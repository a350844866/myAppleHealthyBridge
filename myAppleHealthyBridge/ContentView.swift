import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    @State private var baseURL: String = ""
    @State private var apiToken: String = ""
    @State private var deviceID: String = ""
    @State private var autoSyncEnabled = false

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
                        }
                    }
                    .disabled(appState.syncCoordinator.isAuthorizing)
                }

                Section("Server") {
                    TextField("Base URL", text: $baseURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    SecureField("API Token", text: $apiToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    TextField("Device ID", text: $deviceID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Button("Save Settings") {
                        appState.syncStore.updateSettings(
                            baseURLString: baseURL,
                            apiToken: apiToken,
                            deviceID: deviceID,
                            autoSyncEnabled: autoSyncEnabled
                        )
                        Task {
                            await appState.syncCoordinator.updateAutoSync(enabled: autoSyncEnabled)
                        }
                    }
                }

                Section("Sync") {
                    Button(appState.syncCoordinator.isSyncing ? "Syncing..." : "Run Manual Sync") {
                        Task {
                            await appState.syncCoordinator.runManualSync()
                        }
                    }
                    .disabled(appState.syncCoordinator.isSyncing)

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
            .onAppear {
                let settings = appState.syncStore.settings
                baseURL = settings.baseURLString
                apiToken = settings.apiToken
                deviceID = settings.deviceID
                autoSyncEnabled = settings.autoSyncEnabled

                Task {
                    await appState.syncCoordinator.start()
                }
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(AppState())
    }
}
