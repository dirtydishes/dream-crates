import Foundation

struct APIClient {
    let baseURL: URL

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
}

enum APIError: Error {
    case invalidURL
    case badStatusCode
}

struct FeedResponse: Codable {
    let items: [SampleItem]
    let nextCursor: Int?
}
