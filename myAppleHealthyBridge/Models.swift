import Foundation

struct SyncSettings: Codable, Equatable {
    var baseURLString: String
    var apiToken: String
    var deviceID: String
    var autoSyncEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case baseURLString
        case apiToken
        case deviceID
        case autoSyncEnabled
    }

    static let `default` = SyncSettings(
        baseURLString: "",
        apiToken: "",
        deviceID: UUID().uuidString,
        autoSyncEnabled: false
    )

    init(baseURLString: String, apiToken: String, deviceID: String, autoSyncEnabled: Bool) {
        self.baseURLString = baseURLString
        self.apiToken = apiToken
        self.deviceID = deviceID
        self.autoSyncEnabled = autoSyncEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.baseURLString = try container.decode(String.self, forKey: .baseURLString)
        self.apiToken = try container.decode(String.self, forKey: .apiToken)
        self.deviceID = try container.decode(String.self, forKey: .deviceID)
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
