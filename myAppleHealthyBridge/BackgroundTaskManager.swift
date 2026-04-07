import BackgroundTasks
import Foundation

enum BackgroundTaskManager {
    static let refreshIdentifier = "com.example.myAppleHealthyBridge.sync-refresh"
    static let processingIdentifier = "com.example.myAppleHealthyBridge.sync-processing"

    static func registerTasks(syncAction: @escaping () async -> Bool) {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: refreshIdentifier,
            using: nil
        ) { task in
            guard let task = task as? BGAppRefreshTask else { return }
            handleRefreshTask(task, syncAction: syncAction)
        }

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: processingIdentifier,
            using: nil
        ) { task in
            guard let task = task as? BGProcessingTask else { return }
            handleProcessingTask(task, syncAction: syncAction)
        }
    }

    @discardableResult
    static func scheduleRefresh() -> Bool {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: refreshIdentifier)
        let request = BGAppRefreshTaskRequest(identifier: refreshIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 15 min
        do {
            try BGTaskScheduler.shared.submit(request)
            return true
        } catch {
            print("[BGTask] 调度失败: \(error)")
            return false
        }
    }

    @discardableResult
    static func scheduleProcessing() -> Bool {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: processingIdentifier)
        let request = BGProcessingTaskRequest(identifier: processingIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60) // 1 hour
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        do {
            try BGTaskScheduler.shared.submit(request)
            return true
        } catch {
            print("[BGTask] 调度失败: \(error)")
            return false
        }
    }

    @discardableResult
    static func scheduleAll() -> Bool {
        let refreshOK = scheduleRefresh()
        let processingOK = scheduleProcessing()
        return refreshOK || processingOK
    }

    private static func handleRefreshTask(
        _ task: BGAppRefreshTask,
        syncAction: @escaping () async -> Bool
    ) {
        // Schedule next refresh before doing work
        scheduleRefresh()

        let syncTask = Task {
            await syncAction()
        }

        task.expirationHandler = {
            syncTask.cancel()
        }

        Task {
            let success = await syncTask.value
            task.setTaskCompleted(success: success)
        }
    }

    private static func handleProcessingTask(
        _ task: BGProcessingTask,
        syncAction: @escaping () async -> Bool
    ) {
        // Schedule next processing task
        scheduleProcessing()

        let syncTask = Task {
            await syncAction()
        }

        task.expirationHandler = {
            syncTask.cancel()
        }

        Task {
            let success = await syncTask.value
            task.setTaskCompleted(success: success)
        }
    }
}
