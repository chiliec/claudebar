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

    @Test func buildPlatformOrganizationsRequest() throws {
        let request = try ClaudeAPIClient.buildPlatformOrganizationsRequest(platformSessionKey: "sk-test")
        #expect(request.url?.absoluteString == "https://platform.claude.com/api/organizations")
        #expect(request.value(forHTTPHeaderField: "Cookie") == "sessionKey=sk-test")
        #expect(request.value(forHTTPHeaderField: "anthropic-client-platform") == "web_console")
        #expect(request.httpMethod == "GET")
    }

    @Test func buildPlatformCreditsRequest() throws {
        let request = try ClaudeAPIClient.buildPlatformCreditsRequest(
            platformSessionKey: "sk-test",
            platformOrgId: "8bc28b46-d6dd-4982-a38a-66a11be1c437"
        )
        #expect(request.url?.absoluteString == "https://platform.claude.com/api/organizations/8bc28b46-d6dd-4982-a38a-66a11be1c437/prepaid/credits")
        #expect(request.value(forHTTPHeaderField: "Cookie") == "sessionKey=sk-test")
        #expect(request.value(forHTTPHeaderField: "anthropic-client-platform") == "web_console")
        #expect(request.value(forHTTPHeaderField: "Referer") == "https://platform.claude.com/settings/billing")
    }

    @Test func parsePlatformOrganizationsIgnoresExtraFields() throws {
        let json = """
        [
          {
            "id": 136002694,
            "uuid": "4f4dee87-d910-4390-ae54-b64ad23b9243",
            "name": "Personal",
            "settings": { "claude_console_privacy": "default_private" },
            "capabilities": ["claude_pro", "chat"],
            "billing_type": "stripe_subscription"
          },
          {
            "id": 151870534,
            "uuid": "8bc28b46-d6dd-4982-a38a-66a11be1c437",
            "name": "Vova's Individual Org",
            "settings": {},
            "capabilities": ["api", "api_individual"],
            "billing_type": "api_evaluation"
          }
        ]
        """.data(using: .utf8)!

        let orgs = try ClaudeAPIClient.parsePlatformOrganizationsResponse(data: json)
        #expect(orgs.count == 2)
        #expect(orgs[1].uuid == "8bc28b46-d6dd-4982-a38a-66a11be1c437")
        #expect(orgs[1].capabilities?.contains("api") == true)
    }

    @Test func parsePlatformCreditsHappyPath() throws {
        let json = """
        {
          "amount": 189,
          "currency": "USD",
          "auto_reload_settings": null,
          "pending_invoice_amount_cents": null,
          "last_paid_purchase_cents": null
        }
        """.data(using: .utf8)!

        let credits = try ClaudeAPIClient.parsePlatformCreditsResponse(data: json)
        #expect(credits != nil)
        #expect(credits?.amountCents == 189)
        #expect(credits?.currency == "USD")
    }

    @Test func parsePlatformCreditsReturnsNilOnPermissionError() throws {
        let json = """
        {
          "type": "error",
          "error": {
            "type": "permission_error",
            "message": "Invalid authorization for organization",
            "details": { "error_visibility": "user_facing" }
          },
          "request_id": "req_011CarEk9gJt4F4znLHquZ25"
        }
        """.data(using: .utf8)!

        let credits = try ClaudeAPIClient.parsePlatformCreditsResponse(data: json)
        #expect(credits == nil)
    }
}
