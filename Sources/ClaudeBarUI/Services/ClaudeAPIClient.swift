import Foundation

public struct ClaudeAPIClient {
    private static let baseURL = "https://claude.ai"

    public let sessionKey: String
    public let orgId: String

    public init(sessionKey: String, orgId: String) {
        self.sessionKey = sessionKey
        self.orgId = orgId
    }

    // MARK: - Request Builders

    public func buildUsageRequest() throws -> URLRequest {
        guard let url = URL(string: "\(Self.baseURL)/api/organizations/\(orgId)/usage") else {
            throw APIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
        return request
    }

    public static func buildOrganizationsRequest(sessionKey: String) throws -> URLRequest {
        guard let url = URL(string: "\(baseURL)/api/organizations") else {
            throw APIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
        return request
    }

    public func buildOrganizationDetailsRequest() throws -> URLRequest {
        guard let url = URL(string: "\(Self.baseURL)/api/organizations/\(orgId)") else {
            throw APIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
        return request
    }

    // MARK: - Response Parsers

    public static func parseUsageResponse(data: Data) throws -> UsageResponse {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            let formatters = [ISO8601DateFormatter.withFractionalSeconds, ISO8601DateFormatter.standard]
            for formatter in formatters {
                if let date = formatter.date(from: dateString) { return date }
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot parse date: \(dateString)")
        }
        return try decoder.decode(UsageResponse.self, from: data)
    }

    public static func parseOrganizationsResponse(data: Data) throws -> [Organization] {
        return try JSONDecoder().decode([Organization].self, from: data)
    }

    public static func parseOrganizationDetailsResponse(data: Data) throws -> OrganizationDetails {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            let formatters = [ISO8601DateFormatter.withFractionalSeconds, ISO8601DateFormatter.standard]
            for formatter in formatters {
                if let date = formatter.date(from: dateString) { return date }
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot parse date: \(dateString)")
        }
        return try decoder.decode(OrganizationDetails.self, from: data)
    }

    // MARK: - Network Calls

    public func fetchUsage() async throws -> UsageResponse {
        let (data, response) = try await URLSession.shared.data(for: try buildUsageRequest())
        try Self.validateHTTPResponse(response)
        return try Self.parseUsageResponse(data: data)
    }

    public func fetchOrganizationDetails() async throws -> OrganizationDetails {
        let (data, response) = try await URLSession.shared.data(for: try buildOrganizationDetailsRequest())
        try Self.validateHTTPResponse(response)
        return try Self.parseOrganizationDetailsResponse(data: data)
    }

    public static func fetchOrganizations(sessionKey: String) async throws -> [Organization] {
        let request = try buildOrganizationsRequest(sessionKey: sessionKey)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTPResponse(response)
        return try parseOrganizationsResponse(data: data)
    }

    private static func validateHTTPResponse(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        switch http.statusCode {
        case 200: return
        case 401, 403: throw APIError.sessionExpired
        case 429: throw APIError.rateLimited
        default: throw APIError.httpError(http.statusCode)
        }
    }
}

public enum APIError: Error, Equatable {
    case invalidURL
    case invalidResponse
    case sessionExpired
    case rateLimited
    case httpError(Int)

    public var displayMessage: String {
        switch self {
        case .invalidURL: return String(localized: "apiError.invalidURL", bundle: .module)
        case .invalidResponse: return String(localized: "apiError.invalidResponse", bundle: .module)
        case .sessionExpired: return String(localized: "apiError.sessionExpired", bundle: .module)
        case .rateLimited: return String(localized: "apiError.rateLimited", bundle: .module)
        case .httpError(let code): return String(localized: "apiError.httpError \(code)", bundle: .module)
        }
    }
}

extension ISO8601DateFormatter {
    static let withFractionalSeconds: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static let standard: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}
