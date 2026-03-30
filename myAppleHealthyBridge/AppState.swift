import Foundation

@MainActor
final class AppState: ObservableObject {
    let syncStore: SyncStore
    let healthKitManager: HealthKitManager
    let ingestClient: IngestClient
    let syncCoordinator: SyncCoordinator

    init() {
        let syncStore = SyncStore()
        let healthKitManager = HealthKitManager()
        let ingestClient = IngestClient()

        self.syncStore = syncStore
        self.healthKitManager = healthKitManager
        self.ingestClient = ingestClient
        self.syncCoordinator = SyncCoordinator(
            healthKitManager: healthKitManager,
            syncStore: syncStore,
            ingestClient: ingestClient
        )
    }
}
