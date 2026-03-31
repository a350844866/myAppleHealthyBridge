import SwiftUI

class AppDelegate: NSObject, UIApplicationDelegate {
    var appState: AppState?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let state = AppState()
        appState = state
        BackgroundTaskManager.registerTasks {
            await state.syncCoordinator.handleBackgroundSync()
        }
        return true
    }
}

@main
struct myAppleHealthyBridgeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            if let appState = appDelegate.appState {
                ContentView()
                    .environmentObject(appState)
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard let appState = appDelegate.appState else { return }
            switch newPhase {
            case .active:
                Task { await appState.syncCoordinator.handleForegroundReturn() }
            case .background:
                BackgroundTaskManager.scheduleAll()
            default:
                break
            }
        }
    }
}
