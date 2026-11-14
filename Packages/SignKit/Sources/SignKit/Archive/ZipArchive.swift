import Foundation

public struct ZipEntry: Sendable, Equatable {
    public var path: String
    public var data: Data
    public var modified: Date

    public init(path: String, data: Data, modified: Date = Date()) {
        self.path = path
        self.data = data
        self.modified = modified
    }
}

public enum ZipError: Error, Equatable {
    case notAZipArchive
    case unsupportedCompression(UInt16)
    case corrupted(String)
}

public enum ZipArchive {
    public static func make(_ entries: [ZipEntry]) throws -> Data {
        var archive = Data()
        var central = Data()
        for entry in entries {
            let offset = UInt32(archive.count)
            let name = Data(entry.path.utf8)
            let checksum = CRC32.checksum(entry.data)
            let deflated = (try? (entry.data as NSData).compressed(using: .zlib) as Data) ?? entry.data
            let useDeflate = deflated.count < entry.data.count
            let payload = useDeflate ? deflated : entry.data
            let method: UInt16 = useDeflate ? 8 : 0
            let (time, date) = dosTimestamp(entry.modified)

            var local = Data()
            local.appendLE(UInt32(0x0403_4B50))
            local.appendLE(UInt16(20))
            local.appendLE(UInt16(0x0800))
            local.appendLE(method)
            local.appendLE(time)
            local.appendLE(date)
            local.appendLE(checksum)
            local.appendLE(UInt32(payload.count))
            local.appendLE(UInt32(entry.data.count))
            local.appendLE(UInt16(name.count))
            local.appendLE(UInt16(0))
            local.append(name)
            archive.append(local)
            archive.append(payload)

            central.appendLE(UInt32(0x0201_4B50))
            central.appendLE(UInt16(0x031E))
            central.appendLE(UInt16(20))
            central.appendLE(UInt16(0x0800))
            central.appendLE(method)
            central.appendLE(time)
            central.appendLE(date)
            central.appendLE(checksum)
            central.appendLE(UInt32(payload.count))
            central.appendLE(UInt32(entry.data.count))
            central.appendLE(UInt16(name.count))
            central.appendLE(UInt16(0))
            central.appendLE(UInt16(0))
            central.appendLE(UInt16(0))
            central.appendLE(UInt16(0))
            central.appendLE(UInt32(0o100644) << 16)
            central.appendLE(offset)
            central.append(name)
        }
        let centralOffset = UInt32(archive.count)
        archive.append(central)
        archive.appendLE(UInt32(0x0605_4B50))
        archive.appendLE(UInt16(0))
        archive.appendLE(UInt16(0))
        archive.appendLE(UInt16(entries.count))
        archive.appendLE(UInt16(entries.count))
        archive.appendLE(UInt32(central.count))
        archive.appendLE(centralOffset)
        archive.appendLE(UInt16(0))
        return archive
    }

    public static func read(_ archive: Data) throws -> [ZipEntry] {
        let bytes = [UInt8](archive)
        guard bytes.count >= 22 else { throw ZipError.notAZipArchive }
        var endIndex: Int?
        for index in stride(from: bytes.count - 22, through: max(0, bytes.count - 65_557), by: -1)
        where bytes.readLE32(index) == 0x0605_4B50 {
            endIndex = index
            break
        }
        guard let endIndex else { throw ZipError.notAZipArchive }
        let count = Int(bytes.readLE16(endIndex + 10))
        var cursor = Int(bytes.readLE32(endIndex + 16))
        var entries: [ZipEntry] = []
        for _ in 0..<count {
            guard cursor + 46 <= bytes.count, bytes.readLE32(cursor) == 0x0201_4B50 else {
                throw ZipError.corrupted("central directory")
            }
            let method = bytes.readLE16(cursor + 10)
            let time = bytes.readLE16(cursor + 12)
            let date = bytes.readLE16(cursor + 14)
            let compressedSize = Int(bytes.readLE32(cursor + 20))
            let size = Int(bytes.readLE32(cursor + 24))
            let nameLength = Int(bytes.readLE16(cursor + 28))
            let extraLength = Int(bytes.readLE16(cursor + 30))
            let commentLength = Int(bytes.readLE16(cursor + 32))
            let localOffset = Int(bytes.readLE32(cursor + 42))
            let name = String(decoding: bytes[(cursor + 46)..<(cursor + 46 + nameLength)], as: UTF8.self)
            cursor += 46 + nameLength + extraLength + commentLength

            guard localOffset + 30 <= bytes.count, bytes.readLE32(localOffset) == 0x0403_4B50 else {
                throw ZipError.corrupted("local header for \(name)")
            }
            let start = localOffset + 30 + Int(bytes.readLE16(localOffset + 26)) + Int(bytes.readLE16(localOffset + 28))
            guard start + compressedSize <= bytes.count else { throw ZipError.corrupted("data for \(name)") }
            let payload = Data(bytes[start..<(start + compressedSize)])
            let data: Data
            switch method {
            case 0:
                data = payload
            case 8:
                data = size == 0 ? Data() : try (payload as NSData).decompressed(using: .zlib) as Data
            default:
                throw ZipError.unsupportedCompression(method)
            }
            if name.hasSuffix("/") { continue }
            entries.append(ZipEntry(path: name, data: data, modified: fromDOS(time: time, date: date)))
        }
        return entries
    }

    private static func dosTimestamp(_ date: Date) -> (UInt16, UInt16) {
        let components = Calendar(identifier: .gregorian).dateComponents(
            in: TimeZone.current, from: date)
        let year = max(1980, components.year ?? 1980)
        let time = UInt16((components.hour ?? 0) << 11 | (components.minute ?? 0) << 5 | (components.second ?? 0) / 2)
        let day = UInt16((year - 1980) << 9 | (components.month ?? 1) << 5 | (components.day ?? 1))
        return (time, day)
    }

    private static func fromDOS(time: UInt16, date: UInt16) -> Date {
        var components = DateComponents()
        components.year = Int(date >> 9) + 1980
        components.month = Int((date >> 5) & 0x0F)
        components.day = Int(date & 0x1F)
        components.hour = Int(time >> 11)
        components.minute = Int((time >> 5) & 0x3F)
        components.second = Int(time & 0x1F) * 2
        return Calendar(identifier: .gregorian).date(from: components) ?? Date(timeIntervalSince1970: 0)
    }
}

enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { index in
        var value = UInt32(index)
        for _ in 0..<8 {
            value = value & 1 == 1 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1
        }
        return value
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }
}

extension Data {
    fileprivate mutating func appendLE(_ value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8(value >> 8))
    }

    fileprivate mutating func appendLE(_ value: UInt32) {
        for shift in stride(from: 0, to: 32, by: 8) {
            append(UInt8((value >> UInt32(shift)) & 0xFF))
        }
    }
}

extension Array where Element == UInt8 {
    fileprivate func readLE16(_ offset: Int) -> UInt16 {
        UInt16(self[offset]) | UInt16(self[offset + 1]) << 8
    }

    fileprivate func readLE32(_ offset: Int) -> UInt32 {
        UInt32(self[offset]) | UInt32(self[offset + 1]) << 8 | UInt32(self[offset + 2]) << 16
            | UInt32(self[offset + 3]) << 24
    }
}
