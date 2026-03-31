import SwiftUI

@main
struct myAppleHealthyBridgeApp: App {
    @StateObject private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task {
                    await appState.syncCoordinator.handleForegroundReturn()
                }
            }
        }
    }
}
