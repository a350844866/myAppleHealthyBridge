import SwiftUI

struct ContentView: View {
    private struct FeedbackAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    private enum UserAction {
        case saveSettings
        case restoreServerAnchors
        case startFromNow
        case manualSync
        case backfillLastWeek
    }

    @EnvironmentObject private var appState: AppState

    @State private var baseURL: String = ""
    @State private var apiToken: String = ""
    @State private var basicAuthUsername: String = ""
    @State private var basicAuthPassword: String = ""
    @State private var deviceID: String = ""
    @State private var autoSyncEnabled = false
    @State private var feedbackAlert: FeedbackAlert?
    @State private var activeAction: UserAction?

    var body: some View {
        NavigationStack {
            Form {
                Section("HealthKit") {
                    LabeledContent("Availability", value: appState.syncCoordinator.authorizationStateText)
                    LabeledContent("Observer", value: appState.syncCoordinator.observerStateText)

                    Toggle("Enable Auto Sync", isOn: $autoSyncEnabled)

                    Text("调试阶段建议先保持手动同步。只有打开自动同步后，App 才会注册 HealthKit observer 并在检测到变更时自动跑增量同步。")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button(appState.syncCoordinator.isAuthorizing ? "Requesting..." : "Request HealthKit Access") {
                        Task {
                            await appState.syncCoordinator.requestAuthorization()
                            presentResultAlert(
                                fallbackTitle: "HealthKit Access",
                                fallbackMessage: "HealthKit authorization request finished."
                            )
                        }
                    }
                    .disabled(appState.syncCoordinator.isAuthorizing || activeAction != nil)
                }

                Section("Server") {
                    TextField("Base URL", text: $baseURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    SecureField("API Token", text: $apiToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    TextField("Basic Auth Username", text: $basicAuthUsername)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    SecureField("Basic Auth Password", text: $basicAuthPassword)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    TextField("Device ID", text: $deviceID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Text("Device ID 代表一条长期稳定的增量同步游标，不是临时会话 ID。正式开始同步后不要随意改。")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("如果公网入口启用了 Nginx Basic Auth，就填 Basic 用户名和密码。当前客户端会优先发送 Basic Authorization；只有未填写 Basic Auth 时，才会发送 API Token 的 Bearer Authorization。")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button(activeAction == .saveSettings ? "Saving..." : "Save Settings") {
                        activeAction = .saveSettings
                        let deviceIDChanged = appState.syncStore.updateSettings(
                            baseURLString: baseURL,
                            apiToken: apiToken,
                            basicAuthUsername: basicAuthUsername,
                            basicAuthPassword: basicAuthPassword,
                            deviceID: deviceID,
                            autoSyncEnabled: autoSyncEnabled
                        )

                        Task {
                            if deviceIDChanged {
                                await appState.syncCoordinator.didChangeDeviceID()
                            }
                            await appState.syncCoordinator.updateAutoSync(enabled: autoSyncEnabled)
                            activeAction = nil
                            feedbackAlert = FeedbackAlert(
                                title: "Settings Saved",
                                message: deviceIDChanged
                                ? "Server settings have been saved. Because Device ID changed, local anchors and Start From Now baseline were cleared. Restore server anchors or initialize Start From Now again before syncing."
                                : "Server settings have been saved."
                            )
                        }
                    }
                    .disabled(appState.syncCoordinator.isAuthorizing || appState.syncCoordinator.isSyncing || activeAction != nil)
                }

                Section("Sync") {
                    Button(activeAction == .restoreServerAnchors ? "Restoring..." : "Restore Server Anchors") {
                        activeAction = .restoreServerAnchors
                        Task {
                            await appState.syncCoordinator.restoreServerAnchors()
                            activeAction = nil
                            presentResultAlert(
                                fallbackTitle: "Restore Server Anchors",
                                fallbackMessage: "Server anchor restore finished."
                            )
                        }
                    }
                    .disabled(appState.syncCoordinator.isAuthorizing || appState.syncCoordinator.isSyncing || activeAction != nil)

                    Button(activeAction == .startFromNow ? "Initializing..." : "Start From Now") {
                        activeAction = .startFromNow
                        Task {
                            await appState.syncCoordinator.startFromNow()
                            activeAction = nil
                            presentResultAlert(
                                fallbackTitle: "Start From Now",
                                fallbackMessage: "Incremental baseline has been initialized."
                            )
                        }
                    }
                    .disabled(appState.syncCoordinator.isAuthorizing || appState.syncCoordinator.isSyncing || activeAction != nil)

                    Button(activeAction == .manualSync || appState.syncCoordinator.isSyncing ? "Syncing..." : "Run Manual Sync") {
                        activeAction = .manualSync
                        Task {
                            await appState.syncCoordinator.runManualSync()
                            activeAction = nil
                            presentResultAlert(
                                fallbackTitle: "Manual Sync",
                                fallbackMessage: "Manual sync finished."
                            )
                        }
                    }
                    .disabled(appState.syncCoordinator.isAuthorizing || appState.syncCoordinator.isSyncing || activeAction != nil)

                    Button(activeAction == .backfillLastWeek || appState.syncCoordinator.isSyncing ? "Uploading..." : "Upload Last 7 Days") {
                        activeAction = .backfillLastWeek
                        Task {
                            await appState.syncCoordinator.uploadLast7Days()
                            activeAction = nil
                            presentResultAlert(
                                fallbackTitle: "Upload Last 7 Days",
                                fallbackMessage: "Last 7 days upload finished."
                            )
                        }
                    }
                    .disabled(appState.syncCoordinator.isAuthorizing || appState.syncCoordinator.isSyncing || activeAction != nil)

                    Text("没有本地或服务端游标时，Run Manual Sync 不会再扫全历史。先点 Restore Server Anchors；如果服务端也没有游标，再点 Start From Now。")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("`Upload Last 7 Days` 是一次性历史回填，不会改写当前增量游标；适合在 Start From Now 之后补最近一周数据。")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let result = appState.syncStore.lastSyncResult {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(result.success ? "Success" : "Failure")
                                .font(.headline)
                            Text(result.timestamp.formatted(date: .abbreviated, time: .standard))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(result.message)
                                .font(.body)
                        }
                    }
                }

                Section("Recent Sync") {
                    NavigationLink("View Recent Synced Data") {
                        RecentSyncedDataView()
                            .environmentObject(appState)
                    }

                    Text("Open a server-backed overview of the latest synced samples for the current Device ID.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Payload Preview") {
                    if appState.syncCoordinator.latestPayloadPreview.isEmpty {
                        Text("No payload generated yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ScrollView(.horizontal) {
                            Text(appState.syncCoordinator.latestPayloadPreview)
                                .font(.system(.footnote, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            .navigationTitle("Health Bridge")
            .alert(item: $feedbackAlert) { feedback in
                Alert(
                    title: Text(feedback.title),
                    message: Text(feedback.message),
                    dismissButton: .default(Text("OK"))
                )
            }
            .onAppear {
                let settings = appState.syncStore.settings
                baseURL = settings.baseURLString
                apiToken = settings.apiToken
                basicAuthUsername = settings.basicAuthUsername
                basicAuthPassword = settings.basicAuthPassword
                deviceID = settings.deviceID
                autoSyncEnabled = settings.autoSyncEnabled

                Task {
                    await appState.syncCoordinator.start()
                }
            }
        }
    }
}

private extension ContentView {
    func presentResultAlert(fallbackTitle: String, fallbackMessage: String) {
        if let result = appState.syncStore.lastSyncResult {
            feedbackAlert = FeedbackAlert(
                title: result.success ? "\(fallbackTitle) Succeeded" : "\(fallbackTitle) Failed",
                message: result.message
            )
        } else {
            feedbackAlert = FeedbackAlert(
                title: fallbackTitle,
                message: fallbackMessage
            )
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(AppState())
    }
}
