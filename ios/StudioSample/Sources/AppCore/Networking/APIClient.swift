import Foundation

struct APIClient {
    let baseURL: URL
    let deviceID: String

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
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw APIError.badStatusCode
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(FeedResponse.self, from: data)
    }

    func fetchLibrary() async throws -> [SampleItem] {
        let url = baseURL.appending(path: "/v1/users/\(deviceID)/library")
        let (data, response) = try await URLSession.shared.data(from: url)

        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw APIError.badStatusCode
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([SampleItem].self, from: data)
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
        let (_, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw APIError.badStatusCode
        }
    }
}

enum APIError: Error {
    case invalidURL
    case badStatusCode
}

struct FeedResponse: Codable {
    let items: [SampleItem]
    let nextCursor: Int?
}
