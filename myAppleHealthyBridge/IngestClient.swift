import Foundation

struct IngestClient {
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let backgroundUploader: BackgroundIngestUploader

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.waitsForConnectivity = true
            configuration.timeoutIntervalForRequest = 60
            configuration.timeoutIntervalForResource = 120
            self.session = URLSession(configuration: configuration)
        }

        self.backgroundUploader = BackgroundIngestUploader.shared

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
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuthorization(to: &request, settings: settings)

        let body = try encoder.encode(payload)
        let (data, response) = try await backgroundUploader.upload(request: request, body: body)

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

final class BackgroundIngestUploader: NSObject {
    static let shared = BackgroundIngestUploader()

    private let state = UploadState()

    lazy var session: URLSession = {
        let identifier = "\(Bundle.main.bundleIdentifier ?? "myAppleHealthyBridge").ingest.background"
        let configuration = URLSessionConfiguration.background(withIdentifier: identifier)
        configuration.isDiscretionary = false
        configuration.sessionSendsLaunchEvents = true
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 10 * 60
        configuration.httpMaximumConnectionsPerHost = 1
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    private override init() {
        super.init()
    }

    func upload(request: URLRequest, body: Data) async throws -> (Data, URLResponse) {
        let bodyURL = try writeBodyToTemporaryFile(body)
        let task = session.uploadTask(with: request, fromFile: bodyURL)

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                Task {
                    await state.register(
                        taskIdentifier: task.taskIdentifier,
                        bodyURL: bodyURL,
                        continuation: continuation
                    )
                    task.resume()
                }
            }
        } onCancel: {
            task.cancel()
            Task {
                await self.state.cancel(taskIdentifier: task.taskIdentifier)
            }
        }
    }

    func setBackgroundEventsCompletionHandler(_ completionHandler: @escaping () -> Void) {
        Task {
            await state.setBackgroundEventsCompletionHandler(completionHandler)
        }
    }

    private func writeBodyToTemporaryFile(_ body: Data) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "IngestUploads",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        let fileURL = directory.appendingPathComponent("\(UUID().uuidString).json")
        try body.write(to: fileURL, options: .atomic)
        return fileURL
    }
}

extension BackgroundIngestUploader: URLSessionDataDelegate, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        Task {
            await state.append(data: data, taskIdentifier: dataTask.taskIdentifier)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let response = task.response
        Task {
            await state.finish(taskIdentifier: task.taskIdentifier, response: response, error: error)
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task {
            await state.finishBackgroundEvents()
        }
    }
}

private actor UploadState {
    private struct UploadRecord {
        let bodyURL: URL
        let continuation: CheckedContinuation<(Data, URLResponse), Error>
        var responseData = Data()
    }

    private var records: [Int: UploadRecord] = [:]
    private var backgroundEventsCompletionHandler: (() -> Void)?

    func register(
        taskIdentifier: Int,
        bodyURL: URL,
        continuation: CheckedContinuation<(Data, URLResponse), Error>
    ) {
        records[taskIdentifier] = UploadRecord(bodyURL: bodyURL, continuation: continuation)
    }

    func append(data: Data, taskIdentifier: Int) {
        guard var record = records[taskIdentifier] else {
            return
        }
        record.responseData.append(data)
        records[taskIdentifier] = record
    }

    func finish(taskIdentifier: Int, response: URLResponse?, error: Error?) {
        guard let record = records.removeValue(forKey: taskIdentifier) else {
            return
        }

        try? FileManager.default.removeItem(at: record.bodyURL)

        if let error {
            record.continuation.resume(throwing: error)
            return
        }

        guard let response else {
            record.continuation.resume(throwing: SyncError.invalidServerResponse)
            return
        }

        record.continuation.resume(returning: (record.responseData, response))
    }

    func cancel(taskIdentifier: Int) {
        guard let record = records.removeValue(forKey: taskIdentifier) else {
            return
        }

        try? FileManager.default.removeItem(at: record.bodyURL)
        record.continuation.resume(throwing: CancellationError())
    }

    func setBackgroundEventsCompletionHandler(_ completionHandler: @escaping () -> Void) {
        backgroundEventsCompletionHandler = completionHandler
    }

    func finishBackgroundEvents() {
        let completionHandler = backgroundEventsCompletionHandler
        backgroundEventsCompletionHandler = nil
        completionHandler?()
    }
}
