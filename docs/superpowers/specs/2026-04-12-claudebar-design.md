# ClaudeBar — macOS Menu Bar Usage Tracker

## Overview

A native SwiftUI macOS menu bar app that displays Claude.ai subscription usage limits. Shows a ring icon with current 5-hour utilization percentage in the menu bar. Clicking reveals a popover with detailed usage breakdown, model distribution, and subscription status.

**Target users:** Claude Pro/Max subscribers who want at-a-glance usage visibility.

## Architecture

Single-target SwiftUI macOS app. Menu bar only — no dock icon (`LSUIElement = true`).

```
┌─────────────────────────────────┐
│  Menu Bar UI (SwiftUI)          │
│  ├─ MenuBarView (icon + %)     │
│  └─ PopoverView (details)       │
├─────────────────────────────────┤
│  UsageService                   │
│  ├─ Timer-based polling (5m)    │
│  └─ Manual refresh              │
├─────────────────────────────────┤
│  Auth (Keychain)                │
│  └─ sessionKey + orgId storage  │
└─────────────────────────────────┘
```

**Deployment target:** macOS 14+ (Sonoma)

## Data Source

### API Endpoint

```
GET https://claude.ai/api/organizations/{org_id}/usage
Cookie: sessionKey={sk-ant-sid01-...}
```

### Response Model

> **Note:** The field names below are based on patterns observed in existing open-source tools. The actual JSON field names must be verified against a real API response during implementation. The first implementation task should be to capture and inspect a real response.

```swift
struct UsageResponse: Codable {
    let fiveHour: WindowUsage       // 5-hour rolling window
    let sevenDay: WindowUsage       // 7-day total usage
    let sevenDayOpus: WindowUsage?  // Opus-specific weekly (Max only)
    let modelBreakdown: [ModelUsage]?
}

struct WindowUsage: Codable {
    let utilization: Double  // 0.0 to 1.0
    let resetAt: Date        // ISO 8601
    let isActive: Bool       // currently rate-limited
}

struct ModelUsage: Codable {
    let model: String        // "opus", "sonnet", "haiku"
    let tokensUsed: Int
}
```

### Organization Discovery

On first auth, call `GET https://claude.ai/api/organizations` with the sessionKey cookie to fetch available organizations and their IDs.

### Derived Values

| Display               | Source                                         |
|-----------------------|------------------------------------------------|
| Menu bar "73%"        | `fiveHour.utilization × 100`                   |
| "Resets in 2h 15m"   | `fiveHour.resetAt - now`                       |
| Sonnet/Opus/Haiku %   | Per-model tokens / total tokens                |
| Subscription tier     | Inferred from available limit windows           |

## UI Design

### Menu Bar

- **Ring icon** that fills proportionally to 5-hour utilization
- **Percentage text** next to the icon (e.g., "73%")
- **Color coding** based on utilization:
  - 0-50%: Green (`#4ade80`)
  - 50-75%: Yellow (`#facc15`)
  - 75-90%: Orange (`#D4A574`)
  - 90-100%: Red (`#ef4444`)

### Popover (on click)

Sections from top to bottom:

1. **Header** — "Claude Usage" title + subscription tier badge (e.g., "Max $100")
2. **5-Hour Window** — Large progress bar with percentage, reset countdown
3. **Model Breakdown** — Three cards showing Opus %, Sonnet %, Haiku % of usage
4. **7-Day Windows** — Slim progress bars for total weekly and Opus weekly limits
5. **Footer** — "Last updated" timestamp, Refresh button, Settings button

### Settings View

Accessible from ⚙ in popover footer:

- Current sessionKey status (valid / expired)
- Update sessionKey button
- Polling interval slider (default 5 min)
- Launch at login toggle
- Quit app button

## Authentication Flow

### First Launch

1. App shows setup popover with instructions: "Open claude.ai → DevTools (⌘⌥I) → Application → Cookies → copy `sessionKey` value"
2. User pastes sessionKey into text field
3. App validates by calling `/api/organizations`
4. If multiple orgs exist, user selects one; otherwise auto-selects
5. sessionKey and orgId stored in macOS Keychain
6. Polling starts immediately

### Session Expiry

- When API returns 401/403, menu bar icon turns gray with "!" indicator
- Popover shows "Session expired — update your key" message
- User pastes new key, app resumes

### Security

- sessionKey stored in macOS Keychain (not UserDefaults or files)
- No credentials written to disk in plaintext
- Key cleared from memory after storage

## Polling Strategy

- Default interval: 5 minutes
- Configurable via settings
- Pauses when macOS is asleep / screen locked
- Immediate refresh available via popover button
- Backs off to 15 minutes on repeated errors

## Project Structure

```
ClaudeBar/
├── ClaudeBarApp.swift          # App entry, menu bar setup
├── Views/
│   ├── MenuBarView.swift       # Ring icon + percentage
│   ├── PopoverView.swift       # Detail popover content
│   └── SettingsView.swift      # Settings/auth configuration
├── Models/
│   ├── UsageModel.swift        # Data models (UsageResponse, etc.)
│   └── AppState.swift          # Observable app state
├── Services/
│   ├── UsageService.swift      # API calls + polling timer
│   ├── KeychainService.swift   # Secure credential storage
│   └── OrganizationService.swift # Org discovery
└── Utilities/
    └── RingProgressView.swift  # Custom ring icon view
```

## Supported Plans

| Plan        | 5-Hour Window | 7-Day Total | 7-Day Opus | Model Breakdown |
|-------------|:---:|:---:|:---:|:---:|
| Pro $20     | ✓   | ✓   | —   | ✓   |
| Max $100    | ✓   | ✓   | ✓   | ✓   |
| Max $200    | ✓   | ✓   | ✓   | ✓   |

The app adapts the popover layout based on which limit windows exist in the API response. Pro users won't see the Opus weekly section.

## Error Handling

- **Network errors** — Show last known data with "offline" indicator, retry on next poll
- **401/403** — Session expired flow (gray icon, re-auth prompt)
- **429** — Back off polling interval temporarily
- **Unknown response format** — Log error, show "unable to fetch" in popover

## Out of Scope (v1)

- Webview-based login (manual cookie paste only)
- Notifications at usage thresholds
- Historical usage charts
- Multiple account support
- iOS/iPad companion app
