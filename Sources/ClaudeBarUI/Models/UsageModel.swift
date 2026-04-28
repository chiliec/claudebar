import SwiftUI

// MARK: - API Response Models

public struct UsageResponse: Codable {
    public let fiveHour: WindowUsage?
    public let sevenDay: WindowUsage
    public let sevenDaySonnet: WindowUsage?
    public let sevenDayOpus: WindowUsage?
    public let sevenDayOmelette: WindowUsage?
    public let extraUsage: ExtraUsage?

    public init(fiveHour: WindowUsage?, sevenDay: WindowUsage, sevenDaySonnet: WindowUsage? = nil, sevenDayOpus: WindowUsage? = nil, sevenDayOmelette: WindowUsage? = nil, extraUsage: ExtraUsage? = nil) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.sevenDaySonnet = sevenDaySonnet
        self.sevenDayOpus = sevenDayOpus
        self.sevenDayOmelette = sevenDayOmelette
        self.extraUsage = extraUsage
    }

    /// Max plans get an `extra_usage` credit pool; Pro plans don't. Cleanest
    /// tier signal from `/usage` — independent of per-model window reshuffles.
    public var isMaxTier: Bool {
        guard let extra = extraUsage, extra.isEnabled else { return false }
        return (extra.monthlyLimit ?? 0) > 0
    }
}

public struct WindowUsage: Codable {
    /// Utilization as a fraction (0.0 to 1.0). The API returns 0–100; the decoder divides by 100.
    public let utilization: Double
    public let resetsAt: Date?

    public init(utilization: Double, resetsAt: Date?) {
        self.utilization = utilization
        self.resetsAt = resetsAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawUtilization = try container.decode(Double.self, forKey: .utilization)
        self.utilization = rawUtilization / 100.0
        self.resetsAt = try container.decodeIfPresent(Date.self, forKey: .resetsAt)
    }
}

public struct ExtraUsage: Codable {
    public let isEnabled: Bool
    public let monthlyLimit: Double?
    public let usedCredits: Double?
    public let utilization: Double?
    public let currency: String?
    public let overageBalance: Double?
    public let overageBalanceCurrency: String?

    public init(
        isEnabled: Bool,
        monthlyLimit: Double?,
        usedCredits: Double?,
        utilization: Double?,
        currency: String? = nil,
        overageBalance: Double? = nil,
        overageBalanceCurrency: String? = nil
    ) {
        self.isEnabled = isEnabled
        self.monthlyLimit = monthlyLimit
        self.usedCredits = usedCredits
        self.utilization = utilization
        self.currency = currency
        self.overageBalance = overageBalance
        self.overageBalanceCurrency = overageBalanceCurrency
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

public struct OrganizationDetails: Codable {
    public let uuid: String
    public let name: String
    public let rateLimitTier: String?
    public let capabilities: [String]?
    public let apiDisabledUntil: Date?
    public let billableUsagePausedUntil: Date?

    public init(
        uuid: String,
        name: String,
        rateLimitTier: String?,
        capabilities: [String]? = nil,
        apiDisabledUntil: Date? = nil,
        billableUsagePausedUntil: Date? = nil
    ) {
        self.uuid = uuid
        self.name = name
        self.rateLimitTier = rateLimitTier
        self.capabilities = capabilities
        self.apiDisabledUntil = apiDisabledUntil
        self.billableUsagePausedUntil = billableUsagePausedUntil
    }

    public var tier: SubscriptionTier { .from(rateLimitTier: rateLimitTier, capabilities: capabilities) }
}

public enum SubscriptionTier: Equatable {
    case pro
    case max5x
    case max20x
    case team
    case unknown(String?)

    /// Parse from Claude.ai's `rate_limit_tier` (e.g. `default_claude_max_5x`).
    /// Falls back to `capabilities` when the tier string is missing.
    public static func from(rateLimitTier: String?, capabilities: [String]?) -> SubscriptionTier {
        switch rateLimitTier {
        case "default_claude_pro": return .pro
        case "default_claude_max_5x": return .max5x
        case "default_claude_max_20x": return .max20x
        case "default_claude_team": return .team
        case let other?:
            // Unknown explicit tier — preserve raw suffix for debugging.
            if let raw = other.split(separator: "_").last.map(String.init) {
                return .unknown(raw)
            }
            return .unknown(other)
        case nil:
            // No rate_limit_tier — infer from capabilities as a last resort.
            if let caps = capabilities {
                if caps.contains("claude_max") { return .max5x }
                if caps.contains("claude_pro") { return .pro }
                if caps.contains("claude_team") { return .team }
            }
            return .unknown(nil)
        }
    }

    public var localizationKey: String {
        switch self {
        case .pro: return "tier.pro"
        case .max5x: return "tier.max5x"
        case .max20x: return "tier.max20x"
        case .team: return "tier.team"
        case .unknown: return "tier.unknown"
        }
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
