import Foundation

struct IgnoredUnusedElementsStore {
    private let defaults: UserDefaults
    private let storageKey = "ignoredUnusedElementIDsByProject"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> [String: Set<String>] {
        guard let data = defaults.data(forKey: storageKey) else {
            return [:]
        }

        guard let decoded = try? decoder.decode([String: [String]].self, from: data) else {
            return [:]
        }

        return decoded.mapValues(Set.init)
    }

    func save(_ ignoredIDsByProjectPath: [String: Set<String>]) {
        let sorted = ignoredIDsByProjectPath.mapValues { ids in
            ids.sorted()
        }

        guard let data = try? encoder.encode(sorted) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
