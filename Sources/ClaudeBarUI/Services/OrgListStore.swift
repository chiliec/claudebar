import Foundation

public protocol OrgListStore {
    func load() -> [Organization]
    func save(_ organizations: [Organization])
    func clear()
}

public final class UserDefaultsOrgListStore: OrgListStore {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "com.claudebar.organizations") {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> [Organization] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([Organization].self, from: data)) ?? []
    }

    public func save(_ organizations: [Organization]) {
        guard let data = try? JSONEncoder().encode(organizations) else { return }
        defaults.set(data, forKey: key)
    }

    public func clear() {
        defaults.removeObject(forKey: key)
    }
}

public final class InMemoryOrgListStore: OrgListStore {
    private var storage: [Organization] = []

    public init(initial: [Organization] = []) {
        self.storage = initial
    }

    public func load() -> [Organization] { storage }
    public func save(_ organizations: [Organization]) { storage = organizations }
    public func clear() { storage = [] }
}
