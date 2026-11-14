import Foundation

public struct LibraryEntry: Codable, Sendable, Hashable, Identifiable {
    public enum Status: String, Codable, Sendable {
        case active
        case expired
        case certificateRevoked
        case profileDeleted
        case profileInvalid
        case revoked
    }

    public var bundle: SigningBundle
    public var status: Status
    public var checkedAt: Date?

    public var id: UUID { bundle.id }

    public init(bundle: SigningBundle, status: Status = .active, checkedAt: Date? = nil) {
        self.bundle = bundle
        self.status = status
        self.checkedAt = checkedAt
    }

    public func effectiveStatus(now: Date = Date()) -> Status {
        if status == .active, bundle.expiration < now { return .expired }
        return status
    }
}

public final class SigningLibrary: @unchecked Sendable {
    public let directory: URL
    private let lock = NSLock()
    private let indexURL: URL

    public init(directory: URL) throws {
        self.directory = directory
        self.indexURL = directory.appendingPathComponent("library.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("SignUtils/Library", isDirectory: true)
    }

    public func entries() throws -> [LibraryEntry] {
        try lock.withLock { try readIndex() }.sorted { $0.bundle.createdAt > $1.bundle.createdAt }
    }

    @discardableResult
    public func add(_ artifacts: SigningArtifacts) throws -> LibraryEntry {
        try lock.withLock {
            let url = directory.appendingPathComponent(artifacts.bundle.fileName)
            try artifacts.archive.write(to: url, options: [.atomic, .completeFileProtection])
            var entries = try readIndex()
            let entry = LibraryEntry(bundle: artifacts.bundle)
            entries.removeAll { $0.id == entry.id }
            entries.append(entry)
            try writeIndex(entries)
            return entry
        }
    }

    public func update(_ entry: LibraryEntry) throws {
        try lock.withLock {
            var entries = try readIndex()
            guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
            entries[index] = entry
            try writeIndex(entries)
        }
    }

    public func updateStatuses(_ change: (LibraryEntry) -> LibraryEntry.Status?) throws -> [LibraryEntry] {
        try lock.withLock {
            var entries = try readIndex()
            let now = Date()
            for index in entries.indices {
                if let status = change(entries[index]) {
                    entries[index].status = status
                }
                entries[index].checkedAt = now
            }
            try writeIndex(entries)
            return entries.sorted { $0.bundle.createdAt > $1.bundle.createdAt }
        }
    }

    public func remove(id: UUID) throws {
        try lock.withLock {
            var entries = try readIndex()
            if let entry = entries.first(where: { $0.id == id }) {
                try? FileManager.default.removeItem(at: directory.appendingPathComponent(entry.bundle.fileName))
            }
            entries.removeAll { $0.id == id }
            try writeIndex(entries)
        }
    }

    public func archiveURL(for entry: LibraryEntry) -> URL {
        directory.appendingPathComponent(entry.bundle.fileName)
    }

    public func contents(of entry: LibraryEntry) throws -> [ZipEntry] {
        try ZipArchive.read(Data(contentsOf: archiveURL(for: entry)))
    }

    private func readIndex() throws -> [LibraryEntry] {
        guard FileManager.default.fileExists(atPath: indexURL.path) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([LibraryEntry].self, from: Data(contentsOf: indexURL))
    }

    private func writeIndex(_ entries: [LibraryEntry]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(entries).write(to: indexURL, options: [.atomic, .completeFileProtection])
    }
}
