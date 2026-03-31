import BackgroundTasks
import Foundation

enum BackgroundTaskManager {
    static let refreshIdentifier = "com.example.myAppleHealthyBridge.sync-refresh"
    static let processingIdentifier = "com.example.myAppleHealthyBridge.sync-processing"

    static func registerTasks(syncAction: @escaping () async -> Void) {
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

    static func scheduleRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 15 min
        try? BGTaskScheduler.shared.submit(request)
    }

    static func scheduleProcessing() {
        let request = BGProcessingTaskRequest(identifier: processingIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60) // 1 hour
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        try? BGTaskScheduler.shared.submit(request)
    }

    static func scheduleAll() {
        scheduleRefresh()
        scheduleProcessing()
    }

    private static func handleRefreshTask(
        _ task: BGAppRefreshTask,
        syncAction: @escaping () async -> Void
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
            await syncTask.value
            task.setTaskCompleted(success: true)
        }
    }

    private static func handleProcessingTask(
        _ task: BGProcessingTask,
        syncAction: @escaping () async -> Void
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
            await syncTask.value
            task.setTaskCompleted(success: true)
        }
    }
}
