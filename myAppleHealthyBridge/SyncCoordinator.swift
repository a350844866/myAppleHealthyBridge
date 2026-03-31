import Foundation
import HealthKit

enum SyncError: LocalizedError {
    case healthDataUnavailable
    case invalidBaseURL
    case invalidServerResponse
    case missingBundleIdentifier
    case missingDeviceIdentifier
    case observerRegistrationFailed
    case serverRejected(String)
    case syncCursorNotInitialized
    case unsupportedSampleType(String)

    var errorDescription: String? {
        switch self {
        case .healthDataUnavailable:
            return "Health data is not available on this device."
        case .invalidBaseURL:
            return "Please enter a valid server base URL."
        case .invalidServerResponse:
            return "Server response could not be parsed."
        case .missingBundleIdentifier:
            return "Bundle identifier is missing."
        case .missingDeviceIdentifier:
            return "Device ID is required."
        case .observerRegistrationFailed:
            return "HealthKit observer registration failed."
        case .serverRejected(let message):
            return "Server rejected sync: \(message)"
        case .syncCursorNotInitialized:
            return "No sync cursor found. Restore server anchors or tap Start From Now before syncing."
        case .unsupportedSampleType(let identifier):
            return "Unsupported HealthKit type: \(identifier)"
        }
    }
}

@MainActor
final class SyncCoordinator: ObservableObject {
    @Published private(set) var isAuthorizing = false
    @Published private(set) var isSyncing = false
    @Published private(set) var authorizationStateText = "Unknown"
    @Published private(set) var observerStateText = "Disabled"
    @Published private(set) var latestPayloadPreview = ""

    private let healthKitManager: HealthKitManager
    private let syncStore: SyncStore
    private let ingestClient: IngestClient
    private var pendingObserverTypeIdentifiers: Set<String> = []

    init(healthKitManager: HealthKitManager, syncStore: SyncStore, ingestClient: IngestClient) {
        self.healthKitManager = healthKitManager
        self.syncStore = syncStore
        self.ingestClient = ingestClient

        authorizationStateText = Self.makeAuthorizationText(
            healthDataAvailable: healthKitManager.isHealthDataAvailable(),
            authorizationState: syncStore.healthAuthorizationState
        )
        observerStateText = Self.makeObserverText(settings: syncStore.settings, runtimeState: syncStore.observerRuntimeState)
    }

    func start() async {
        guard healthKitManager.isHealthDataAvailable() else {
            authorizationStateText = "Unavailable"
            observerStateText = "Unavailable"
            return
        }

        authorizationStateText = Self.makeAuthorizationText(
            healthDataAvailable: true,
            authorizationState: syncStore.healthAuthorizationState
        )
        observerStateText = Self.makeObserverText(settings: syncStore.settings, runtimeState: syncStore.observerRuntimeState)
        do {
            _ = try await restoreServerAnchorsIfAvailable(recordResult: false)
        } catch {
            syncStore.record(
                result: SyncRunResult(
                    timestamp: .now,
                    message: "Cursor restore failed: \(error.localizedDescription)",
                    success: false
                )
            )
        }
        await refreshObserverRegistration()
    }

    func requestAuthorization() async {
        isAuthorizing = true
        defer { isAuthorizing = false }

        do {
            try await healthKitManager.requestAuthorization()
            syncStore.recordHealthAuthorizationRequested(success: true)
            authorizationStateText = Self.makeAuthorizationText(
                healthDataAvailable: true,
                authorizationState: syncStore.healthAuthorizationState
            )
            await refreshObserverRegistration()
            syncStore.record(
                result: SyncRunResult(
                    timestamp: .now,
                    message: "HealthKit access is available.",
                    success: true
                )
            )
        } catch {
            syncStore.recordHealthAuthorizationRequested(success: false)
            authorizationStateText = "Failed"
            observerStateText = "Disabled"
            syncStore.record(
                result: SyncRunResult(
                    timestamp: .now,
                    message: error.localizedDescription,
                    success: false
                )
            )
        }
    }

    func runManualSync() async {
        do {
            try await ensureSyncCursorReady(allowServerRestore: true)
        } catch {
            syncStore.record(
                result: SyncRunResult(
                    timestamp: .now,
                    message: error.localizedDescription,
                    success: false
                )
            )
            return
        }

        await runSync(trigger: .manual, mode: .incremental, changedTypeIdentifier: nil)
    }

    func uploadLast7Days() async {
        guard !syncStore.settings.deviceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            syncStore.record(
                result: SyncRunResult(
                    timestamp: .now,
                    message: SyncError.missingDeviceIdentifier.localizedDescription,
                    success: false
                )
            )
            return
        }

        await runSync(trigger: .backfill, mode: .last7Days, changedTypeIdentifier: nil)
    }

    func updateAutoSync(enabled: Bool) async {
        await refreshObserverRegistration(forceAutoSyncEnabled: enabled)
    }

    func restoreServerAnchors() async {
        do {
            let restored = try await restoreServerAnchorsIfAvailable(recordResult: true)
            if !restored {
                syncStore.record(
                    result: SyncRunResult(
                        timestamp: .now,
                        message: "No server anchors found for this Device ID. Use Start From Now to establish a new incremental cursor.",
                        success: false
                    )
                )
            }
            await refreshObserverRegistration()
        } catch {
            syncStore.record(
                result: SyncRunResult(
                    timestamp: .now,
                    message: "Restore server anchors failed: \(error.localizedDescription)",
                    success: false
                )
            )
        }
    }

    func startFromNow() async {
        let now = Date()
        clearLocalSyncCursor()
        syncStore.setBaselineStartAt(now)
        latestPayloadPreview = "baseline_start_at: \(now.ISO8601Format())\nmode: start_from_now\nitems: 0"
        syncStore.record(
            result: SyncRunResult(
                timestamp: .now,
                message: "Start From Now initialized. Future syncs will only include HealthKit samples whose start time is on or after \(now.formatted(date: .abbreviated, time: .standard)).",
                success: true
            )
        )
        await refreshObserverRegistration()
    }

    func didChangeDeviceID() async {
        clearLocalSyncCursor()
        latestPayloadPreview = ""
        syncStore.record(
            result: SyncRunResult(
                timestamp: .now,
                message: "Device ID changed. Local anchors and Start From Now baseline were cleared. Restore server anchors or initialize Start From Now again.",
                success: true
            )
        )
        await refreshObserverRegistration()
    }

    private func refreshObserverRegistration(forceAutoSyncEnabled: Bool? = nil) async {
        guard healthKitManager.isHealthDataAvailable() else {
            observerStateText = "Unavailable"
            return
        }

        let autoSyncEnabled = forceAutoSyncEnabled ?? syncStore.settings.autoSyncEnabled
        guard syncStore.healthAuthorizationState.lastRequestSucceeded else {
            observerStateText = autoSyncEnabled ? "Waiting for HealthKit access" : "Disabled"
            return
        }

        guard autoSyncEnabled else {
            await healthKitManager.stopObservers()
            pendingObserverTypeIdentifiers.removeAll()
            syncStore.recordObserverState(isEnabled: false, observedTypeCount: 0, lastErrorMessage: nil)
            observerStateText = "Disabled"
            return
        }

        do {
            _ = try await restoreServerAnchorsIfAvailable(recordResult: false)
        } catch {
            syncStore.recordObserverState(
                isEnabled: false,
                observedTypeCount: 0,
                lastErrorMessage: error.localizedDescription
            )
            observerStateText = "Observer failed"
            return
        }

        guard hasSyncCursor else {
            observerStateText = "Needs cursor"
            return
        }

        do {
            let count = try await healthKitManager.startObservers(
                baselineStartAt: syncStore.settings.baselineStartAt
            ) { [weak self] identifier in
                Task { [weak self] in
                    await self?.handleObserverUpdate(identifier: identifier)
                }
            }
            syncStore.recordObserverState(isEnabled: true, observedTypeCount: count, lastErrorMessage: nil)
            observerStateText = Self.makeObserverText(settings: syncStore.settings, runtimeState: syncStore.observerRuntimeState)
        } catch {
            syncStore.recordObserverState(
                isEnabled: false,
                observedTypeCount: 0,
                lastErrorMessage: error.localizedDescription
            )
            observerStateText = "Observer failed"
            syncStore.record(
                result: SyncRunResult(
                    timestamp: .now,
                    message: "Observer setup failed: \(error.localizedDescription)",
                    success: false
                )
            )
        }
    }

    private func handleObserverUpdate(identifier: String) async {
        syncStore.recordObserverState(
            isEnabled: true,
            observedTypeCount: syncStore.observerRuntimeState.observedTypeCount,
            lastTriggerAt: .now,
            lastTriggerType: identifier,
            lastErrorMessage: nil
        )
        observerStateText = Self.makeObserverText(settings: syncStore.settings, runtimeState: syncStore.observerRuntimeState)

        guard syncStore.settings.autoSyncEnabled else {
            pendingObserverTypeIdentifiers.removeAll()
            observerStateText = "Observer ready / auto sync off"
            return
        }

        if isSyncing {
            pendingObserverTypeIdentifiers.insert(identifier)
            observerStateText = "Change detected / queued"
            return
        }

        await runSync(trigger: .observer, mode: .incremental, changedTypeIdentifier: identifier)
    }

    private enum SyncTrigger {
        case manual
        case observer
        case backfill

        var label: String {
            switch self {
            case .manual:
                return "Manual"
            case .observer:
                return "Auto"
            case .backfill:
                return "Backfill"
            }
        }
    }

    private enum SyncMode {
        case incremental
        case last7Days

        var baselineStartAt: Date? {
            switch self {
            case .incremental:
                return nil
            case .last7Days:
                return Calendar.current.date(byAdding: .day, value: -7, to: Date())
            }
        }

        var preservesCursor: Bool {
            switch self {
            case .incremental:
                return false
            case .last7Days:
                return true
            }
        }

        var previewLabel: String {
            switch self {
            case .incremental:
                return "incremental"
            case .last7Days:
                return "last_7_days"
            }
        }
    }

    private func runSync(trigger: SyncTrigger, mode: SyncMode, changedTypeIdentifier: String?) async {
        isSyncing = true

        do {
            let settings = syncStore.settings
            let baselineStartAt = mode.baselineStartAt ?? settings.baselineStartAt
            let anchorMap: [String: HKQueryAnchor?] = Dictionary(
                uniqueKeysWithValues: healthKitManager.supportedTypeIdentifiers.map {
                    ($0, mode.preservesCursor ? nil : syncStore.anchor(for: $0))
                }
            )

            let batch = try await healthKitManager.fetchAllAnchoredSamples(
                anchors: anchorMap,
                baselineStartAt: baselineStartAt
            )
            let results = batch.results
            let items = results.values.flatMap(\.samples).sorted { $0.startAt < $1.startAt }

            guard let bundleID = Bundle.main.bundleIdentifier else {
                throw SyncError.missingBundleIdentifier
            }

            let newAnchors = results.compactMapValues(\.newAnchor)
            var encodedAnchors = syncStore.encodedAnchors(for: healthKitManager.supportedTypeIdentifiers)

            if !mode.preservesCursor {
                for (identifier, anchor) in newAnchors {
                    encodedAnchors[identifier] = try syncStore.encodedString(for: anchor)
                }
            }

            let payload = IngestPayload(
                deviceID: settings.deviceID,
                bundleID: bundleID,
                sentAt: .now,
                items: items,
                anchors: encodedAnchors
            )

            latestPayloadPreview = makePayloadPreview(
                payload,
                modeLabel: mode.previewLabel,
                baselineStartAt: baselineStartAt
            )

            let response = try await ingestClient.post(payload: payload, settings: settings)

            if !mode.preservesCursor {
                for (identifier, anchor) in newAnchors {
                    try syncStore.save(anchor: anchor, for: identifier)
                }
            }

            let triggerDetail = changedTypeIdentifier.map { " (\($0))" } ?? ""
            let batchDetail = batch.reachedSyncLimit ? " Batch capped to reduce memory use; run sync again to continue backfill." : ""
            let acceptedCount = response.accepted ?? items.count
            let deduplicatedCount = response.deduplicated ?? 0
            let message = "\(trigger.label) sync completed\(triggerDetail). Uploaded \(items.count) items; server accepted \(acceptedCount), deduplicated \(deduplicatedCount).\(batchDetail)"
            syncStore.record(result: SyncRunResult(timestamp: .now, message: message, success: true))
            observerStateText = Self.makeObserverText(settings: syncStore.settings, runtimeState: syncStore.observerRuntimeState)
        } catch {
            syncStore.record(
                result: SyncRunResult(
                    timestamp: .now,
                    message: "\(trigger.label) sync failed: \(error.localizedDescription)",
                    success: false
                )
            )
            if case .observer = trigger {
                observerStateText = "Observer sync failed"
            }
        }

        isSyncing = false
        await runQueuedObserverSyncIfNeeded()
    }

    private var hasSyncCursor: Bool {
        syncStore.settings.baselineStartAt != nil
        || syncStore.hasAnyAnchors(for: healthKitManager.supportedTypeIdentifiers)
    }

    private func ensureSyncCursorReady(allowServerRestore: Bool) async throws {
        guard !syncStore.settings.deviceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SyncError.missingDeviceIdentifier
        }

        if hasSyncCursor {
            return
        }

        if allowServerRestore, try await restoreServerAnchorsIfAvailable(recordResult: false) {
            return
        }

        throw SyncError.syncCursorNotInitialized
    }

    private func restoreServerAnchorsIfAvailable(recordResult: Bool) async throws -> Bool {
        guard !hasSyncCursor else {
            return true
        }

        let settings = syncStore.settings
        let deviceID = settings.deviceID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !deviceID.isEmpty else {
            throw SyncError.missingDeviceIdentifier
        }

        guard let bundleID = Bundle.main.bundleIdentifier else {
            throw SyncError.missingBundleIdentifier
        }

        guard let response = try await ingestClient.fetchRemoteAnchors(
            deviceID: deviceID,
            bundleID: bundleID,
            settings: settings
        ) else {
            return false
        }

        let supportedIdentifiers = Set(healthKitManager.supportedTypeIdentifiers)
        syncStore.removeAnchors(for: healthKitManager.supportedTypeIdentifiers)
        syncStore.setBaselineStartAt(nil)

        for (identifier, encodedAnchor) in response.anchors where supportedIdentifiers.contains(identifier) {
            syncStore.save(encodedAnchor: encodedAnchor, for: identifier)
        }

        if recordResult {
            syncStore.record(
                result: SyncRunResult(
                    timestamp: .now,
                    message: "Restored \(response.anchors.count) server anchors for Device ID \(deviceID).",
                    success: true
                )
            )
        }

        return true
    }

    private func clearLocalSyncCursor() {
        syncStore.removeAnchors(for: healthKitManager.supportedTypeIdentifiers)
        syncStore.setBaselineStartAt(nil)
        pendingObserverTypeIdentifiers.removeAll()
    }

    private func makePayloadPreview(
        _ payload: IngestPayload,
        modeLabel: String,
        baselineStartAt: Date?
    ) -> String {
        let previewItems = Array(payload.items.prefix(8))
        let countsByType = payload.items.reduce(into: [String: Int]()) { counts, item in
            counts[item.type, default: 0] += 1
        }

        var lines: [String] = [
            "mode: \(modeLabel)",
            "device_id: \(payload.deviceID)",
            "bundle_id: \(payload.bundleID)",
            "sent_at: \(payload.sentAt.ISO8601Format())",
            "item_count: \(payload.items.count)",
            "anchor_count: \(payload.anchors.count)",
            "types: \(countsByType.count)"
        ]

        if let baselineStartAt {
            lines.append("baseline_start_at: \(baselineStartAt.ISO8601Format())")
        }

        if !countsByType.isEmpty {
            lines.append("counts_by_type:")
            for (type, count) in countsByType.sorted(by: { $0.key < $1.key }) {
                lines.append("- \(Self.shortTypeName(type)): \(count)")
            }
        }

        if !previewItems.isEmpty {
            lines.append("preview_items:")
            for item in previewItems {
                let valueText = item.value.map { String($0) } ?? "nil"
                let unitText = item.unit ?? "nil"
                lines.append("- \(Self.shortTypeName(item.type)) | \(item.startAt.ISO8601Format()) | value=\(valueText) | unit=\(unitText)")
            }
        }

        if payload.items.count > previewItems.count {
            lines.append("preview_truncated: showing \(previewItems.count) of \(payload.items.count) items")
        }

        return lines.joined(separator: "\n")
    }

    private func runQueuedObserverSyncIfNeeded() async {
        guard syncStore.settings.autoSyncEnabled else {
            pendingObserverTypeIdentifiers.removeAll()
            return
        }

        guard !pendingObserverTypeIdentifiers.isEmpty else {
            return
        }

        let queuedIdentifiers = pendingObserverTypeIdentifiers
        pendingObserverTypeIdentifiers.removeAll()

        let changedTypeIdentifier: String?
        if queuedIdentifiers.count == 1 {
            changedTypeIdentifier = queuedIdentifiers.first
        } else {
            changedTypeIdentifier = "\(queuedIdentifiers.count) pending types"
        }

        observerStateText = "Processing queued changes"
        await runSync(trigger: .observer, mode: .incremental, changedTypeIdentifier: changedTypeIdentifier)
    }

    private static func makeAuthorizationText(
        healthDataAvailable: Bool,
        authorizationState: HealthAuthorizationState
    ) -> String {
        guard healthDataAvailable else {
            return "Unavailable"
        }

        guard authorizationState.hasRequestedAccess else {
            return "Ready"
        }

        return authorizationState.lastRequestSucceeded ? "Authorized" : "Failed"
    }

    private static func makeObserverText(settings: SyncSettings, runtimeState: ObserverRuntimeState) -> String {
        guard settings.autoSyncEnabled else {
            return "Disabled"
        }

        guard runtimeState.isEnabled else {
            if let lastErrorMessage = runtimeState.lastErrorMessage, !lastErrorMessage.isEmpty {
                return "Failed"
            }
            return "Pending"
        }

        if let lastTriggerType = runtimeState.lastTriggerType {
            return "Watching \(runtimeState.observedTypeCount) / last \(shortTypeName(lastTriggerType))"
        }

        return "Watching \(runtimeState.observedTypeCount)"
    }

    private static func shortTypeName(_ identifier: String) -> String {
        identifier
            .replacingOccurrences(of: "HKQuantityTypeIdentifier", with: "")
            .replacingOccurrences(of: "HKCategoryTypeIdentifier", with: "")
    }
}
