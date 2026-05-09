import Testing
import WebKit
@testable import ClaudeBarUI

@MainActor
@Suite
struct PlatformAuthWebViewTests {
    @Test func extractsSessionKeyForPlatformDomain() {
        let target = HTTPCookie(properties: [
            .name: "sessionKey",
            .value: "sk-ant-sid02-platform-value",
            .domain: "platform.claude.com",
            .path: "/",
        ])!
        let other = HTTPCookie(properties: [
            .name: "sessionKey",
            .value: "sk-ant-sid02-claudeai-value",
            .domain: ".claude.com",
            .path: "/",
        ])!

        let result = PlatformAuthWebView.extractPlatformSessionKey(from: [other, target])

        #expect(result == "sk-ant-sid02-platform-value")
    }

    @Test func ignoresCookiesFromWrongDomain() {
        let cookie = HTTPCookie(properties: [
            .name: "sessionKey",
            .value: "sk-claudeai",
            .domain: ".claude.com",
            .path: "/",
        ])!

        #expect(PlatformAuthWebView.extractPlatformSessionKey(from: [cookie]) == nil)
    }

    @Test func ignoresWrongName() {
        let cookie = HTTPCookie(properties: [
            .name: "csrf",
            .value: "whatever",
            .domain: "platform.claude.com",
            .path: "/",
        ])!

        #expect(PlatformAuthWebView.extractPlatformSessionKey(from: [cookie]) == nil)
    }

    @Test func returnsNilForEmptyCookies() {
        #expect(PlatformAuthWebView.extractPlatformSessionKey(from: []) == nil)
    }
}
