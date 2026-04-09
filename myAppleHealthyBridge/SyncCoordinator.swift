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
            return "当前设备不支持健康数据。"
        case .invalidBaseURL:
            return "请输入有效的服务端地址。"
        case .invalidServerResponse:
            return "服务端响应无法解析。"
        case .missingBundleIdentifier:
            return "缺少应用包标识。"
        case .missingDeviceIdentifier:
            return "设备编号不能为空。"
        case .observerRegistrationFailed:
            return "健康数据观察器注册失败。"
        case .serverRejected(let message):
            return "服务端拒绝同步：\(message)"
        case .syncCursorNotInitialized:
            return "未找到同步游标。请先恢复服务端游标，或先点「从现在开始」，再执行同步。"
        case .unsupportedSampleType(let identifier):
            return "不支持的健康数据类型：\(identifier)"
        }
    }
}

@MainActor
final class SyncCoordinator: ObservableObject {
    @Published private(set) var isAuthorizing = false
    @Published private(set) var isSyncing = false
    @Published private(set) var backfillBatchCount = 0
    @Published private(set) var backfillSentTotal = 0
    @Published private(set) var backfillServerTotal: Int?
    @Published private(set) var authorizationStateText = "未知"
    @Published private(set) var observerStateText = "已关闭"
    @Published private(set) var latestPayloadPreview = ""

    private let healthKitManager: HealthKitManager
    private let syncStore: SyncStore
    private let ingestClient: IngestClient
    private var pendingObserverTypeIdentifiers: Set<String> = []
    private var retryTask: Task<Void, Never>?
    private var consecutiveFailures = 0
    private static let maxRetryDelay: UInt64 = 120_000_000_000 // 120s
    private static let manualIncrementalBudget = SyncBudget(maxPerType: 200, maxTotal: 1_000)
    private static let backgroundIncrementalBudget = SyncBudget(maxPerType: 40, maxTotal: 240)
    private static let last7DaysBudget = SyncBudget(maxPerType: 120, maxTotal: 500)
    private static let historyBackfillBudget = SyncBudget(maxPerType: 50, maxTotal: 200)
    private var hasStarted = false

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
        guard !hasStarted else { return }
        hasStarted = true
        guard healthKitManager.isHealthDataAvailable() else {
            authorizationStateText = "不可用"
            observerStateText = "不可用"
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
                    message: "恢复同步游标失败：\(error.localizedDescription)",
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
                    message: "健康数据权限已可用。",
                    success: true
                )
            )
        } catch {
            syncStore.recordHealthAuthorizationRequested(success: false)
            authorizationStateText = "失败"
            observerStateText = "已关闭"
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

        _ = await runSync(
            trigger: .manual,
            mode: .incremental,
            changedTypeIdentifier: nil,
            budget: Self.manualIncrementalBudget
        )
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

        _ = await runSync(
            trigger: .backfill,
            mode: .last7Days,
            changedTypeIdentifier: nil,
            budget: Self.last7DaysBudget
        )
    }

    func runBackfillHistory() async {
        guard !syncStore.settings.deviceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            syncStore.record(result: SyncRunResult(
                timestamp: .now,
                message: SyncError.missingDeviceIdentifier.localizedDescription,
                success: false
            ))
            return
        }

        isSyncing = true
        backfillBatchCount = 0
        backfillSentTotal = 0
        backfillServerTotal = nil

        // Fetch server-side total for progress display
        if let overview = try? await fetchServerOverview() {
            backfillServerTotal = overview
        }

        syncStore.record(result: SyncRunResult(
            timestamp: .now,
            message: "开始全量历史回填。将分批上传所有 HealthKit 历史数据，服务端会自动去重已导入的记录。",
            success: true
        ))

        while true {
            backfillBatchCount += 1
            let reachedLimit = await runBackfillBatch(batchNumber: backfillBatchCount)
            if !reachedLimit { break }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }

        isSyncing = false
        backfillBatchCount = 0
        backfillSentTotal = 0
        backfillServerTotal = nil
        await runQueuedObserverSyncIfNeeded()
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
                        message: "这个设备编号在服务端没有同步游标。请使用「从现在开始」建立新的增量游标。",
                        success: false
                    )
                )
            }
            await refreshObserverRegistration()
        } catch {
            syncStore.record(
                result: SyncRunResult(
                    timestamp: .now,
                    message: "恢复服务端游标失败：\(error.localizedDescription)",
                    success: false
                )
            )
        }
    }

    func startFromNow() async {
        let now = Date()
        clearLocalSyncCursor()
        syncStore.setBaselineStartAt(now)
        latestPayloadPreview = "基线开始时间：\(now.ISO8601Format())\n同步模式：从现在开始\n样本数：0"
        syncStore.record(
            result: SyncRunResult(
                timestamp: .now,
                message: "「从现在开始」已初始化。后续同步只会包含开始时间在 \(now.formatted(date: .abbreviated, time: .standard)) 及之后的健康数据样本。",
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
                message: "设备编号已变更。本地同步游标和「从现在开始」基线已清空，请重新恢复服务端游标或重新初始化「从现在开始」。",
                success: true
            )
        )
        await refreshObserverRegistration()
    }

    private func refreshObserverRegistration(forceAutoSyncEnabled: Bool? = nil) async {
        guard healthKitManager.isHealthDataAvailable() else {
            observerStateText = "不可用"
            return
        }

        let autoSyncEnabled = forceAutoSyncEnabled ?? syncStore.settings.autoSyncEnabled
        guard syncStore.healthAuthorizationState.lastRequestSucceeded else {
            observerStateText = autoSyncEnabled ? "等待健康数据权限" : "已关闭"
            return
        }

        guard autoSyncEnabled else {
            await healthKitManager.stopObservers()
            pendingObserverTypeIdentifiers.removeAll()
            syncStore.recordObserverState(isEnabled: false, observedTypeCount: 0, lastErrorMessage: nil)
            observerStateText = "已关闭"
            return
        }

        // Try to restore server anchors, but don't block observer setup if we already
        // have local cursors — network may be temporarily unavailable.
        do {
            _ = try await restoreServerAnchorsIfAvailable(recordResult: false)
        } catch {
            if !hasSyncCursor {
                syncStore.recordObserverState(
                    isEnabled: false,
                    observedTypeCount: 0,
                    lastErrorMessage: error.localizedDescription
                )
                observerStateText = "观察器失败"
                return
            }
            // Have local cursors, proceed with observer setup despite restore failure
        }

        guard hasSyncCursor else {
            observerStateText = "需要游标"
            return
        }

        do {
            let count = try await healthKitManager.startObservers(
                baselineStartAt: syncStore.settings.baselineStartAt
            ) { [weak self] identifier, completionHandler in
                Task { [weak self] in
                    await self?.handleObserverUpdate(identifier: identifier)
                    completionHandler()
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
            observerStateText = "观察器失败"
            syncStore.record(
                result: SyncRunResult(
                    timestamp: .now,
                    message: "观察器初始化失败：\(error.localizedDescription)",
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
            observerStateText = "观察器已就绪 / 自动同步关闭"
            return
        }

        if isSyncing {
            pendingObserverTypeIdentifiers.insert(identifier)
            observerStateText = "检测到变更 / 已排队"
            return
        }

        _ = await runSync(
            trigger: .observer,
            mode: .incremental,
            changedTypeIdentifier: identifier,
            budget: Self.backgroundIncrementalBudget
        )
    }

    /// Called when app returns to foreground — catch up on any missed observer deliveries.
    func handleForegroundReturn() async {
        guard syncStore.settings.autoSyncEnabled, hasSyncCursor, !isSyncing else { return }
        retryTask?.cancel()
        retryTask = nil
        consecutiveFailures = 0
        _ = await runSync(
            trigger: .observer,
            mode: .incremental,
            changedTypeIdentifier: "前台恢复",
            budget: Self.backgroundIncrementalBudget
        )
    }

    /// Called by BGTaskScheduler — periodic background sync to catch missed deliveries.
    func handleBackgroundSync() async -> Bool {
        guard syncStore.settings.autoSyncEnabled, hasSyncCursor, !isSyncing else { return true }
        return await runSync(
            trigger: .backgroundTask,
            mode: .incremental,
            changedTypeIdentifier: "后台定时",
            budget: Self.backgroundIncrementalBudget
        )
    }

    private func scheduleRetry() {
        retryTask?.cancel()
        consecutiveFailures += 1
        let baseDelay: UInt64 = 5_000_000_000 // 5s
        let delay = min(baseDelay * UInt64(1 << min(consecutiveFailures - 1, 5)), Self.maxRetryDelay)
        retryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            await self?.executeRetry()
        }
    }

    private func executeRetry() async {
        guard syncStore.settings.autoSyncEnabled, hasSyncCursor, !isSyncing else { return }
        _ = await runSync(
            trigger: .observer,
            mode: .incremental,
            changedTypeIdentifier: "自动重试(\(consecutiveFailures))",
            budget: Self.backgroundIncrementalBudget
        )
    }

    private enum SyncTrigger {
        case manual
        case observer
        case backgroundTask
        case backfill

        var label: String {
            switch self {
            case .manual:
                return "手动"
            case .observer:
                return "自动"
            case .backgroundTask:
                return "后台"
            case .backfill:
                return "回填"
            }
        }
    }

    private struct SyncBudget {
        let maxPerType: Int
        let maxTotal: Int
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
                return "增量"
            case .last7Days:
                return "最近7天"
            }
        }
    }

    @discardableResult
    private func runSync(
        trigger: SyncTrigger,
        mode: SyncMode,
        changedTypeIdentifier: String?,
        budget: SyncBudget
    ) async -> Bool {
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
                baselineStartAt: baselineStartAt,
                maxPerType: budget.maxPerType,
                maxTotal: budget.maxTotal
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
            let batchDetail = batch.reachedSyncLimit ? " 本批次已封顶以控制内存占用；再次执行可继续回填。" : ""
            let acceptedCount = response.accepted ?? items.count
            let deduplicatedCount = response.deduplicated ?? 0
            let message = "\(trigger.label)同步完成\(triggerDetail)。已上传 \(items.count) 条；服务端接受 \(acceptedCount) 条，去重 \(deduplicatedCount) 条。\(batchDetail)"
            syncStore.record(result: SyncRunResult(timestamp: .now, message: message, success: true))
            observerStateText = Self.makeObserverText(settings: syncStore.settings, runtimeState: syncStore.observerRuntimeState)
            consecutiveFailures = 0
            retryTask?.cancel()
            retryTask = nil
            isSyncing = false
            await runQueuedObserverSyncIfNeeded()
            return true
        } catch {
            syncStore.record(
                result: SyncRunResult(
                    timestamp: .now,
                    message: "\(trigger.label)同步失败：\(error.localizedDescription)",
                    success: false
                )
            )
            if case .observer = trigger {
                observerStateText = "同步失败，将自动重试"
                scheduleRetry()
            }
            if case .backgroundTask = trigger {
                observerStateText = "同步失败，将自动重试"
                scheduleRetry()
            }
            isSyncing = false
            await runQueuedObserverSyncIfNeeded()
            return false
        }
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
                    message: "已为设备编号 \(deviceID) 恢复 \(response.anchors.count) 个服务端游标。",
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
            "模式：\(modeLabel)",
            "设备编号：\(payload.deviceID)",
            "应用包标识：\(payload.bundleID)",
            "发送时间：\(payload.sentAt.ISO8601Format())",
            "样本数：\(payload.items.count)",
            "游标数：\(payload.anchors.count)",
            "类型数：\(countsByType.count)"
        ]

        if let baselineStartAt {
            lines.append("基线开始时间：\(baselineStartAt.ISO8601Format())")
        }

        if !countsByType.isEmpty {
            lines.append("类型分布：")
            for (type, count) in countsByType.sorted(by: { $0.key < $1.key }) {
                lines.append("- \(Self.shortTypeName(type)): \(count)")
            }
        }

        if !previewItems.isEmpty {
            lines.append("预览样本：")
            for item in previewItems {
                let valueText = item.value.map { String($0) } ?? "空"
                let unitText = item.unit ?? "空"
                lines.append("- \(Self.shortTypeName(item.type)) | \(item.startAt.ISO8601Format()) | 数值=\(valueText) | 单位=\(unitText)")
            }
        }

        if payload.items.count > previewItems.count {
            lines.append("预览已截断：当前展示 \(previewItems.count) / \(payload.items.count) 条")
        }

        return lines.joined(separator: "\n")
    }

    // Returns true if sync limit was reached and another batch should follow.
    private func runBackfillBatch(batchNumber: Int) async -> Bool {
        do {
            let settings = syncStore.settings
            let anchorMap: [String: HKQueryAnchor?] = Dictionary(
                uniqueKeysWithValues: healthKitManager.supportedTypeIdentifiers.map {
                    ($0, syncStore.anchor(for: $0))
                }
            )

            let batch = try await healthKitManager.fetchAllAnchoredSamples(
                anchors: anchorMap,
                baselineStartAt: nil,
                maxPerType: Self.historyBackfillBudget.maxPerType,
                maxTotal: Self.historyBackfillBudget.maxTotal
            )
            let results = batch.results
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

            latestPayloadPreview = makePayloadPreview(
                payload,
                modeLabel: "全量回填（第 \(batchNumber) 批）",
                baselineStartAt: nil
            )

            // If no items fetched, we're done regardless of reachedSyncLimit
            if items.isEmpty {
                syncStore.record(result: SyncRunResult(
                    timestamp: .now,
                    message: "全量历史回填完成，共 \(batchNumber - 1) 批，累计发送 \(backfillSentTotal) 条。",
                    success: true
                ))
                return false
            }

            let response = try await ingestClient.post(payload: payload, settings: settings)

            for (identifier, anchor) in newAnchors {
                try syncStore.save(anchor: anchor, for: identifier)
            }

            backfillSentTotal += items.count

            let acceptedCount = response.accepted ?? items.count
            let deduplicatedCount = response.deduplicated ?? 0
            let progressText: String
            if let serverTotal = backfillServerTotal, serverTotal > 0 {
                progressText = " [\(backfillSentTotal)/\(serverTotal)]"
            } else {
                progressText = " [已发送 \(backfillSentTotal)]"
            }
            let contMsg = batch.reachedSyncLimit ? " 继续下一批..." : " 全部回填完成。"
            syncStore.record(result: SyncRunResult(
                timestamp: .now,
                message: "回填第 \(batchNumber) 批\(progressText)：上传 \(items.count) 条，接受 \(acceptedCount)，去重 \(deduplicatedCount)。\(contMsg)",
                success: true
            ))

            return batch.reachedSyncLimit
        } catch {
            syncStore.record(result: SyncRunResult(
                timestamp: .now,
                message: "全量回填第 \(batchNumber) 批失败：\(error.localizedDescription)",
                success: false
            ))
            return false
        }
    }

    private func fetchServerOverview() async throws -> Int? {
        let settings = syncStore.settings
        guard let baseURL = URL(string: settings.baseURLString), !settings.baseURLString.isEmpty else {
            return nil
        }
        let url = baseURL.appending(path: "api/stats/overview")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            return nil
        }
        struct OverviewRecords: Decodable {
            let total_records: Int?
        }
        struct OverviewResponse: Decodable {
            let records: OverviewRecords?
        }
        let overview = try JSONDecoder().decode(OverviewResponse.self, from: data)
        return overview.records?.total_records
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
        // Don't clear yet — runSync will set isSyncing, and if it fails
        // the retry mechanism will handle it. Clear only after we start.
        pendingObserverTypeIdentifiers.removeAll()

        let changedTypeIdentifier: String?
        if queuedIdentifiers.count == 1 {
            changedTypeIdentifier = queuedIdentifiers.first
        } else {
            changedTypeIdentifier = "\(queuedIdentifiers.count) 个待处理类型"
        }

        observerStateText = "正在处理排队中的变更"
        _ = await runSync(
            trigger: .observer,
            mode: .incremental,
            changedTypeIdentifier: changedTypeIdentifier,
            budget: Self.backgroundIncrementalBudget
        )
    }

    private static func makeAuthorizationText(
        healthDataAvailable: Bool,
        authorizationState: HealthAuthorizationState
    ) -> String {
        guard healthDataAvailable else {
            return "不可用"
        }

        guard authorizationState.hasRequestedAccess else {
            return "就绪"
        }

        return authorizationState.lastRequestSucceeded ? "已授权" : "失败"
    }

    private static func makeObserverText(settings: SyncSettings, runtimeState: ObserverRuntimeState) -> String {
        guard settings.autoSyncEnabled else {
            return "已关闭"
        }

        guard runtimeState.isEnabled else {
            if let lastErrorMessage = runtimeState.lastErrorMessage, !lastErrorMessage.isEmpty {
                return "失败"
            }
            return "等待中"
        }

        if let lastTriggerType = runtimeState.lastTriggerType {
            return "监听中 \(runtimeState.observedTypeCount) 个 / 最近 \(shortTypeName(lastTriggerType))"
        }

        return "监听中 \(runtimeState.observedTypeCount) 个"
    }

    private static func shortTypeName(_ identifier: String) -> String {
        identifier
            .replacingOccurrences(of: "HKQuantityTypeIdentifier", with: "")
            .replacingOccurrences(of: "HKCategoryTypeIdentifier", with: "")
            .replacingOccurrences(of: "HKWorkoutActivityType", with: "")
    }
}
