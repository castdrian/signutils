import Foundation

public enum DER {
    public enum Tag: UInt8 {
        case boolean = 0x01
        case integer = 0x02
        case bitString = 0x03
        case octetString = 0x04
        case null = 0x05
        case objectIdentifier = 0x06
        case utf8String = 0x0C
        case printableString = 0x13
        case ia5String = 0x16
        case bmpString = 0x1E
        case sequence = 0x30
        case set = 0x31
    }

    public static func encode(tag: UInt8, content: Data) -> Data {
        var output = Data([tag])
        output.append(length(content.count))
        output.append(content)
        return output
    }

    public static func length(_ count: Int) -> Data {
        if count < 0x80 {
            return Data([UInt8(count)])
        }
        var bytes: [UInt8] = []
        var remaining = count
        while remaining > 0 {
            bytes.insert(UInt8(remaining & 0xFF), at: 0)
            remaining >>= 8
        }
        return Data([0x80 | UInt8(bytes.count)] + bytes)
    }

    public static func sequence(_ items: [Data]) -> Data {
        encode(tag: Tag.sequence.rawValue, content: items.reduce(Data(), +))
    }

    public static func set(_ items: [Data]) -> Data {
        let sorted = items.sorted { $0.lexicographicallyPrecedes($1) }
        return encode(tag: Tag.set.rawValue, content: sorted.reduce(Data(), +))
    }

    public static func integer(_ value: Int) -> Data {
        var bytes: [UInt8] = []
        var remaining = value
        repeat {
            bytes.insert(UInt8(remaining & 0xFF), at: 0)
            remaining >>= 8
        } while remaining > 0
        if let first = bytes.first, first & 0x80 != 0 {
            bytes.insert(0, at: 0)
        }
        return encode(tag: Tag.integer.rawValue, content: Data(bytes))
    }

    public static func unsignedInteger(_ magnitude: Data) -> Data {
        var bytes = Array(magnitude.drop { $0 == 0 })
        if bytes.isEmpty {
            bytes = [0]
        }
        if bytes[0] & 0x80 != 0 {
            bytes.insert(0, at: 0)
        }
        return encode(tag: Tag.integer.rawValue, content: Data(bytes))
    }

    public static func octetString(_ data: Data) -> Data {
        encode(tag: Tag.octetString.rawValue, content: data)
    }

    public static func bitString(_ data: Data) -> Data {
        encode(tag: Tag.bitString.rawValue, content: Data([0]) + data)
    }

    public static let null = Data([Tag.null.rawValue, 0x00])

    public static func utf8String(_ string: String) -> Data {
        encode(tag: Tag.utf8String.rawValue, content: Data(string.utf8))
    }

    public static func printableString(_ string: String) -> Data {
        encode(tag: Tag.printableString.rawValue, content: Data(string.utf8))
    }

    public static func ia5String(_ string: String) -> Data {
        encode(tag: Tag.ia5String.rawValue, content: Data(string.utf8))
    }

    public static func bmpString(_ string: String) -> Data {
        var content = Data()
        for unit in string.utf16 {
            content.append(UInt8(unit >> 8))
            content.append(UInt8(unit & 0xFF))
        }
        return encode(tag: Tag.bmpString.rawValue, content: content)
    }

    public static func explicit(_ number: UInt8, _ content: Data) -> Data {
        encode(tag: 0xA0 | number, content: content)
    }

    public static func implicitPrimitive(_ number: UInt8, _ content: Data) -> Data {
        encode(tag: 0x80 | number, content: content)
    }

    public static func objectIdentifier(_ dotted: String) -> Data {
        let arcs = dotted.split(separator: ".").compactMap { UInt64($0) }
        precondition(arcs.count >= 2, "Invalid object identifier \(dotted)")
        var content = Data([UInt8(arcs[0] * 40 + arcs[1])])
        for arc in arcs.dropFirst(2) {
            content.append(base128(arc))
        }
        return encode(tag: Tag.objectIdentifier.rawValue, content: content)
    }

    private static func base128(_ value: UInt64) -> Data {
        var bytes: [UInt8] = [UInt8(value & 0x7F)]
        var remaining = value >> 7
        while remaining > 0 {
            bytes.insert(UInt8(remaining & 0x7F) | 0x80, at: 0)
            remaining >>= 7
        }
        return Data(bytes)
    }

    public static func algorithm(_ oid: String, parameters: Data? = DER.null) -> Data {
        sequence([objectIdentifier(oid)] + (parameters.map { [$0] } ?? []))
    }
}

public struct DERNode: Sendable {
    public let tag: UInt8
    public let content: Data
    public let encoded: Data

    public var isConstructed: Bool { tag & 0x20 != 0 }

    public func children() throws -> [DERNode] {
        try DERNode.parseAll(content)
    }

    public static func parse(_ data: Data) throws -> DERNode {
        var reader = DERReader(data: data)
        return try reader.next()
    }

    public static func parseAll(_ data: Data) throws -> [DERNode] {
        var reader = DERReader(data: data)
        var nodes: [DERNode] = []
        while !reader.isAtEnd {
            nodes.append(try reader.next())
        }
        return nodes
    }

    public var objectIdentifier: String? {
        guard tag == DER.Tag.objectIdentifier.rawValue, let first = content.first else { return nil }
        var arcs = [UInt64(first / 40), UInt64(first % 40)]
        var value: UInt64 = 0
        for byte in content.dropFirst() {
            value = (value << 7) | UInt64(byte & 0x7F)
            if byte & 0x80 == 0 {
                arcs.append(value)
                value = 0
            }
        }
        return arcs.map(String.init).joined(separator: ".")
    }

    public var integerValue: Int? {
        guard tag == DER.Tag.integer.rawValue, content.count <= 8 else { return nil }
        return content.reduce(0) { ($0 << 8) | Int($1) }
    }

    public var stringValue: String? {
        switch tag {
        case DER.Tag.utf8String.rawValue, DER.Tag.printableString.rawValue, DER.Tag.ia5String.rawValue, 0x14:
            return String(data: content, encoding: .utf8)
        case DER.Tag.bmpString.rawValue:
            return String(data: content, encoding: .utf16BigEndian)
        default:
            return nil
        }
    }
}

public enum DERError: Error, Equatable {
    case truncated
    case unsupportedLength
}

struct DERReader {
    let data: Data
    var offset: Int

    init(data: Data) {
        self.data = Data(data)
        self.offset = 0
    }

    var isAtEnd: Bool { offset >= data.count }

    mutating func next() throws -> DERNode {
        let start = offset
        let tag = try byte()
        let first = try byte()
        var length = 0
        if first & 0x80 == 0 {
            length = Int(first)
        } else {
            let count = Int(first & 0x7F)
            guard count > 0, count <= 4 else { throw DERError.unsupportedLength }
            for _ in 0..<count {
                length = (length << 8) | Int(try byte())
            }
        }
        guard offset + length <= data.count else { throw DERError.truncated }
        let content = data.subdata(in: offset..<(offset + length))
        offset += length
        return DERNode(tag: tag, content: content, encoded: data.subdata(in: start..<offset))
    }

    private mutating func byte() throws -> UInt8 {
        guard offset < data.count else { throw DERError.truncated }
        defer { offset += 1 }
        return data[offset]
    }
}
