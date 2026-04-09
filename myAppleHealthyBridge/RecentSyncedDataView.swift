import SwiftUI

struct RecentSyncedDataView: View {
    @EnvironmentObject private var appState: AppState

    @State private var recordsResponse: RecentSyncedRecordsResponse?
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let pageLimit = 50

    var body: some View {
        List {
            if let configurationIssue {
                Section {
                    Text(configurationIssue)
                        .foregroundStyle(.secondary)
                }
            } else if isLoading && recordsResponse == nil {
                Section {
                    HStack {
                        ProgressView()
                        Text("正在加载最近同步数据...")
                            .foregroundStyle(.secondary)
                    }
                }
            } else if let errorMessage {
                Section("错误") {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }

            if let response = recordsResponse {
                Section("概览") {
                    LabeledContent("服务端总数", value: "\(response.total)")
                    LabeledContent("当前已拉取", value: "\(response.data.count)")
                    if let latest = response.data.first?.bridgeSentAt {
                        LabeledContent("最近批次", value: latest)
                    }
                    Text("本页展示当前设备在服务端最近同步的 \(pageLimit) 条记录。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !recentTypeCounts.isEmpty {
                    Section("近期类型分布") {
                        ForEach(recentTypeCounts, id: \.type) { entry in
                            HStack {
                                Text(shortTypeName(entry.type))
                                Spacer()
                                Text("\(entry.count)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("最近记录") {
                    ForEach(response.data) { record in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(shortTypeName(record.type))
                                    .font(.headline)
                                Spacer()
                                Text(record.valueSummary)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            Text(record.startAt)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if let sourceName = record.sourceName, !sourceName.isEmpty {
                                Text(sourceName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .navigationTitle("最近同步数据")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(isLoading ? "刷新中..." : "刷新") {
                    Task {
                        await loadRecentRecords()
                    }
                }
                .disabled(isLoading || configurationIssue != nil)
            }
        }
        .task {
            await loadRecentRecords()
        }
        .refreshable {
            await loadRecentRecords()
        }
    }
}

private extension RecentSyncedDataView {
    var configurationIssue: String? {
        let settings = appState.syncStore.settings
        if settings.baseURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "请先填写服务端地址。"
        }
        if settings.deviceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "请先填写设备编号。"
        }
        return nil
    }

    var recentTypeCounts: [(type: String, count: Int)] {
        guard let response = recordsResponse else {
            return []
        }
        return response.data.reduce(into: [String: Int]()) { counts, record in
            counts[record.type, default: 0] += 1
        }
        .map { (type: $0.key, count: $0.value) }
        .sorted {
            if $0.count == $1.count {
                return $0.type < $1.type
            }
            return $0.count > $1.count
        }
    }

    func loadRecentRecords() async {
        guard configurationIssue == nil else {
            recordsResponse = nil
            errorMessage = nil
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let settings = appState.syncStore.settings
            let bundleID = Bundle.main.bundleIdentifier ?? ""
            let response = try await appState.ingestClient.fetchRecentSyncedRecords(
                deviceID: settings.deviceID,
                bundleID: bundleID,
                limit: pageLimit,
                settings: settings
            )
            recordsResponse = response
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func shortTypeName(_ identifier: String) -> String {
        identifier
            .replacingOccurrences(of: "HKQuantityTypeIdentifier", with: "")
            .replacingOccurrences(of: "HKCategoryTypeIdentifier", with: "")
            .replacingOccurrences(of: "HKWorkoutActivityType", with: "")
    }
}

private extension RecentSyncedRecord {
    var valueSummary: String {
        if let valueText, let unit, !unit.isEmpty {
            return "\(valueText) \(unit)"
        }
        if let valueText {
            return valueText
        }
        if let unit, !unit.isEmpty {
            return unit
        }
        return "无数值"
    }
}
