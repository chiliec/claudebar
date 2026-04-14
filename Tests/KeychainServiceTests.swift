import Testing
@testable import ClaudeBarUI

@Suite(.serialized)
struct KeychainServiceTests {
    let service = KeychainService(serviceName: "com.claudebar.test")

    private func cleanup() {
        try? service.delete(account: "sessionKey")
        try? service.delete(account: "orgId")
    }

    @Test func saveAndRetrieve() throws {
        cleanup()
        try service.save(account: "sessionKey", value: "sk-ant-sid01-test123")
        let retrieved = try service.retrieve(account: "sessionKey")
        #expect(retrieved == "sk-ant-sid01-test123")
        cleanup()
    }

    @Test func retrieveNonExistent() {
        cleanup()
        let result = try? service.retrieve(account: "nonexistent")
        #expect(result == nil)
    }

    @Test func overwriteExisting() throws {
        cleanup()
        try service.save(account: "sessionKey", value: "old-value")
        try service.save(account: "sessionKey", value: "new-value")
        let retrieved = try service.retrieve(account: "sessionKey")
        #expect(retrieved == "new-value")
        cleanup()
    }

    @Test func delete() throws {
        cleanup()
        try service.save(account: "orgId", value: "abc-123")
        try service.delete(account: "orgId")
        let result = try? service.retrieve(account: "orgId")
        #expect(result == nil)
    }
}
