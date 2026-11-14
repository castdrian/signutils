import CryptoKit
import Foundation

public struct CertificateInfo: Sendable, Equatable {
    public let commonName: String
    public let organizationalUnit: String?
    public let serialNumber: String
    public let notBefore: Date
    public let notAfter: Date
    public let sha1Fingerprint: String

    public init(der: Data) throws {
        let certificate = try DERNode.parse(der)
        let parts = try certificate.children()
        guard let tbs = parts.first else { throw CryptoError.invalidCertificate }
        var fields = try tbs.children()
        if fields.first?.tag == 0xA0 {
            fields.removeFirst()
        }
        guard fields.count >= 6 else { throw CryptoError.invalidCertificate }
        serialNumber = fields[0].content.map { String(format: "%02X", $0) }.joined()
        let validity = try fields[3].children()
        guard validity.count == 2, let start = Self.date(validity[0]), let end = Self.date(validity[1]) else {
            throw CryptoError.invalidCertificate
        }
        notBefore = start
        notAfter = end
        let subject = try Self.attributes(fields[4])
        commonName = subject[OID.commonName] ?? ""
        organizationalUnit = subject[OID.organizationalUnitName]
        sha1Fingerprint = Insecure.SHA1.hash(data: der).map { String(format: "%02X", $0) }.joined()
    }

    private static func attributes(_ name: DERNode) throws -> [String: String] {
        var result: [String: String] = [:]
        for relativeName in try name.children() {
            for pair in try relativeName.children() {
                let items = try pair.children()
                guard items.count == 2, let oid = items[0].objectIdentifier, let value = items[1].stringValue else {
                    continue
                }
                result[oid] = value
            }
        }
        return result
    }

    private static func date(_ node: DERNode) -> Date? {
        guard let text = String(data: node.content, encoding: .ascii) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = node.tag == 0x17 ? "yyMMddHHmmss'Z'" : "yyyyMMddHHmmss'Z'"
        return formatter.date(from: text)
    }
}
