# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

ClaudeBar is a native SwiftUI macOS menu bar app (macOS 14+) that displays Claude.ai subscription usage. It polls the Claude.ai API and shows a ring icon with utilization percentage in the menu bar, with a detail popover on click. See README.md for user-facing docs.

## Build & Test Commands

```bash
./scripts/run.sh                     # Build + sign + run (development)
./scripts/bundle.sh                  # Build release + sign + create .app bundle
swift test                           # Run all tests (65 tests)
swift test --filter AppStateTests    # Run one test suite
swift test --filter ClaudeBarTests.AppStateTests.testMenuBarTextWithNoUsage  # Run single test
```

**Do not use `swift run`** — the binary must be code-signed before launch (Keychain + SMAppService require it). Use `./scripts/run.sh` instead.

## Code Signing

Both scripts sign with `"Apple Development: Vladimir Babin (8FNR8DGE9N)"`. Ad-hoc signing (`-s -`) causes Keychain password prompts on every rebuild because macOS can't match a stable identity. If the signing identity changes, update both `scripts/run.sh` and `scripts/bundle.sh`.

## Architecture

**Three-layer architecture:** Views → AppState (ViewModel) → Services

- `AppState` is an `@Observable` class — views receive it as a plain parameter, no `@ObservedObject` wrappers needed
- `ClaudeAPIClient` is a stateless struct — request builders and response parsers are static, network calls use async/await
- `KeychainService` is a struct with constructor-injectable `serviceName` — tests use `com.claudebar.test` to avoid touching real credentials

**Key flow:** App launches → `loadCredentials()` from Keychain → if authenticated, `startPolling()` → periodic `refreshUsage()` via Timer → UI updates reactively via `@Observable`

**View routing in PopoverView:** Not authenticated → `SetupView` | Session expired → `SessionExpiredView` | Otherwise → `UsageDetailView`

## SPM Specifics

- Two targets: `ClaudeBarUI` (library with all models/services/views) and `ClaudeBar` (thin executable with `@main` entry point). This split enables SwiftUI `#Preview` support — previews don't work in executable targets without `ENABLE_DEBUG_DYLIB`
- Uses `-parse-as-library` unsafe flag in Package.swift so `@main` works in the executable target (instead of requiring `main.swift`)
- `Sources/App/Info.plist` and `Sources/App/ClaudeBar.entitlements` are excluded from the Swift target — only used by the bundle script
- ViewInspector is a test-only dependency for SwiftUI view introspection
- All types in `ClaudeBarUI` are `public` — tests import via `@testable import ClaudeBarUI`

## API Details

- Auth: `Cookie: sessionKey={value}` header on all requests to `https://claude.ai/api/...`
- The API returns utilization on a 0–100 scale; `WindowUsage` normalizes to 0–1.0 on decode (values > 1.0 are divided by 100)
- Date parsing uses a custom decoder that handles both ISO 8601 with and without fractional seconds (`.000Z` vs `Z`)
- `convertFromSnakeCase` key decoding strategy maps `five_hour` → `fiveHour`, etc.

## Testing Patterns

- View tests use ViewInspector with `@retroactive Inspectable` conformance (required because views and protocol are in different modules)
- AppState tests use `makeState()` helper that injects a test keychain (`com.claudebar.test`) and clears it before each test
- `CoreData: XPC: sendMessage: failed` warnings in test output are harmless — Keychain XPC in test sandbox
