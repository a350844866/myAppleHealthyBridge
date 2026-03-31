import Foundation

struct SyncSettings: Codable, Equatable {
    var baseURLString: String
    var apiToken: String
    var basicAuthUsername: String
    var basicAuthPassword: String
    var deviceID: String
    var baselineStartAt: Date?
    var autoSyncEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case baseURLString
        case apiToken
        case basicAuthUsername
        case basicAuthPassword
        case deviceID
        case baselineStartAt
        case autoSyncEnabled
    }

    static let `default` = SyncSettings(
        baseURLString: "",
        apiToken: "",
        basicAuthUsername: "",
        basicAuthPassword: "",
        deviceID: UUID().uuidString,
        baselineStartAt: nil,
        autoSyncEnabled: false
    )

    init(
        baseURLString: String,
        apiToken: String,
        basicAuthUsername: String,
        basicAuthPassword: String,
        deviceID: String,
        baselineStartAt: Date?,
        autoSyncEnabled: Bool
    ) {
        self.baseURLString = baseURLString
        self.apiToken = apiToken
        self.basicAuthUsername = basicAuthUsername
        self.basicAuthPassword = basicAuthPassword
        self.deviceID = deviceID
        self.baselineStartAt = baselineStartAt
        self.autoSyncEnabled = autoSyncEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.baseURLString = try container.decode(String.self, forKey: .baseURLString)
        self.apiToken = try container.decode(String.self, forKey: .apiToken)
        self.basicAuthUsername = try container.decodeIfPresent(String.self, forKey: .basicAuthUsername) ?? ""
        self.basicAuthPassword = try container.decodeIfPresent(String.self, forKey: .basicAuthPassword) ?? ""
        self.deviceID = try container.decode(String.self, forKey: .deviceID)
        self.baselineStartAt = try container.decodeIfPresent(Date.self, forKey: .baselineStartAt)
        self.autoSyncEnabled = try container.decodeIfPresent(Bool.self, forKey: .autoSyncEnabled) ?? false
    }
}

struct SyncRunResult: Codable, Equatable {
    var timestamp: Date
    var message: String
    var success: Bool
}

struct HealthAuthorizationState: Codable, Equatable {
    var hasRequestedAccess: Bool
    var lastRequestSucceeded: Bool

    static let `default` = HealthAuthorizationState(
        hasRequestedAccess: false,
        lastRequestSucceeded: false
    )
}

struct ObserverRuntimeState: Codable, Equatable {
    var isEnabled: Bool
    var observedTypeCount: Int
    var lastTriggerAt: Date?
    var lastTriggerType: String?
    var lastErrorMessage: String?

    static let `default` = ObserverRuntimeState(
        isEnabled: false,
        observedTypeCount: 0,
        lastTriggerAt: nil,
        lastTriggerType: nil,
        lastErrorMessage: nil
    )
}

struct IngestPayload: Codable {
    let deviceID: String
    let bundleID: String
    let sentAt: Date
    let items: [IngestItem]
    let anchors: [String: String]

    enum CodingKeys: String, CodingKey {
        case deviceID = "device_id"
        case bundleID = "bundle_id"
        case sentAt = "sent_at"
        case items
        case anchors
    }
}

struct IngestItem: Codable {
    let source: String
    let kind: String
    let type: String
    let uuid: String
    let startAt: Date
    let endAt: Date
    let value: Double?
    let unit: String?
    let metadata: [String: String]

    enum CodingKeys: String, CodingKey {
        case source
        case kind
        case type
        case uuid
        case startAt = "start_at"
        case endAt = "end_at"
        case value
        case unit
        case metadata
    }
}

struct IngestResponse: Codable {
    let ok: Bool
    let accepted: Int?
    let deduplicated: Int?
}

struct DeviceSyncAnchorsResponse: Codable {
    let device: RemoteDeviceSyncState
    let anchors: [String: String]
}

struct RemoteDeviceSyncState: Codable {
    let deviceID: String
    let bundleID: String
    let lastSeenAt: String?
    let lastSentAt: String?
    let lastSyncAt: String?
    let lastSyncStatus: String
    let lastErrorMessage: String?
    let lastItemsCount: Int
    let lastAcceptedCount: Int
    let lastDeduplicatedCount: Int
    let updatedAt: String?
    let anchorCount: Int
    let anchorsUpdatedAt: String?

    enum CodingKeys: String, CodingKey {
        case deviceID = "device_id"
        case bundleID = "bundle_id"
        case lastSeenAt = "last_seen_at"
        case lastSentAt = "last_sent_at"
        case lastSyncAt = "last_sync_at"
        case lastSyncStatus = "last_sync_status"
        case lastErrorMessage = "last_error_message"
        case lastItemsCount = "last_items_count"
        case lastAcceptedCount = "last_accepted_count"
        case lastDeduplicatedCount = "last_deduplicated_count"
        case updatedAt = "updated_at"
        case anchorCount = "anchor_count"
        case anchorsUpdatedAt = "anchors_updated_at"
    }
}

struct RecentSyncedRecordsResponse: Codable {
    let total: Int
    let data: [RecentSyncedRecord]
}

struct RecentSyncedRecord: Codable, Identifiable {
    let id: Int
    let type: String
    let sourceName: String?
    let sourceVersion: String?
    let unit: String?
    let valueText: String?
    let valueNum: Double?
    let startAt: String
    let endAt: String
    let localDate: String
    let metadata: String?
    let bridgeDeviceID: String?
    let bridgeBundleID: String?
    let bridgeSentAt: String?
    let bridgeKind: String?
    let bridgeSource: String?

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case sourceName = "source_name"
        case sourceVersion = "source_version"
        case unit
        case valueText = "value_text"
        case valueNum = "value_num"
        case startAt = "start_at"
        case endAt = "end_at"
        case localDate = "local_date"
        case metadata
        case bridgeDeviceID = "bridge_device_id"
        case bridgeBundleID = "bridge_bundle_id"
        case bridgeSentAt = "bridge_sent_at"
        case bridgeKind = "bridge_kind"
        case bridgeSource = "bridge_source"
    }
}
