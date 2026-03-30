import Foundation

struct IngestClient {
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(session: URLSession = .shared) {
        self.session = session

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func post(payload: IngestPayload, settings: SyncSettings) async throws -> IngestResponse {
        guard let baseURL = URL(string: settings.baseURLString), !settings.baseURLString.isEmpty else {
            throw SyncError.invalidBaseURL
        }

        let url = baseURL.appending(path: "ingest")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if !settings.apiToken.isEmpty {
            request.setValue("Bearer \(settings.apiToken)", forHTTPHeaderField: "Authorization")
        }

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
}
