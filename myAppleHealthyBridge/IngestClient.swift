import Foundation

struct IngestClient {
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.waitsForConnectivity = true
            configuration.timeoutIntervalForRequest = 180
            configuration.timeoutIntervalForResource = 600
            self.session = URLSession(configuration: configuration)
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func fetchRemoteAnchors(
        deviceID: String,
        bundleID: String,
        settings: SyncSettings
    ) async throws -> DeviceSyncAnchorsResponse? {
        guard let baseURL = URL(string: settings.baseURLString), !settings.baseURLString.isEmpty else {
            throw SyncError.invalidBaseURL
        }

        var components = URLComponents(url: baseURL.appending(path: "api/device-sync-state/anchors"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "device_id", value: deviceID),
            URLQueryItem(name: "bundle_id", value: bundleID)
        ]

        guard let url = components?.url else {
            throw SyncError.invalidBaseURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 60
        applyAuthorization(to: &request, settings: settings)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SyncError.invalidServerResponse
        }

        if httpResponse.statusCode == 404 {
            return nil
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw SyncError.serverRejected(message)
        }

        return try decoder.decode(DeviceSyncAnchorsResponse.self, from: data)
    }

    func fetchRecentSyncedRecords(
        deviceID: String,
        bundleID: String? = nil,
        limit: Int = 50,
        settings: SyncSettings
    ) async throws -> RecentSyncedRecordsResponse {
        guard let baseURL = URL(string: settings.baseURLString), !settings.baseURLString.isEmpty else {
            throw SyncError.invalidBaseURL
        }

        var components = URLComponents(url: baseURL.appending(path: "api/records/recent"), resolvingAgainstBaseURL: false)
        var queryItems = [
            URLQueryItem(name: "device_id", value: deviceID),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        if let bundleID, !bundleID.isEmpty {
            queryItems.append(URLQueryItem(name: "bundle_id", value: bundleID))
        }
        components?.queryItems = queryItems

        guard let url = components?.url else {
            throw SyncError.invalidBaseURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 60
        applyAuthorization(to: &request, settings: settings)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SyncError.invalidServerResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw SyncError.serverRejected(message)
        }

        return try decoder.decode(RecentSyncedRecordsResponse.self, from: data)
    }

    func post(payload: IngestPayload, settings: SyncSettings) async throws -> IngestResponse {
        guard let baseURL = URL(string: settings.baseURLString), !settings.baseURLString.isEmpty else {
            throw SyncError.invalidBaseURL
        }

        let url = baseURL.appending(path: "ingest")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuthorization(to: &request, settings: settings)

        request.httpBody = try encoder.encode(payload)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SyncError.invalidServerResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw SyncError.serverRejected(message)
        }

        if data.isEmpty {
            return IngestResponse(ok: true, accepted: payload.items.count, deduplicated: nil)
        }

        return try decoder.decode(IngestResponse.self, from: data)
    }

    private func applyAuthorization(to request: inout URLRequest, settings: SyncSettings) {
        if !settings.basicAuthUsername.isEmpty {
            let credentials = "\(settings.basicAuthUsername):\(settings.basicAuthPassword)"
            let encoded = Data(credentials.utf8).base64EncodedString()
            request.setValue("Basic \(encoded)", forHTTPHeaderField: "Authorization")
        } else if !settings.apiToken.isEmpty {
            request.setValue("Bearer \(settings.apiToken)", forHTTPHeaderField: "Authorization")
        }
    }
}
