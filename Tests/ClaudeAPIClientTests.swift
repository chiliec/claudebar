import Testing
@testable import ClaudeBarUI

@MainActor
@Suite
struct ClaudeAPIClientTests {
    @Test func buildUsageRequest() throws {
        let client = ClaudeAPIClient(sessionKey: "sk-test", orgId: "org-123")
        let request = try client.buildUsageRequest()

        #expect(request.url?.absoluteString == "https://claude.ai/api/organizations/org-123/usage")
        #expect(request.value(forHTTPHeaderField: "Cookie") == "sessionKey=sk-test")
        #expect(request.httpMethod == "GET")
    }

    @Test func buildOrganizationsRequest() throws {
        let request = try ClaudeAPIClient.buildOrganizationsRequest(sessionKey: "sk-test")

        #expect(request.url?.absoluteString == "https://claude.ai/api/organizations")
        #expect(request.value(forHTTPHeaderField: "Cookie") == "sessionKey=sk-test")
    }

    @Test func parseUsageResponse() throws {
        let json = """
        {
          "five_hour": { "utilization": 73.0, "resets_at": "2026-04-12T15:30:00.000Z" },
          "seven_day": { "utilization": 31.0, "resets_at": "2026-04-14T12:59:00.000Z" },
          "seven_day_sonnet": { "utilization": 20.0, "resets_at": "2026-04-14T12:59:00.000Z" },
          "seven_day_opus": { "utilization": 8.0, "resets_at": null }
        }
        """.data(using: .utf8)!

        let usage = try ClaudeAPIClient.parseUsageResponse(data: json)
        #expect(abs(usage.fiveHour!.utilization - 0.73) < 0.0001)
        #expect(abs(usage.sevenDay.utilization - 0.31) < 0.0001)
        #expect(abs(usage.sevenDaySonnet!.utilization - 0.20) < 0.0001)
    }

    @Test func parseOrganizationsResponse() throws {
        let json = """
        [
          { "uuid": "org-abc", "name": "Personal" },
          { "uuid": "org-def", "name": "Work" }
        ]
        """.data(using: .utf8)!

        let orgs = try ClaudeAPIClient.parseOrganizationsResponse(data: json)
        #expect(orgs.count == 2)
        #expect(orgs[0].uuid == "org-abc")
        #expect(orgs[1].name == "Work")
    }
}
