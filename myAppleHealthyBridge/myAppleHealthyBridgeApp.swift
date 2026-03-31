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

    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        if identifier == BackgroundIngestUploader.shared.session.configuration.identifier {
            BackgroundIngestUploader.shared.setBackgroundEventsCompletionHandler(completionHandler)
        } else {
            completionHandler()
        }
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
                _ = BackgroundTaskManager.scheduleAll()
            default:
                break
            }
        }
    }
}
