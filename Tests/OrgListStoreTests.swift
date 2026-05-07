import Testing
import Foundation
@testable import ClaudeBarUI

@Suite
struct OrgListStoreTests {
    private func makeStore() -> UserDefaultsOrgListStore {
        let suite = UserDefaults(suiteName: "com.claudebar.test.orgs.\(UUID().uuidString)")!
        return UserDefaultsOrgListStore(defaults: suite, key: "organizations")
    }

    @Test func emptyByDefault() {
        let store = makeStore()
        #expect(store.load().isEmpty)
    }

    @Test func roundTripsOrganizations() {
        let store = makeStore()
        let orgs = [
            Organization(uuid: "org-1", name: "Personal", capabilities: nil),
            Organization(uuid: "org-2", name: "Work", capabilities: ["claude_pro"]),
        ]
        store.save(orgs)
        let loaded = store.load()
        #expect(loaded.count == 2)
        #expect(loaded[0].uuid == "org-1")
        #expect(loaded[0].name == "Personal")
        #expect(loaded[1].uuid == "org-2")
        #expect(loaded[1].capabilities == ["claude_pro"])
    }

    @Test func saveOverwritesPrevious() {
        let store = makeStore()
        store.save([Organization(uuid: "old", name: "Old", capabilities: nil)])
        store.save([Organization(uuid: "new", name: "New", capabilities: nil)])
        let loaded = store.load()
        #expect(loaded.count == 1)
        #expect(loaded[0].uuid == "new")
    }

    @Test func clearRemovesAll() {
        let store = makeStore()
        store.save([Organization(uuid: "x", name: "X", capabilities: nil)])
        store.clear()
        #expect(store.load().isEmpty)
    }

    @Test func corruptedDataReturnsEmpty() {
        let suite = UserDefaults(suiteName: "com.claudebar.test.orgs.\(UUID().uuidString)")!
        suite.set("not-json".data(using: .utf8), forKey: "organizations")
        let store = UserDefaultsOrgListStore(defaults: suite, key: "organizations")
        #expect(store.load().isEmpty)
    }

    @Test func inMemoryStoreRoundTrips() {
        let store = InMemoryOrgListStore()
        let orgs = [Organization(uuid: "x", name: "X", capabilities: nil)]
        store.save(orgs)
        #expect(store.load() == [Organization(uuid: "x", name: "X", capabilities: nil)])
    }
}
