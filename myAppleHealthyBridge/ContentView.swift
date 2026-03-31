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
        case backfillHistory
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
                Section("健康数据") {
                    LabeledContent("可用性", value: appState.syncCoordinator.authorizationStateText)
                    LabeledContent("观察器", value: appState.syncCoordinator.observerStateText)

                    Toggle("开启自动同步", isOn: $autoSyncEnabled)

                    Text("调试阶段建议先保持手动同步。只有打开自动同步后，应用才会注册健康数据观察器，并在检测到变更时自动执行增量同步。")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button(appState.syncCoordinator.isAuthorizing ? "请求中..." : "请求健康数据权限") {
                        Task {
                            await appState.syncCoordinator.requestAuthorization()
                            presentResultAlert(
                                fallbackTitle: "健康数据权限",
                                fallbackMessage: "健康数据权限请求已完成。"
                            )
                        }
                    }
                    .disabled(appState.syncCoordinator.isAuthorizing || activeAction != nil)
                }

                Section("服务端") {
                    TextField("服务端地址", text: $baseURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    SecureField("接口令牌", text: $apiToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    TextField("基础认证用户名", text: $basicAuthUsername)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    SecureField("基础认证密码", text: $basicAuthPassword)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    TextField("设备编号", text: $deviceID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Text("设备编号代表一条长期稳定的增量同步游标，不是临时会话编号。正式开始同步后不要随意改。")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("如果公网入口启用了基础认证，就填写用户名和密码。当前客户端会优先发送基础认证请求头；只有未填写基础认证时，才会发送接口令牌对应的令牌认证请求头。")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button(activeAction == .saveSettings ? "保存中..." : "保存设置") {
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
                                title: "设置已保存",
                                message: deviceIDChanged
                                ? "服务端设置已保存。由于设备编号已变更，本地同步游标和「从现在开始」基线已清空。请先恢复服务端游标，或者重新初始化「从现在开始」，再继续同步。"
                                : "服务端设置已保存。"
                            )
                        }
                    }
                    .disabled(appState.syncCoordinator.isAuthorizing || appState.syncCoordinator.isSyncing || activeAction != nil)
                }

                Section("同步") {
                    Button(activeAction == .restoreServerAnchors ? "恢复中..." : "恢复服务端游标") {
                        activeAction = .restoreServerAnchors
                        Task {
                            await appState.syncCoordinator.restoreServerAnchors()
                            activeAction = nil
                            presentResultAlert(
                                fallbackTitle: "恢复服务端游标",
                                fallbackMessage: "服务端游标恢复已完成。"
                            )
                        }
                    }
                    .disabled(appState.syncCoordinator.isAuthorizing || appState.syncCoordinator.isSyncing || activeAction != nil)

                    Button(activeAction == .startFromNow ? "初始化中..." : "从现在开始") {
                        activeAction = .startFromNow
                        Task {
                            await appState.syncCoordinator.startFromNow()
                            activeAction = nil
                            presentResultAlert(
                                fallbackTitle: "从现在开始",
                                fallbackMessage: "增量同步基线已初始化。"
                            )
                        }
                    }
                    .disabled(appState.syncCoordinator.isAuthorizing || appState.syncCoordinator.isSyncing || activeAction != nil)

                    Button(activeAction == .manualSync || appState.syncCoordinator.isSyncing ? "同步中..." : "手动同步") {
                        activeAction = .manualSync
                        Task {
                            await appState.syncCoordinator.runManualSync()
                            activeAction = nil
                            presentResultAlert(
                                fallbackTitle: "手动同步",
                                fallbackMessage: "手动同步已完成。"
                            )
                        }
                    }
                    .disabled(appState.syncCoordinator.isAuthorizing || appState.syncCoordinator.isSyncing || activeAction != nil)

                    Button(activeAction == .backfillLastWeek || appState.syncCoordinator.isSyncing ? "上传中..." : "上传最近 7 天") {
                        activeAction = .backfillLastWeek
                        Task {
                            await appState.syncCoordinator.uploadLast7Days()
                            activeAction = nil
                            presentResultAlert(
                                fallbackTitle: "上传最近 7 天",
                                fallbackMessage: "最近 7 天数据上传已完成。"
                            )
                        }
                    }
                    .disabled(appState.syncCoordinator.isAuthorizing || appState.syncCoordinator.isSyncing || activeAction != nil)

                    Button(activeAction == .backfillHistory || appState.syncCoordinator.isSyncing
                           ? (appState.syncCoordinator.backfillBatchCount > 0
                              ? "回填中（第 \(appState.syncCoordinator.backfillBatchCount) 批）..."
                              : "回填中...")
                           : "回填全部历史") {
                        activeAction = .backfillHistory
                        Task {
                            await appState.syncCoordinator.runBackfillHistory()
                            activeAction = nil
                            presentResultAlert(
                                fallbackTitle: "全量历史回填",
                                fallbackMessage: "历史数据回填已完成。"
                            )
                        }
                    }
                    .disabled(appState.syncCoordinator.isAuthorizing || appState.syncCoordinator.isSyncing || activeAction != nil)

                    Text("没有本地或服务端游标时，手动同步不会再扫描全量历史。先点「恢复服务端游标」；如果服务端也没有游标，再点「从现在开始」。")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("「上传最近 7 天」是一次性历史回填，不会改写当前增量游标；适合在「从现在开始」之后补最近一周数据。\n\n「回填全部历史」会分批上传 HealthKit 中所有历史记录（每批 5000 条），服务端自动去重已导入的数据。游标会随批次推进，可随时中断后续接着回填。")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let result = appState.syncStore.lastSyncResult {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(result.success ? "成功" : "失败")
                                .font(.headline)
                            Text(result.timestamp.formatted(date: .abbreviated, time: .standard))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(result.message)
                                .font(.body)
                        }
                    }
                }

                Section("最近同步") {
                    NavigationLink("查看最近同步数据") {
                        RecentSyncedDataView()
                            .environmentObject(appState)
                    }

                    Text("打开一个基于服务端的概览页，查看当前设备最近同步上来的样本。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("上传内容预览") {
                    if appState.syncCoordinator.latestPayloadPreview.isEmpty {
                    Text("还没有生成上传内容。")
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
            .navigationTitle("健康同步桥")
            .alert(item: $feedbackAlert) { feedback in
                Alert(
                    title: Text(feedback.title),
                    message: Text(feedback.message),
                    dismissButton: .default(Text("确定"))
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
                title: result.success ? "\(fallbackTitle)成功" : "\(fallbackTitle)失败",
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
