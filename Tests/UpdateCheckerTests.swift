import Testing
@testable import ClaudeBarUI

@Suite
struct UpdateCheckerTests {
    @Test func newerMajorVersion() {
        #expect(UpdateChecker.compareVersions("2.0.0", isNewerThan: "1.0.0"))
    }

    @Test func newerMinorVersion() {
        #expect(UpdateChecker.compareVersions("1.1.0", isNewerThan: "1.0.0"))
    }

    @Test func newerPatchVersion() {
        #expect(UpdateChecker.compareVersions("1.0.1", isNewerThan: "1.0.0"))
    }

    @Test func sameVersion() {
        #expect(!UpdateChecker.compareVersions("1.0.0", isNewerThan: "1.0.0"))
    }

    @Test func olderVersion() {
        #expect(!UpdateChecker.compareVersions("1.0.0", isNewerThan: "1.1.0"))
    }

    @Test func differentLengthVersions() {
        #expect(UpdateChecker.compareVersions("1.0.0.1", isNewerThan: "1.0.0"))
        #expect(!UpdateChecker.compareVersions("1.0", isNewerThan: "1.0.0"))
    }
}
