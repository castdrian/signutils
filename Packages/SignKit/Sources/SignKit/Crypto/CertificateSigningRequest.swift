import Foundation

public struct CertificateSigningRequest: Sendable {
    public let der: Data

    public init(keyPair: RSAKeyPair, commonName: String, emailAddress: String? = nil, countryCode: String? = nil) throws {
        let info = DER.sequence([
            DER.integer(0),
            Self.name(commonName: commonName, emailAddress: emailAddress, countryCode: countryCode),
            keyPair.subjectPublicKeyInfo,
            DER.explicit(0, Data()),
        ])
        let signature = try keyPair.sign(info)
        der = DER.sequence([
            info,
            DER.algorithm(OID.sha256WithRSAEncryption),
            DER.bitString(signature),
        ])
    }

    public var pem: String {
        PEM.encode(der, label: "CERTIFICATE REQUEST")
    }

    private static func name(commonName: String, emailAddress: String?, countryCode: String?) -> Data {
        var relativeNames: [Data] = []
        if let countryCode, countryCode.count == 2 {
            relativeNames.append(attribute(OID.countryName, DER.printableString(countryCode.uppercased())))
        }
        relativeNames.append(attribute(OID.commonName, DER.utf8String(commonName)))
        if let emailAddress, !emailAddress.isEmpty {
            relativeNames.append(attribute(OID.emailAddress, DER.ia5String(emailAddress)))
        }
        return DER.sequence(relativeNames)
    }

    private static func attribute(_ oid: String, _ value: Data) -> Data {
        DER.set([DER.sequence([DER.objectIdentifier(oid), value])])
    }
}
