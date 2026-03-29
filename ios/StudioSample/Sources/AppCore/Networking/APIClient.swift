import Foundation

struct APIClient {
    let baseURL: URL
    let deviceID: String

    static let defaultUserAgent = "DreamCrates/1.0 (iOS)"

    func fetchFeed(limit: Int = 30, cursor: Int = 0) async throws -> FeedResponse {
        var components = URLComponents(url: baseURL.appending(path: "/v1/samples"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            .init(name: "limit", value: String(limit)),
            .init(name: "cursor", value: String(cursor)),
        ]

        guard let url = components?.url else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        applyDefaultHeaders(to: &request)
        print("DreamCrates API fetchFeed -> \(url.absoluteString)")
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw APIError.badStatusCode(url: url.absoluteString, statusCode: nil, bodyPreview: nil)
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            let bodyPreview = String(data: data.prefix(400), encoding: .utf8)
            print("DreamCrates API fetchFeed bad status \(http.statusCode) for \(url.absoluteString)")
            if let bodyPreview, !bodyPreview.isEmpty {
                print("DreamCrates API fetchFeed body: \(bodyPreview)")
            }
            throw APIError.badStatusCode(
                url: url.absoluteString,
                statusCode: http.statusCode,
                bodyPreview: bodyPreview
            )
        }

        do {
            let response = try Self.makeDecoder().decode(FeedResponse.self, from: data)
            print("DreamCrates API fetchFeed decoded \(response.items.count) items from \(url.absoluteString)")
            return response
        } catch {
            let bodyPreview = String(data: data.prefix(400), encoding: .utf8) ?? "<non-utf8>"
            print("DreamCrates API fetchFeed decode failed for \(url.absoluteString): \(error)")
            print("DreamCrates API fetchFeed raw body: \(bodyPreview)")
            throw APIError.decodingFailed(url: url.absoluteString, underlying: String(describing: error))
        }
    }

    func runPollerOnce() async throws -> PollOnceResponse {
        let url = baseURL.appending(path: "/v1/poller/run-once")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        applyDefaultHeaders(to: &request)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw APIError.badStatusCode(url: url.absoluteString, statusCode: nil, bodyPreview: nil)
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw APIError.badStatusCode(
                url: url.absoluteString,
                statusCode: http.statusCode,
                bodyPreview: String(data: data.prefix(400), encoding: .utf8)
            )
        }

        return try Self.makeDecoder().decode(PollOnceResponse.self, from: data)
    }

    func fetchLibrary() async throws -> [SampleItem] {
        let url = baseURL.appending(path: "/v1/users/\(deviceID)/library")
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        applyDefaultHeaders(to: &request)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw APIError.badStatusCode(url: url.absoluteString, statusCode: nil, bodyPreview: nil)
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw APIError.badStatusCode(
                url: url.absoluteString,
                statusCode: http.statusCode,
                bodyPreview: String(data: data.prefix(400), encoding: .utf8)
            )
        }

        return try Self.makeDecoder().decode([SampleItem].self, from: data)
    }

    func updateLibrary(sampleID: String, saved: Bool) async throws {
        var components = URLComponents(
            url: baseURL.appending(path: "/v1/users/\(deviceID)/library/\(sampleID)"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [.init(name: "saved", value: saved ? "true" : "false")]

        guard let url = components?.url else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.timeoutInterval = 12
        applyDefaultHeaders(to: &request)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw APIError.badStatusCode(url: url.absoluteString, statusCode: nil, bodyPreview: nil)
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw APIError.badStatusCode(
                url: url.absoluteString,
                statusCode: http.statusCode,
                bodyPreview: String(data: data.prefix(400), encoding: .utf8)
            )
        }
    }

    func resolvePlayback(sampleID: String) async throws -> PlaybackResolvePayload {
        let url = baseURL.appending(path: "/v1/playback/resolve")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 12
        applyDefaultHeaders(to: &request)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(SampleActionPayload(sampleID: sampleID))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.badStatusCode(url: url.absoluteString, statusCode: nil, bodyPreview: nil)
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw APIError.badStatusCode(
                url: url.absoluteString,
                statusCode: http.statusCode,
                bodyPreview: String(data: data.prefix(400), encoding: .utf8)
            )
        }

        return try Self.makeDecoder().decode(PlaybackResolvePayload.self, from: data)
    }

    func prepareDownload(sampleID: String) async throws -> DownloadPreparePayload {
        let url = baseURL.appending(path: "/v1/download/prepare")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 12
        applyDefaultHeaders(to: &request)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(SampleActionPayload(sampleID: sampleID))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.badStatusCode(url: url.absoluteString, statusCode: nil, bodyPreview: nil)
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw APIError.badStatusCode(
                url: url.absoluteString,
                statusCode: http.statusCode,
                bodyPreview: String(data: data.prefix(400), encoding: .utf8)
            )
        }

        return try Self.makeDecoder().decode(DownloadPreparePayload.self, from: data)
    }

    func registerDevice(
        apnsToken: String,
        notificationsEnabled: Bool,
        quietStartHour: Int?,
        quietEndHour: Int?
    ) async throws {
        let url = baseURL.appending(path: "/v1/devices/register")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 12
        applyDefaultHeaders(to: &request)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            DeviceRegistrationRequestPayload(
                deviceID: deviceID,
                apnsToken: apnsToken,
                notificationsEnabled: notificationsEnabled,
                quietStartHour: quietStartHour,
                quietEndHour: quietEndHour
            )
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.badStatusCode(url: url.absoluteString, statusCode: nil, bodyPreview: nil)
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw APIError.badStatusCode(
                url: url.absoluteString,
                statusCode: http.statusCode,
                bodyPreview: String(data: data.prefix(400), encoding: .utf8)
            )
        }
    }

    func fetchPreferences() async throws -> DevicePreferencesPayload {
        let url = baseURL.appending(path: "/v1/users/\(deviceID)/preferences")
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        applyDefaultHeaders(to: &request)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw APIError.badStatusCode(url: url.absoluteString, statusCode: nil, bodyPreview: nil)
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw APIError.badStatusCode(
                url: url.absoluteString,
                statusCode: http.statusCode,
                bodyPreview: String(data: data.prefix(400), encoding: .utf8)
            )
        }

        return try Self.makeDecoder().decode(DevicePreferencesPayload.self, from: data)
    }

    func updatePreferences(
        notificationsEnabled: Bool,
        quietStartHour: Int?,
        quietEndHour: Int?
    ) async throws {
        let url = baseURL.appending(path: "/v1/users/\(deviceID)/preferences")
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.timeoutInterval = 12
        applyDefaultHeaders(to: &request)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            PreferencesPayload(
                notificationsEnabled: notificationsEnabled,
                quietStartHour: quietStartHour,
                quietEndHour: quietEndHour
            )
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.badStatusCode(url: url.absoluteString, statusCode: nil, bodyPreview: nil)
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw APIError.badStatusCode(
                url: url.absoluteString,
                statusCode: http.statusCode,
                bodyPreview: String(data: data.prefix(400), encoding: .utf8)
            )
        }
    }

    private func applyDefaultHeaders(to request: inout URLRequest) {
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Self.defaultUserAgent, forHTTPHeaderField: "User-Agent")
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

enum APIError: Error {
    case invalidURL
    case badStatusCode(url: String, statusCode: Int?, bodyPreview: String?)
    case decodingFailed(url: String, underlying: String)
}

struct FeedResponse: Codable {
    let items: [SampleItem]
    let nextCursor: Int?
}

struct PollOnceResponse: Codable {
    let inserted: Int
    let notificationsSent: Int
}

private struct SampleActionPayload: Encodable {
    let sampleID: String

    enum CodingKeys: String, CodingKey {
        case sampleID = "sample_id"
    }
}

struct PlaybackResolvePayload: Decodable {
    let sampleID: String
    let playbackURL: URL
    let expiresAt: Date
    let source: String

    enum CodingKeys: String, CodingKey {
        case sampleID = "sample_id"
        case playbackURL = "playback_url"
        case expiresAt = "expires_at"
        case source
    }
}

struct DownloadPreparePayload: Decodable {
    let sampleID: String
    let downloadURL: URL
    let expiresAt: Date
    let source: String

    enum CodingKeys: String, CodingKey {
        case sampleID = "sample_id"
        case downloadURL = "download_url"
        case expiresAt = "expires_at"
        case source
    }
}

private struct DeviceRegistrationRequestPayload: Encodable {
    let deviceID: String
    let apnsToken: String
    let notificationsEnabled: Bool
    let quietStartHour: Int?
    let quietEndHour: Int?

    enum CodingKeys: String, CodingKey {
        case deviceID = "device_id"
        case apnsToken = "apns_token"
        case notificationsEnabled = "notifications_enabled"
        case quietStartHour = "quiet_start_hour"
        case quietEndHour = "quiet_end_hour"
    }
}

struct DevicePreferencesPayload: Codable {
    let deviceID: String
    let notificationsEnabled: Bool
    let quietStartHour: Int?
    let quietEndHour: Int?

    enum CodingKeys: String, CodingKey {
        case deviceID = "device_id"
        case notificationsEnabled = "notifications_enabled"
        case quietStartHour = "quiet_start_hour"
        case quietEndHour = "quiet_end_hour"
    }
}

private struct PreferencesPayload: Encodable {
    let notificationsEnabled: Bool
    let quietStartHour: Int?
    let quietEndHour: Int?

    enum CodingKeys: String, CodingKey {
        case notificationsEnabled = "notifications_enabled"
        case quietStartHour = "quiet_start_hour"
        case quietEndHour = "quiet_end_hour"
    }
}
