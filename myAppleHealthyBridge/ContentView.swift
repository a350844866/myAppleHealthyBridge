import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    @State private var baseURL: String = ""
    @State private var apiToken: String = ""
    @State private var deviceID: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("HealthKit") {
                    LabeledContent("Availability", value: appState.syncCoordinator.authorizationStateText)
                    LabeledContent("Observer", value: appState.syncCoordinator.observerStateText)

                    Text("This build uses manual sync only. If you already granted Health access, tapping again usually will not show a system popup.")
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
                            deviceID: deviceID
                        )
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
