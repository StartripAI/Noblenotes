import Foundation
import CoreKit

public protocol KeyValueStore {
    func load<T: Codable>(key: String) -> T?
    func save<T: Codable>(key: String, value: T)
}

public final class InMemoryKeyValueStore: KeyValueStore {
    private var storage: [String: Data] = [:]
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init() {}

    public func load<T: Codable>(key: String) -> T? {
        guard let data = storage[key] else { return nil }
        return try? decoder.decode(T.self, from: data)
    }

    public func save<T: Codable>(key: String, value: T) {
        guard let data = try? encoder.encode(value) else { return }
        storage[key] = data
    }
}
