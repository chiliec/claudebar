import Testing
import Foundation
@testable import ClaudeBarUI

@Suite
struct UsageModelTests {
    @Test func decodeFullUsageResponse() throws {
        let json = """
        {
          "five_hour": { "utilization": 42.0, "resets_at": "2026-04-12T15:30:00.000Z" },
          "seven_day": { "utilization": 15.0, "resets_at": "2026-04-14T12:59:00.000Z" },
          "seven_day_sonnet": { "utilization": 8.0, "resets_at": "2026-04-14T12:59:00.000Z" },
          "seven_day_opus": { "utilization": 3.0, "resets_at": null },
          "extra_usage": { "is_enabled": true, "monthly_limit": 100.0, "used_credits": 12.50, "utilization": 12.5 }
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601

        let usage = try decoder.decode(UsageResponse.self, from: json)

        #expect(abs(usage.fiveHour!.utilization - 0.42) < 0.0001)
        #expect(usage.fiveHour?.resetsAt != nil)
        #expect(abs(usage.sevenDay.utilization - 0.15) < 0.0001)
        #expect(abs(usage.sevenDaySonnet!.utilization - 0.08) < 0.0001)
        #expect(abs(usage.sevenDayOpus!.utilization - 0.03) < 0.0001)
        #expect(usage.sevenDayOpus?.resetsAt == nil)
        #expect(usage.extraUsage?.isEnabled == true)
        #expect(usage.extraUsage?.monthlyLimit == 100.0)
        #expect(usage.extraUsage?.usedCredits == 12.50)
    }

    @Test func decodeMinimalResponse() throws {
        let json = """
        {
          "seven_day": { "utilization": 5.0, "resets_at": "2026-04-14T12:59:00.000Z" }
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601

        let usage = try decoder.decode(UsageResponse.self, from: json)

        #expect(usage.fiveHour == nil)
        #expect(abs(usage.sevenDay.utilization - 0.05) < 0.0001)
        #expect(usage.sevenDaySonnet == nil)
        #expect(usage.sevenDayOpus == nil)
        #expect(usage.extraUsage == nil)
    }

    @Test func decodeOnePercentDoesNotClipToFull() throws {
        let json = """
        { "seven_day": { "utilization": 1.0, "resets_at": null } }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601

        let usage = try decoder.decode(UsageResponse.self, from: json)

        #expect(abs(usage.sevenDay.utilization - 0.01) < 0.0001)
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
