import Testing
import Foundation
@testable import ClaudeBarUI

@Suite
struct UsageModelTests {
    @Test func decodeFullUsageResponse() throws {
        let json = """
        {
          "five_hour": { "utilization": 0.42, "resets_at": "2026-04-12T15:30:00.000Z" },
          "seven_day": { "utilization": 0.15, "resets_at": "2026-04-14T12:59:00.000Z" },
          "seven_day_sonnet": { "utilization": 0.08, "resets_at": "2026-04-14T12:59:00.000Z" },
          "seven_day_opus": { "utilization": 0.03, "resets_at": null },
          "extra_usage": { "is_enabled": true, "monthly_limit": 100.0, "used_credits": 12.50, "utilization": 0.125 }
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601

        let usage = try decoder.decode(UsageResponse.self, from: json)

        #expect(usage.fiveHour?.utilization == 0.42)
        #expect(usage.fiveHour?.resetsAt != nil)
        #expect(usage.sevenDay.utilization == 0.15)
        #expect(usage.sevenDaySonnet?.utilization == 0.08)
        #expect(usage.sevenDayOpus?.utilization == 0.03)
        #expect(usage.sevenDayOpus?.resetsAt == nil)
        #expect(usage.extraUsage?.isEnabled == true)
        #expect(usage.extraUsage?.monthlyLimit == 100.0)
        #expect(usage.extraUsage?.usedCredits == 12.50)
    }

    @Test func decodeMinimalResponse() throws {
        let json = """
        {
          "seven_day": { "utilization": 0.05, "resets_at": "2026-04-14T12:59:00.000Z" }
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601

        let usage = try decoder.decode(UsageResponse.self, from: json)

        #expect(usage.fiveHour == nil)
        #expect(usage.sevenDay.utilization == 0.05)
        #expect(usage.sevenDaySonnet == nil)
        #expect(usage.sevenDayOpus == nil)
        #expect(usage.extraUsage == nil)
    }

    @Test func decodeOrganization() throws {
        let json = """
        [{ "uuid": "abc-123", "name": "My Org", "capabilities": ["chat"] }]
        """.data(using: .utf8)!

        let orgs = try JSONDecoder().decode([Organization].self, from: json)

        #expect(orgs.count == 1)
        #expect(orgs[0].uuid == "abc-123")
        #expect(orgs[0].name == "My Org")
    }

    @Test func decodePercentageScaleResponse() throws {
        let json = """
        {
          "five_hour": { "utilization": 5.0, "resets_at": "2026-04-12T15:30:00.000Z" },
          "seven_day": { "utilization": 15.0, "resets_at": "2026-04-14T12:59:00.000Z" }
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601

        let usage = try decoder.decode(UsageResponse.self, from: json)

        #expect(abs(usage.fiveHour!.utilization - 0.05) < 0.001)
        #expect(abs(usage.sevenDay.utilization - 0.15) < 0.001)
    }

    @Test func normalizationViaInit() {
        // Values > 1.0 are treated as percentage scale
        let window = WindowUsage(utilization: 73.0, resetsAt: nil)
        #expect(abs(window.utilization - 0.73) < 0.001)

        // Values <= 1.0 are kept as-is
        let fraction = WindowUsage(utilization: 0.42, resetsAt: nil)
        #expect(fraction.utilization == 0.42)
    }

    @Test func colorForUtilization() {
        #expect(UsageColor.forUtilization(0.0) == .green)
        #expect(UsageColor.forUtilization(0.3) == .green)
        #expect(UsageColor.forUtilization(0.5) == .green)
        #expect(UsageColor.forUtilization(0.51) == .yellow)
        #expect(UsageColor.forUtilization(0.75) == .yellow)
        #expect(UsageColor.forUtilization(0.76) == .orange)
        #expect(UsageColor.forUtilization(0.9) == .orange)
        #expect(UsageColor.forUtilization(0.91) == .red)
        #expect(UsageColor.forUtilization(1.0) == .red)
    }
}
