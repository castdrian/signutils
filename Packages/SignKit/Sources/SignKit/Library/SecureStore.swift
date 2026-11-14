import Foundation
import Security

public protocol SecureStore: Sendable {
    func data(for key: String) throws -> Data?
    func set(_ data: Data, for key: String) throws
    func remove(_ key: String) throws
    func keys() throws -> [String]
}

public enum SecureStoreError: Error, LocalizedError, Equatable {
    case keychain(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .keychain(let status):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "error \(status)"
            return "Keychain: \(message)"
        }
    }
}

public final class KeychainStore: SecureStore, @unchecked Sendable {
    private let service: String
    private let accessGroup: String?

    public init(service: String, accessGroup: String? = nil) {
        self.service = service
        self.accessGroup = accessGroup
    }

    private func baseQuery() -> [CFString: Any] {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecUseDataProtectionKeychain: true,
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup] = accessGroup
        }
        return query
    }

    public func data(for key: String) throws -> Data? {
        var query = baseQuery()
        query[kSecAttrAccount] = key
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw SecureStoreError.keychain(status) }
        return result as? Data
    }

    public func set(_ data: Data, for key: String) throws {
        var query = baseQuery()
        query[kSecAttrAccount] = key
        let update: [CFString: Any] = [kSecValueData: data]
        var status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            query[kSecValueData] = data
            query[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(query as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw SecureStoreError.keychain(status) }
    }

    public func remove(_ key: String) throws {
        var query = baseQuery()
        query[kSecAttrAccount] = key
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw SecureStoreError.keychain(status) }
    }

    public func keys() throws -> [String] {
        var query = baseQuery()
        query[kSecReturnAttributes] = true
        query[kSecMatchLimit] = kSecMatchLimitAll
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess else { throw SecureStoreError.keychain(status) }
        let items = result as? [[CFString: Any]] ?? []
        return items.compactMap { $0[kSecAttrAccount] as? String }.sorted()
    }
}

public final class MemoryStore: SecureStore, @unchecked Sendable {
    private var storage: [String: Data]
    private let lock = NSLock()

    public init(_ storage: [String: Data] = [:]) {
        self.storage = storage
    }

    public func data(for key: String) throws -> Data? {
        lock.withLock { storage[key] }
    }

    public func set(_ data: Data, for key: String) throws {
        lock.withLock { storage[key] = data }
    }

    public func remove(_ key: String) throws {
        lock.withLock { _ = storage.removeValue(forKey: key) }
    }

    public func keys() throws -> [String] {
        lock.withLock { storage.keys.sorted() }
    }
}

public struct PrivateKeyVault: Sendable {
    private let store: SecureStore
    private static let prefix = "certificate-key."

    public init(store: SecureStore) {
        self.store = store
    }

    public func save(_ keyPair: RSAKeyPair, certificateID: String) throws {
        try store.set(keyPair.privateKeyPKCS1, for: Self.prefix + certificateID)
    }

    public func keyPair(certificateID: String) throws -> RSAKeyPair? {
        guard let data = try store.data(for: Self.prefix + certificateID) else { return nil }
        return try RSAKeyPair(privateKeyPKCS1: data)
    }

    public func remove(certificateID: String) throws {
        try store.remove(Self.prefix + certificateID)
    }

    public func certificateIDs() throws -> Set<String> {
        Set(try store.keys().filter { $0.hasPrefix(Self.prefix) }.map { String($0.dropFirst(Self.prefix.count)) })
    }
}

public struct CredentialVault: Sendable {
    private let store: SecureStore
    private static let key = "api-credentials"

    public init(store: SecureStore) {
        self.store = store
    }

    public func all() throws -> [APICredentials] {
        guard let data = try store.data(for: Self.key) else { return [] }
        return try JSONDecoder().decode([APICredentials].self, from: data)
    }

    public func save(_ credentials: [APICredentials]) throws {
        try store.set(try JSONEncoder().encode(credentials), for: Self.key)
    }

    public func upsert(_ credential: APICredentials) throws {
        var current = try all().filter { $0.keyID != credential.keyID }
        current.append(credential)
        try save(current)
    }

    public func remove(keyID: String) throws {
        try save(try all().filter { $0.keyID != keyID })
    }
}
