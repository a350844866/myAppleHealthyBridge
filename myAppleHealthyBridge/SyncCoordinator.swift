import Foundation
import HealthKit

enum SyncError: LocalizedError {
    case healthDataUnavailable
    case invalidBaseURL
    case invalidServerResponse
    case missingBundleIdentifier
    case serverRejected(String)
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
        case .serverRejected(let message):
            return "Server rejected sync: \(message)"
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

    init(healthKitManager: HealthKitManager, syncStore: SyncStore, ingestClient: IngestClient) {
        self.healthKitManager = healthKitManager
        self.syncStore = syncStore
        self.ingestClient = ingestClient

        authorizationStateText = Self.makeAuthorizationText(
            healthDataAvailable: healthKitManager.isHealthDataAvailable(),
            authorizationState: syncStore.healthAuthorizationState
        )
        observerStateText = "Disabled"
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
        observerStateText = "Disabled"
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
            observerStateText = "Disabled"
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
        isSyncing = true
        defer { isSyncing = false }

        do {
            let settings = syncStore.settings
            let anchorMap = Dictionary(
                uniqueKeysWithValues: healthKitManager.supportedTypeIdentifiers.map { ($0, syncStore.anchor(for: $0)) }
            )

            let results = try await healthKitManager.fetchAllAnchoredSamples(anchors: anchorMap)
            let items = results.values.flatMap(\.samples).sorted { $0.startAt < $1.startAt }

            guard let bundleID = Bundle.main.bundleIdentifier else {
                throw SyncError.missingBundleIdentifier
            }

            let newAnchors = results.compactMapValues(\.newAnchor)
            var encodedAnchors = syncStore.encodedAnchors(for: healthKitManager.supportedTypeIdentifiers)

            for (identifier, anchor) in newAnchors {
                encodedAnchors[identifier] = try syncStore.encodedString(for: anchor)
            }

            let payload = IngestPayload(
                deviceID: settings.deviceID,
                bundleID: bundleID,
                sentAt: .now,
                items: items,
                anchors: encodedAnchors
            )

            latestPayloadPreview = makePayloadPreview(payload)

            _ = try await ingestClient.post(payload: payload, settings: settings)

            for (identifier, anchor) in newAnchors {
                try syncStore.save(anchor: anchor, for: identifier)
            }

            let message = "Sync completed. Uploaded \(items.count) items."
            syncStore.record(result: SyncRunResult(timestamp: .now, message: message, success: true))
        } catch {
            syncStore.record(
                result: SyncRunResult(
                    timestamp: .now,
                    message: error.localizedDescription,
                    success: false
                )
            )
        }
    }

    private func makePayloadPreview(_ payload: IngestPayload) -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let data = try? encoder.encode(payload), let text = String(data: data, encoding: .utf8) else {
            return "Unable to render payload preview."
        }

        return text
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
}
