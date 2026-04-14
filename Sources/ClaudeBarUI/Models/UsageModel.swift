import SwiftUI

// MARK: - API Response Models

public struct UsageResponse: Codable {
    public let fiveHour: WindowUsage?
    public let sevenDay: WindowUsage
    public let sevenDaySonnet: WindowUsage?
    public let sevenDayOpus: WindowUsage?
    public let extraUsage: ExtraUsage?

    public init(fiveHour: WindowUsage?, sevenDay: WindowUsage, sevenDaySonnet: WindowUsage? = nil, sevenDayOpus: WindowUsage? = nil, extraUsage: ExtraUsage? = nil) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.sevenDaySonnet = sevenDaySonnet
        self.sevenDayOpus = sevenDayOpus
        self.extraUsage = extraUsage
    }
}

public struct WindowUsage: Codable {
    /// Utilization as a fraction (0.0 to 1.0). The API returns 0–100; we normalize on decode.
    public let utilization: Double
    public let resetsAt: Date?

    public init(utilization: Double, resetsAt: Date?) {
        self.utilization = utilization > 1.0 ? utilization / 100.0 : utilization
        self.resetsAt = resetsAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawUtilization = try container.decode(Double.self, forKey: .utilization)
        self.utilization = rawUtilization > 1.0 ? rawUtilization / 100.0 : rawUtilization
        self.resetsAt = try container.decodeIfPresent(Date.self, forKey: .resetsAt)
    }
}

public struct ExtraUsage: Codable {
    public let isEnabled: Bool
    public let monthlyLimit: Double?
    public let usedCredits: Double?
    public let utilization: Double?

    public init(isEnabled: Bool, monthlyLimit: Double?, usedCredits: Double?, utilization: Double?) {
        self.isEnabled = isEnabled
        self.monthlyLimit = monthlyLimit
        self.usedCredits = usedCredits
        self.utilization = utilization
    }
}

public struct Organization: Codable {
    public let uuid: String
    public let name: String
    public let capabilities: [String]?

    public init(uuid: String, name: String, capabilities: [String]? = nil) {
        self.uuid = uuid
        self.name = name
        self.capabilities = capabilities
    }
}

// MARK: - Display Helpers

public enum UsageColor {
    case green, yellow, orange, red

    public static func forUtilization(_ value: Double) -> UsageColor {
        switch value {
        case ..<0.51: return .green
        case ..<0.76: return .yellow
        case ..<0.91: return .orange
        default: return .red
        }
    }

    public var swiftUIColor: Color {
        switch self {
        case .green: return Color(red: 0.29, green: 0.87, blue: 0.50)   // #4ade80
        case .yellow: return Color(red: 0.98, green: 0.80, blue: 0.08)  // #facc15
        case .orange: return Color(red: 0.83, green: 0.65, blue: 0.46)  // #D4A574
        case .red: return Color(red: 0.94, green: 0.27, blue: 0.27)     // #ef4444
        }
    }
}
