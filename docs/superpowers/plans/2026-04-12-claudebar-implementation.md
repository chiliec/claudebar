# ClaudeBar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native SwiftUI macOS menu bar app that shows Claude.ai subscription usage (5-hour window, 7-day limits, per-model breakdown) via a ring icon + percentage in the menu bar, with a detail popover on click.

**Architecture:** Single-target SwiftUI app using `MenuBarExtra` with `.window` style for the popover. Swift Package Manager with `-parse-as-library` flag (no Xcode project needed for development). Three layers: UI (SwiftUI views), Services (API + Keychain), Models (Codable structs + observable state).

**Tech Stack:** Swift 5.9+, SwiftUI, macOS 14+ (Sonoma), URLSession, Security.framework (Keychain)

---

### Task 1: Project Scaffold

**Files:**
- Create: `Package.swift`
- Create: `Sources/ClaudeBarApp.swift`
- Create: `Sources/Info.plist`

- [ ] **Step 1: Initialize the Swift package**

Run:
```bash
cd /Users/babin/Develop/Pet/claudebar
swift package init --type executable --name ClaudeBar
```

- [ ] **Step 2: Replace Package.swift with macOS menu bar config**

Replace the generated `Package.swift` with:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClaudeBar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ClaudeBar",
            path: "Sources",
            swiftSettings: [.unsafeFlags(["-parse-as-library"])]
        ),
        .testTarget(
            name: "ClaudeBarTests",
            dependencies: ["ClaudeBar"],
            path: "Tests"
        ),
    ]
)
```

- [ ] **Step 3: Create the minimal app entry point**

Replace `Sources/main.swift` with `Sources/ClaudeBarApp.swift` (delete `main.swift` first):

```swift
import SwiftUI

@main
struct ClaudeBarApp: App {
    var body: some Scene {
        MenuBarExtra {
            VStack {
                Text("ClaudeBar — Loading...")
                Divider()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding()
            .frame(width: 300)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "circle.dashed")
                Text("—%")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
            }
        }
        .menuBarExtraStyle(.window)
    }

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }
}
```

- [ ] **Step 4: Build and verify it compiles**

Run:
```bash
swift build
```

Expected: Build succeeds. The binary is at `.build/debug/ClaudeBar`.

- [ ] **Step 5: Run the app briefly to verify the menu bar icon appears**

Run:
```bash
.build/debug/ClaudeBar &
sleep 3
kill %1
```

Expected: A menu bar icon with "—%" appears briefly. Clicking it shows a popover with "ClaudeBar — Loading..." and a Quit button.

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources/ClaudeBarApp.swift
git commit -m "feat: scaffold SwiftUI menu bar app with MenuBarExtra"
```

---

### Task 2: Data Models

**Files:**
- Create: `Sources/Models/UsageModel.swift`
- Create: `Tests/UsageModelTests.swift`

The actual API response from `GET /api/organizations/{org_id}/usage` looks like:

```json
{
  "five_hour": { "utilization": 0.42, "resets_at": "2026-04-12T15:30:00.000Z" },
  "seven_day": { "utilization": 0.15, "resets_at": "2026-04-14T12:59:00.000Z" },
  "seven_day_sonnet": { "utilization": 0.08, "resets_at": "2026-04-14T12:59:00.000Z" },
  "seven_day_opus": { "utilization": 0.03, "resets_at": null },
  "extra_usage": { "is_enabled": true, "monthly_limit": 100.0, "used_credits": 12.50, "utilization": 0.125 }
}
```

And `GET /api/organizations` returns:

```json
[{ "uuid": "abc-123", "name": "My Org", "capabilities": ["chat"] }]
```

- [ ] **Step 1: Write the model tests**

Create `Tests/UsageModelTests.swift`:

```swift
import XCTest
@testable import ClaudeBar

final class UsageModelTests: XCTestCase {
    func testDecodeFullUsageResponse() throws {
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

        XCTAssertEqual(usage.fiveHour?.utilization, 0.42)
        XCTAssertNotNil(usage.fiveHour?.resetsAt)
        XCTAssertEqual(usage.sevenDay.utilization, 0.15)
        XCTAssertEqual(usage.sevenDaySonnet?.utilization, 0.08)
        XCTAssertEqual(usage.sevenDayOpus?.utilization, 0.03)
        XCTAssertNil(usage.sevenDayOpus?.resetsAt)
        XCTAssertEqual(usage.extraUsage?.isEnabled, true)
        XCTAssertEqual(usage.extraUsage?.monthlyLimit, 100.0)
        XCTAssertEqual(usage.extraUsage?.usedCredits, 12.50)
    }

    func testDecodeMinimalResponse() throws {
        let json = """
        {
          "seven_day": { "utilization": 0.05, "resets_at": "2026-04-14T12:59:00.000Z" }
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601

        let usage = try decoder.decode(UsageResponse.self, from: json)

        XCTAssertNil(usage.fiveHour)
        XCTAssertEqual(usage.sevenDay.utilization, 0.05)
        XCTAssertNil(usage.sevenDaySonnet)
        XCTAssertNil(usage.sevenDayOpus)
        XCTAssertNil(usage.extraUsage)
    }

    func testDecodeOrganization() throws {
        let json = """
        [{ "uuid": "abc-123", "name": "My Org", "capabilities": ["chat"] }]
        """.data(using: .utf8)!

        let orgs = try JSONDecoder().decode([Organization].self, from: json)

        XCTAssertEqual(orgs.count, 1)
        XCTAssertEqual(orgs[0].uuid, "abc-123")
        XCTAssertEqual(orgs[0].name, "My Org")
    }

    func testSonnetPercentage() {
        let usage = UsageResponse(
            fiveHour: WindowUsage(utilization: 0.5, resetsAt: nil),
            sevenDay: WindowUsage(utilization: 0.3, resetsAt: nil),
            sevenDaySonnet: WindowUsage(utilization: 0.2, resetsAt: nil),
            sevenDayOpus: WindowUsage(utilization: 0.08, resetsAt: nil),
            extraUsage: nil
        )
        // Sonnet % of total 7-day = 0.2 / 0.3 = 66.7%
        let sonnetPct = usage.sonnetPercentage
        XCTAssertEqual(sonnetPct!, 66.7, accuracy: 0.1)
    }

    func testColorForUtilization() {
        XCTAssertEqual(UsageColor.forUtilization(0.0), .green)
        XCTAssertEqual(UsageColor.forUtilization(0.3), .green)
        XCTAssertEqual(UsageColor.forUtilization(0.5), .green)
        XCTAssertEqual(UsageColor.forUtilization(0.51), .yellow)
        XCTAssertEqual(UsageColor.forUtilization(0.75), .yellow)
        XCTAssertEqual(UsageColor.forUtilization(0.76), .orange)
        XCTAssertEqual(UsageColor.forUtilization(0.9), .orange)
        XCTAssertEqual(UsageColor.forUtilization(0.91), .red)
        XCTAssertEqual(UsageColor.forUtilization(1.0), .red)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
swift test --filter UsageModelTests 2>&1 | tail -20
```

Expected: Compilation errors — `UsageResponse`, `Organization`, `UsageColor` not defined.

- [ ] **Step 3: Implement the models**

Create `Sources/Models/UsageModel.swift`:

```swift
import SwiftUI

// MARK: - API Response Models

struct UsageResponse: Codable {
    let fiveHour: WindowUsage?
    let sevenDay: WindowUsage
    let sevenDaySonnet: WindowUsage?
    let sevenDayOpus: WindowUsage?
    let extraUsage: ExtraUsage?

    /// Sonnet's share of total 7-day usage as a percentage (0-100), or nil if no data.
    var sonnetPercentage: Double? {
        guard let sonnet = sevenDaySonnet, sevenDay.utilization > 0 else { return nil }
        return (sonnet.utilization / sevenDay.utilization) * 100.0
    }

    /// Opus's share of total 7-day usage as a percentage (0-100), or nil if no data.
    var opusPercentage: Double? {
        guard let opus = sevenDayOpus, sevenDay.utilization > 0 else { return nil }
        return (opus.utilization / sevenDay.utilization) * 100.0
    }
}

struct WindowUsage: Codable {
    let utilization: Double
    let resetsAt: Date?
}

struct ExtraUsage: Codable {
    let isEnabled: Bool
    let monthlyLimit: Double?
    let usedCredits: Double?
    let utilization: Double?
}

struct Organization: Codable {
    let uuid: String
    let name: String
    let capabilities: [String]?
}

// MARK: - Display Helpers

enum UsageColor {
    case green, yellow, orange, red

    static func forUtilization(_ value: Double) -> UsageColor {
        switch value {
        case ..<0.51: return .green
        case ..<0.76: return .yellow
        case ..<0.91: return .orange
        default: return .red
        }
    }

    var swiftUIColor: Color {
        switch self {
        case .green: return Color(red: 0.29, green: 0.87, blue: 0.50)   // #4ade80
        case .yellow: return Color(red: 0.98, green: 0.80, blue: 0.08)  // #facc15
        case .orange: return Color(red: 0.83, green: 0.65, blue: 0.46)  // #D4A574
        case .red: return Color(red: 0.94, green: 0.27, blue: 0.27)     // #ef4444
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
swift test --filter UsageModelTests 2>&1 | tail -20
```

Expected: All 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Models/UsageModel.swift Tests/UsageModelTests.swift
git commit -m "feat: add Codable data models for usage API response"
```

---

### Task 3: Keychain Service

**Files:**
- Create: `Sources/Services/KeychainService.swift`
- Create: `Tests/KeychainServiceTests.swift`

- [ ] **Step 1: Write the keychain service tests**

Create `Tests/KeychainServiceTests.swift`:

```swift
import XCTest
@testable import ClaudeBar

final class KeychainServiceTests: XCTestCase {
    let service = KeychainService(serviceName: "com.claudebar.test")

    override func tearDown() {
        try? service.delete(account: "sessionKey")
        try? service.delete(account: "orgId")
    }

    func testSaveAndRetrieve() throws {
        try service.save(account: "sessionKey", value: "sk-ant-sid01-test123")
        let retrieved = try service.retrieve(account: "sessionKey")
        XCTAssertEqual(retrieved, "sk-ant-sid01-test123")
    }

    func testRetrieveNonExistent() {
        let result = try? service.retrieve(account: "nonexistent")
        XCTAssertNil(result)
    }

    func testOverwriteExisting() throws {
        try service.save(account: "sessionKey", value: "old-value")
        try service.save(account: "sessionKey", value: "new-value")
        let retrieved = try service.retrieve(account: "sessionKey")
        XCTAssertEqual(retrieved, "new-value")
    }

    func testDelete() throws {
        try service.save(account: "orgId", value: "abc-123")
        try service.delete(account: "orgId")
        let result = try? service.retrieve(account: "orgId")
        XCTAssertNil(result)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
swift test --filter KeychainServiceTests 2>&1 | tail -20
```

Expected: Compilation error — `KeychainService` not defined.

- [ ] **Step 3: Implement the keychain service**

Create `Sources/Services/KeychainService.swift`:

```swift
import Foundation
import Security

struct KeychainService {
    let serviceName: String

    init(serviceName: String = "com.claudebar") {
        self.serviceName = serviceName
    }

    func save(account: String, value: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

        // Delete existing item first (upsert pattern)
        try? delete(account: account)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    func retrieve(account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError.retrieveFailed(status)
        }
        return String(data: data, encoding: .utf8)
    }

    func delete(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }
}

enum KeychainError: Error {
    case encodingFailed
    case saveFailed(OSStatus)
    case retrieveFailed(OSStatus)
    case deleteFailed(OSStatus)
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
swift test --filter KeychainServiceTests 2>&1 | tail -20
```

Expected: All 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Services/KeychainService.swift Tests/KeychainServiceTests.swift
git commit -m "feat: add Keychain service for secure credential storage"
```

---

### Task 4: API Client

**Files:**
- Create: `Sources/Services/ClaudeAPIClient.swift`
- Create: `Tests/ClaudeAPIClientTests.swift`

- [ ] **Step 1: Write the API client tests**

Create `Tests/ClaudeAPIClientTests.swift`:

```swift
import XCTest
@testable import ClaudeBar

final class ClaudeAPIClientTests: XCTestCase {
    func testBuildUsageRequest() throws {
        let client = ClaudeAPIClient(sessionKey: "sk-test", orgId: "org-123")
        let request = client.buildUsageRequest()

        XCTAssertEqual(request.url?.absoluteString, "https://claude.ai/api/organizations/org-123/usage")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "sessionKey=sk-test")
        XCTAssertEqual(request.httpMethod, "GET")
    }

    func testBuildOrganizationsRequest() {
        let request = ClaudeAPIClient.buildOrganizationsRequest(sessionKey: "sk-test")

        XCTAssertEqual(request.url?.absoluteString, "https://claude.ai/api/organizations")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "sessionKey=sk-test")
    }

    func testParseUsageResponse() throws {
        let json = """
        {
          "five_hour": { "utilization": 0.73, "resets_at": "2026-04-12T15:30:00.000Z" },
          "seven_day": { "utilization": 0.31, "resets_at": "2026-04-14T12:59:00.000Z" },
          "seven_day_sonnet": { "utilization": 0.20, "resets_at": "2026-04-14T12:59:00.000Z" },
          "seven_day_opus": { "utilization": 0.08, "resets_at": null }
        }
        """.data(using: .utf8)!

        let usage = try ClaudeAPIClient.parseUsageResponse(data: json)
        XCTAssertEqual(usage.fiveHour?.utilization, 0.73)
        XCTAssertEqual(usage.sevenDay.utilization, 0.31)
        XCTAssertEqual(usage.sevenDaySonnet?.utilization, 0.20)
    }

    func testParseOrganizationsResponse() throws {
        let json = """
        [
          { "uuid": "org-abc", "name": "Personal" },
          { "uuid": "org-def", "name": "Work" }
        ]
        """.data(using: .utf8)!

        let orgs = try ClaudeAPIClient.parseOrganizationsResponse(data: json)
        XCTAssertEqual(orgs.count, 2)
        XCTAssertEqual(orgs[0].uuid, "org-abc")
        XCTAssertEqual(orgs[1].name, "Work")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
swift test --filter ClaudeAPIClientTests 2>&1 | tail -20
```

Expected: Compilation error — `ClaudeAPIClient` not defined.

- [ ] **Step 3: Implement the API client**

Create `Sources/Services/ClaudeAPIClient.swift`:

```swift
import Foundation

struct ClaudeAPIClient {
    private static let baseURL = "https://claude.ai"

    let sessionKey: String
    let orgId: String

    // MARK: - Request Builders

    func buildUsageRequest() -> URLRequest {
        let url = URL(string: "\(Self.baseURL)/api/organizations/\(orgId)/usage")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
        return request
    }

    static func buildOrganizationsRequest(sessionKey: String) -> URLRequest {
        let url = URL(string: "\(baseURL)/api/organizations")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
        return request
    }

    // MARK: - Response Parsers

    static func parseUsageResponse(data: Data) throws -> UsageResponse {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            // Try ISO 8601 with fractional seconds first, then without
            let formatters = [ISO8601DateFormatter.withFractionalSeconds, ISO8601DateFormatter.standard]
            for formatter in formatters {
                if let date = formatter.date(from: dateString) { return date }
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot parse date: \(dateString)")
        }
        return try decoder.decode(UsageResponse.self, from: data)
    }

    static func parseOrganizationsResponse(data: Data) throws -> [Organization] {
        return try JSONDecoder().decode([Organization].self, from: data)
    }

    // MARK: - Network Calls

    func fetchUsage() async throws -> UsageResponse {
        let (data, response) = try await URLSession.shared.data(for: buildUsageRequest())
        try Self.validateHTTPResponse(response)
        return try Self.parseUsageResponse(data: data)
    }

    static func fetchOrganizations(sessionKey: String) async throws -> [Organization] {
        let request = buildOrganizationsRequest(sessionKey: sessionKey)
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

enum APIError: Error, Equatable {
    case invalidResponse
    case sessionExpired
    case rateLimited
    case httpError(Int)
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```bash
swift test --filter ClaudeAPIClientTests 2>&1 | tail -20
```

Expected: All 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Services/ClaudeAPIClient.swift Tests/ClaudeAPIClientTests.swift
git commit -m "feat: add Claude API client with request building and response parsing"
```

---

### Task 5: App State (Observable ViewModel)

**Files:**
- Create: `Sources/Models/AppState.swift`

- [ ] **Step 1: Implement the observable app state**

Create `Sources/Models/AppState.swift`:

```swift
import SwiftUI

@Observable
final class AppState {
    // MARK: - Auth State
    var sessionKey: String?
    var orgId: String?
    var organizations: [Organization] = []
    var isAuthenticated: Bool { sessionKey != nil && orgId != nil }

    // MARK: - Usage State
    var usage: UsageResponse?
    var lastUpdated: Date?
    var isLoading = false
    var error: AppError?

    // MARK: - UI State
    var showingSettings = false

    // MARK: - Services
    private let keychain = KeychainService()
    private var pollTimer: Timer?
    var pollInterval: TimeInterval = 300 // 5 minutes

    // MARK: - Computed Display Values

    var menuBarText: String {
        guard let usage else { return "—%" }
        let pct = Int((usage.fiveHour?.utilization ?? usage.sevenDay.utilization) * 100)
        return "\(pct)%"
    }

    var menuBarUtilization: Double {
        usage?.fiveHour?.utilization ?? usage?.sevenDay.utilization ?? 0
    }

    var usageColor: UsageColor {
        UsageColor.forUtilization(menuBarUtilization)
    }

    // MARK: - Lifecycle

    func loadCredentials() {
        sessionKey = try? keychain.retrieve(account: "sessionKey")
        orgId = try? keychain.retrieve(account: "orgId")
    }

    func saveCredentials(sessionKey: String, orgId: String) throws {
        try keychain.save(account: "sessionKey", value: sessionKey)
        try keychain.save(account: "orgId", value: orgId)
        self.sessionKey = sessionKey
        self.orgId = orgId
    }

    func clearCredentials() {
        try? keychain.delete(account: "sessionKey")
        try? keychain.delete(account: "orgId")
        sessionKey = nil
        orgId = nil
        usage = nil
        organizations = []
    }

    // MARK: - API Calls

    func validateAndFetchOrgs(sessionKey: String) async {
        isLoading = true
        error = nil
        do {
            organizations = try await ClaudeAPIClient.fetchOrganizations(sessionKey: sessionKey)
            if organizations.count == 1 {
                try saveCredentials(sessionKey: sessionKey, orgId: organizations[0].uuid)
                await refreshUsage()
            }
        } catch let apiError as APIError {
            error = .api(apiError)
        } catch {
            self.error = .network(error.localizedDescription)
        }
        isLoading = false
    }

    func selectOrganization(_ org: Organization) async {
        guard let sessionKey else { return }
        do {
            try saveCredentials(sessionKey: sessionKey, orgId: org.uuid)
            await refreshUsage()
        } catch {
            self.error = .network(error.localizedDescription)
        }
    }

    func refreshUsage() async {
        guard let sessionKey, let orgId else { return }
        isLoading = true
        error = nil
        let client = ClaudeAPIClient(sessionKey: sessionKey, orgId: orgId)
        do {
            usage = try await client.fetchUsage()
            lastUpdated = Date()
        } catch APIError.sessionExpired {
            error = .sessionExpired
            clearCredentials()
        } catch APIError.rateLimited {
            error = .rateLimited
        } catch {
            self.error = .network(error.localizedDescription)
        }
        isLoading = false
    }

    // MARK: - Polling

    func startPolling() {
        stopPolling()
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { await self.refreshUsage() }
        }
        // Also fetch immediately
        Task { await refreshUsage() }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }
}

enum AppError: Equatable {
    case api(APIError)
    case sessionExpired
    case rateLimited
    case network(String)

    var message: String {
        switch self {
        case .sessionExpired: return "Session expired — update your key"
        case .rateLimited: return "Rate limited — will retry"
        case .api(let e): return "API error: \(e)"
        case .network(let msg): return msg
        }
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run:
```bash
swift build 2>&1 | tail -10
```

Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Sources/Models/AppState.swift
git commit -m "feat: add observable AppState with auth, polling, and usage management"
```

---

### Task 6: Ring Progress View (Menu Bar Icon)

**Files:**
- Create: `Sources/Views/RingProgressView.swift`

- [ ] **Step 1: Implement the ring progress view**

Create `Sources/Views/RingProgressView.swift`:

```swift
import SwiftUI

struct RingProgressView: View {
    let progress: Double // 0.0 to 1.0
    let color: Color
    let size: CGFloat

    init(progress: Double, color: Color, size: CGFloat = 16) {
        self.progress = min(max(progress, 0), 1)
        self.color = color
        self.size = size
    }

    var body: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(color.opacity(0.25), lineWidth: size * 0.15)

            // Progress arc
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: size * 0.15, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run:
```bash
swift build 2>&1 | tail -5
```

Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Sources/Views/RingProgressView.swift
git commit -m "feat: add ring progress view for menu bar icon"
```

---

### Task 7: Popover View

**Files:**
- Create: `Sources/Views/PopoverView.swift`

- [ ] **Step 1: Implement the popover view**

Create `Sources/Views/PopoverView.swift`:

```swift
import SwiftUI

struct PopoverView: View {
    let state: AppState

    var body: some View {
        VStack(spacing: 0) {
            if !state.isAuthenticated {
                SetupView(state: state)
            } else if let error = state.error, error == .sessionExpired {
                SessionExpiredView(state: state)
            } else {
                UsageDetailView(state: state)
            }
        }
        .frame(width: 320)
    }
}

// MARK: - Usage Detail View

private struct UsageDetailView: View {
    let state: AppState

    var body: some View {
        VStack(spacing: 0) {
            header
            if let usage = state.usage {
                fiveHourSection(usage)
                modelBreakdown(usage)
                sevenDaySection(usage)
            } else if state.isLoading {
                ProgressView()
                    .padding(40)
            } else if let error = state.error {
                Text(error.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(20)
            }
            footer
        }
    }

    private var header: some View {
        HStack {
            Text("Claude Usage")
                .font(.headline)
            Spacer()
            if let usage = state.usage {
                Text(tierLabel(usage))
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.quaternary)
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func fiveHourSection(_ usage: UsageResponse) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("5-Hour Window")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let reset = usage.fiveHour?.resetsAt {
                    Text("Resets in \(resetTimeString(reset))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            let utilization = usage.fiveHour?.utilization ?? 0
            let color = UsageColor.forUtilization(utilization).swiftUIColor

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.quaternary)
                    .frame(height: 20)
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 6)
                        .fill(color)
                        .frame(width: geo.size.width * utilization, height: 20)
                }
                .frame(height: 20)
                Text("\(Int(utilization * 100))%")
                    .font(.system(size: 11, weight: .bold))
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private func modelBreakdown(_ usage: UsageResponse) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Model Breakdown")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                if let opusPct = usage.opusPercentage {
                    modelCard(name: "Opus", percentage: opusPct, color: Color(red: 0.75, green: 0.52, blue: 0.99))
                }
                if let sonnetPct = usage.sonnetPercentage {
                    modelCard(name: "Sonnet", percentage: sonnetPct, color: Color(red: 0.38, green: 0.65, blue: 0.98))
                }
                // "Other" = remainder
                if let opus = usage.opusPercentage, let sonnet = usage.sonnetPercentage {
                    let other = max(0, 100 - opus - sonnet)
                    if other > 0.5 {
                        modelCard(name: "Other", percentage: other, color: Color(red: 0.20, green: 0.83, blue: 0.60))
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private func modelCard(name: String, percentage: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(Int(percentage))%")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func sevenDaySection(_ usage: UsageResponse) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("7-Day Windows")
                .font(.caption)
                .foregroundStyle(.secondary)

            slimBar(label: "Total", utilization: usage.sevenDay.utilization, resetDate: usage.sevenDay.resetsAt, color: .blue)

            if let opus = usage.sevenDayOpus {
                slimBar(label: "Opus", utilization: opus.utilization, resetDate: opus.resetsAt, color: Color(red: 0.75, green: 0.52, blue: 0.99))
            }

            if let sonnet = usage.sevenDaySonnet {
                slimBar(label: "Sonnet", utilization: sonnet.utilization, resetDate: sonnet.resetsAt, color: Color(red: 0.38, green: 0.65, blue: 0.98))
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private func slimBar(label: String, utilization: Double, resetDate: Date?, color: Color) -> some View {
        VStack(spacing: 3) {
            HStack {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(utilization * 100))%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if let date = resetDate {
                    Text("· resets \(shortResetString(date))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.quaternary)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: geo.size.width * utilization)
                }
            }
            .frame(height: 8)
        }
    }

    private var footer: some View {
        HStack {
            if let lastUpdated = state.lastUpdated {
                Text("Updated \(lastUpdated, style: .relative) ago")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button("Refresh") {
                Task { await state.refreshUsage() }
            }
            .font(.caption2)
            .buttonStyle(.plain)
            .foregroundStyle(.blue)
            Button("Settings") {
                state.showingSettings = true
            }
            .font(.caption2)
            .buttonStyle(.plain)
            .foregroundStyle(.blue)
            .padding(.leading, 8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func tierLabel(_ usage: UsageResponse) -> String {
        if usage.sevenDayOpus != nil {
            if let extra = usage.extraUsage, let limit = extra.monthlyLimit {
                return "Max $\(Int(limit))"
            }
            return "Max"
        }
        return "Pro"
    }

    private func resetTimeString(_ date: Date) -> String {
        let interval = date.timeIntervalSinceNow
        if interval <= 0 { return "now" }
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    private func shortResetString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }
}

// MARK: - Setup View (first-launch auth)

struct SetupView: View {
    let state: AppState
    @State private var keyInput = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Setup ClaudeBar")
                .font(.headline)

            Text("1. Open **claude.ai** in your browser\n2. DevTools (⌘⌥I) → Application → Cookies\n3. Copy the `sessionKey` value")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("Paste sessionKey here...", text: $keyInput)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))

            if state.organizations.count > 1 {
                Text("Select organization:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(state.organizations, id: \.uuid) { org in
                    Button(org.name) {
                        Task { await state.selectOrganization(org) }
                    }
                    .buttonStyle(.bordered)
                }
            }

            if state.isLoading {
                ProgressView()
                    .scaleEffect(0.8)
            }

            if let error = state.error {
                Text(error.message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Connect") {
                    Task { await state.validateAndFetchOrgs(sessionKey: keyInput) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(keyInput.isEmpty || state.isLoading)
            }

            Divider()
            Button("Quit ClaudeBar") {
                NSApplication.shared.terminate(nil)
            }
            .font(.caption)
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(16)
    }
}

// MARK: - Session Expired View

struct SessionExpiredView: View {
    let state: AppState
    @State private var keyInput = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Session Expired", systemImage: "exclamationmark.triangle")
                .font(.headline)
                .foregroundStyle(.orange)

            Text("Your sessionKey has expired. Paste a new one from claude.ai cookies.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("Paste new sessionKey...", text: $keyInput)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))

            HStack {
                Spacer()
                Button("Reconnect") {
                    Task { await state.validateAndFetchOrgs(sessionKey: keyInput) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(keyInput.isEmpty || state.isLoading)
            }
        }
        .padding(16)
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run:
```bash
swift build 2>&1 | tail -10
```

Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Sources/Views/PopoverView.swift
git commit -m "feat: add popover view with usage details, setup, and session expired states"
```

---

### Task 8: Settings View

**Files:**
- Create: `Sources/Views/SettingsView.swift`

- [ ] **Step 1: Implement the settings view**

Create `Sources/Views/SettingsView.swift`:

```swift
import SwiftUI
import ServiceManagement

struct SettingsView: View {
    let state: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Settings")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                    .font(.caption)
            }

            // Session status
            GroupBox("Session") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Circle()
                            .fill(state.isAuthenticated ? .green : .red)
                            .frame(width: 8, height: 8)
                        Text(state.isAuthenticated ? "Connected" : "Not connected")
                            .font(.caption)
                    }
                    Button("Update Session Key") {
                        state.clearCredentials()
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }

            // Launch at login
            GroupBox("General") {
                VStack(alignment: .leading, spacing: 8) {
                    LaunchAtLoginToggle()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }

            Spacer()

            Button("Quit ClaudeBar") {
                NSApplication.shared.terminate(nil)
            }
            .font(.caption)
            .buttonStyle(.plain)
            .foregroundStyle(.red)
        }
        .padding(16)
        .frame(width: 320, height: 280)
    }
}

struct LaunchAtLoginToggle: View {
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Toggle("Launch at login", isOn: $launchAtLogin)
            .font(.caption)
            .onChange(of: launchAtLogin) { _, newValue in
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    launchAtLogin = !newValue // revert on failure
                }
            }
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run:
```bash
swift build 2>&1 | tail -10
```

Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Sources/Views/SettingsView.swift
git commit -m "feat: add settings view with session status and launch at login"
```

---

### Task 9: Wire Everything Together in App Entry Point

**Files:**
- Modify: `Sources/ClaudeBarApp.swift`

- [ ] **Step 1: Update the app entry point to use all components**

Replace the contents of `Sources/ClaudeBarApp.swift` with:

```swift
import SwiftUI

@main
struct ClaudeBarApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            PopoverView(state: appState)
                .sheet(isPresented: $appState.showingSettings) {
                    SettingsView(state: appState)
                }
        } label: {
            HStack(spacing: 4) {
                RingProgressView(
                    progress: appState.menuBarUtilization,
                    color: appState.usageColor.swiftUIColor
                )
                Text(appState.menuBarText)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(appState.error == .sessionExpired
                        ? Color.gray
                        : appState.usageColor.swiftUIColor)
            }
        }
        .menuBarExtraStyle(.window)
    }

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }
}
```

- [ ] **Step 2: Add onAppear lifecycle to PopoverView to trigger loading**

In `Sources/Views/PopoverView.swift`, update the `PopoverView` body to add lifecycle hooks:

Find the line:
```swift
        .frame(width: 320)
```

Replace with:
```swift
        .frame(width: 320)
        .onAppear {
            appState.loadCredentials()
            if appState.isAuthenticated {
                appState.startPolling()
            }
        }
```

Use `.task` on the popover content to trigger credential loading and polling on first appearance. The full updated file:

```swift
import SwiftUI

@main
struct ClaudeBarApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            PopoverView(state: appState)
                .sheet(isPresented: $appState.showingSettings) {
                    SettingsView(state: appState)
                }
                .task {
                    appState.loadCredentials()
                    if appState.isAuthenticated {
                        appState.startPolling()
                    }
                }
        } label: {
            HStack(spacing: 4) {
                RingProgressView(
                    progress: appState.menuBarUtilization,
                    color: appState.usageColor.swiftUIColor
                )
                Text(appState.menuBarText)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(appState.error == .sessionExpired
                        ? Color.gray
                        : appState.usageColor.swiftUIColor)
            }
        }
        .menuBarExtraStyle(.window)
    }

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }
}
```

- [ ] **Step 3: Build to verify everything compiles together**

Run:
```bash
swift build 2>&1 | tail -10
```

Expected: Build succeeds.

- [ ] **Step 4: Run the app and manually verify**

Run:
```bash
.build/debug/ClaudeBar &
```

Expected:
- Menu bar shows a ring icon with "—%" (no data yet)
- Clicking opens the popover with the setup view (paste sessionKey)
- Quit button works

Kill the app when done:
```bash
kill %1
```

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeBarApp.swift
git commit -m "feat: wire app entry point with menu bar icon, popover, and lifecycle"
```

---

### Task 10: Final Integration Testing

**Files:** No new files — manual testing.

- [ ] **Step 1: Build release version**

Run:
```bash
swift build -c release 2>&1 | tail -10
```

Expected: Release build succeeds.

- [ ] **Step 2: Run all tests**

Run:
```bash
swift test 2>&1 | tail -20
```

Expected: All tests pass (UsageModelTests + KeychainServiceTests + ClaudeAPIClientTests).

- [ ] **Step 3: Manual smoke test with a real session key**

Run:
```bash
.build/release/ClaudeBar &
```

Manual checklist:
1. App appears in menu bar with ring icon and "—%"
2. Click → setup view appears with instructions
3. Paste a real sessionKey → app validates and starts showing usage
4. Ring fills to match utilization, color matches threshold
5. Popover shows 5-hour bar, model breakdown, 7-day windows
6. Refresh button works
7. Settings → Quit works

Kill the app:
```bash
kill %1
```

- [ ] **Step 4: Commit any fixes**

If fixes were needed during testing:
```bash
git add -A
git commit -m "fix: integration testing fixes"
```

---

### Task 11: Create .app Bundle

**Files:**
- Create: `scripts/bundle.sh`
- Create: `Sources/Info.plist`

To distribute the app as a proper `.app` bundle (with dock icon hidden, proper name in menu bar), we need to wrap the binary.

- [ ] **Step 1: Create Info.plist**

Create `Sources/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>ClaudeBar</string>
    <key>CFBundleIdentifier</key>
    <string>com.claudebar.app</string>
    <key>CFBundleName</key>
    <string>ClaudeBar</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
</dict>
</plist>
```

- [ ] **Step 2: Create bundle script**

Create `scripts/bundle.sh`:

```bash
#!/bin/bash
set -e

APP_NAME="ClaudeBar"
BUILD_DIR=".build/release"
BUNDLE_DIR="$BUILD_DIR/$APP_NAME.app"

echo "Building release..."
swift build -c release

echo "Creating app bundle..."
rm -rf "$BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR/Contents/MacOS"
mkdir -p "$BUNDLE_DIR/Contents/Resources"

cp "$BUILD_DIR/$APP_NAME" "$BUNDLE_DIR/Contents/MacOS/"
cp Sources/Info.plist "$BUNDLE_DIR/Contents/"

echo "Done: $BUNDLE_DIR"
echo "To install: cp -r $BUNDLE_DIR /Applications/"
```

- [ ] **Step 3: Make script executable and run it**

Run:
```bash
chmod +x scripts/bundle.sh
./scripts/bundle.sh
```

Expected: `.build/release/ClaudeBar.app` is created.

- [ ] **Step 4: Test the .app bundle**

Run:
```bash
open .build/release/ClaudeBar.app
```

Expected: App launches, no dock icon appears, menu bar icon shows up. Verify it works the same as the raw binary.

Quit via the popover Quit button or:
```bash
pkill ClaudeBar
```

- [ ] **Step 5: Commit**

```bash
git add Sources/Info.plist scripts/bundle.sh
git commit -m "feat: add .app bundle creation script and Info.plist"
```
