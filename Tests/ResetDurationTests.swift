import Testing
import Foundation
@testable import ClaudeBarUI

@Suite
struct ResetDurationTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func zeroInterval() {
        #expect(ResetDuration.string(from: now, now: now) == "0h 0m")
    }

    @Test func pastDateClampsToZero() {
        let past = now.addingTimeInterval(-3600)
        #expect(ResetDuration.string(from: past, now: now) == "0h 0m")
    }

    @Test func subMinuteTruncatesToZero() {
        let future = now.addingTimeInterval(30)
        #expect(ResetDuration.string(from: future, now: now) == "0h 0m")
    }

    @Test func minutesOnly() {
        let future = now.addingTimeInterval(45 * 60)
        #expect(ResetDuration.string(from: future, now: now) == "0h 45m")
    }

    @Test func exactlyOneHour() {
        let future = now.addingTimeInterval(3600)
        #expect(ResetDuration.string(from: future, now: now) == "1h 0m")
    }

    @Test func hoursAndMinutes() {
        let future = now.addingTimeInterval(3600 + 30 * 60)
        #expect(ResetDuration.string(from: future, now: now) == "1h 30m")
    }

    @Test func justUnder24Hours() {
        let future = now.addingTimeInterval(23 * 3600 + 59 * 60)
        #expect(ResetDuration.string(from: future, now: now) == "23h 59m")
    }

    @Test func exactly24HoursCrossesToDays() {
        let future = now.addingTimeInterval(24 * 3600)
        #expect(ResetDuration.string(from: future, now: now) == "1d 0h")
    }

    @Test func daysAndHours() {
        let future = now.addingTimeInterval(3 * 86_400 + 14 * 3600)
        #expect(ResetDuration.string(from: future, now: now) == "3d 14h")
    }

    @Test func exactWholeDays() {
        let future = now.addingTimeInterval(7 * 86_400)
        #expect(ResetDuration.string(from: future, now: now) == "7d 0h")
    }

    @Test func accessibilitySubMinuteUsesLessThanMinutePhrase() {
        let future = now.addingTimeInterval(30)
        let label = ResetDuration.accessibilityLabel(for: future, now: now)
        #expect(label == "Resets in less than a minute")
        #expect(!label.contains("0h 0m"))
    }

    @Test func accessibilityPastDateClampsAndUsesLessThanMinutePhrase() {
        let past = now.addingTimeInterval(-3600)
        let label = ResetDuration.accessibilityLabel(for: past, now: now)
        #expect(label == "Resets in less than a minute")
        #expect(!label.contains("0h 0m"))
    }

    @Test func accessibilityNormalIntervalProducesSpokenForm() {
        let future = now.addingTimeInterval(2 * 3600 + 30 * 60)
        let label = ResetDuration.accessibilityLabel(for: future, now: now)
        #expect(!label.isEmpty)
        #expect(!label.contains("0h 0m"))
        #expect(label.contains("hour"))
    }
}
