import Foundation

struct SyncSettings: Codable, Equatable {
    var baseURLString: String
    var apiToken: String
    var deviceID: String

    static let `default` = SyncSettings(
        baseURLString: "",
        apiToken: "",
        deviceID: UUID().uuidString
    )
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
