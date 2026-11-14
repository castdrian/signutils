import Foundation
import Security

public enum CryptoError: Error, LocalizedError, Equatable {
    case keyGenerationFailed(String)
    case keyExportFailed(String)
    case keyImportFailed(String)
    case signingFailed(String)
    case encryptionFailed(Int32)
    case invalidCertificate
    case invalidPrivateKey
    case invalidPEM

    public var errorDescription: String? {
        switch self {
        case .keyGenerationFailed(let reason): "Could not generate a private key: \(reason)"
        case .keyExportFailed(let reason): "Could not export the private key: \(reason)"
        case .keyImportFailed(let reason): "Could not read the private key: \(reason)"
        case .signingFailed(let reason): "Could not sign the certificate request: \(reason)"
        case .encryptionFailed(let status): "Could not encrypt the PKCS#12 container (\(status))"
        case .invalidCertificate: "The certificate returned by Apple could not be read"
        case .invalidPrivateKey: "The private key is not a valid RSA key"
        case .invalidPEM: "The key is not valid PEM"
        }
    }
}

public struct RSAKeyPair: Sendable {
    public let privateKeyPKCS1: Data
    public let publicKeyPKCS1: Data

    public static func generate(bits: Int = 2048) throws -> RSAKeyPair {
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits: bits,
            kSecAttrIsPermanent: false,
        ]
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw CryptoError.keyGenerationFailed(Self.describe(error))
        }
        return try RSAKeyPair(secKey: privateKey)
    }

    public init(privateKeyPKCS1: Data) throws {
        let key = try Self.makePrivateKey(privateKeyPKCS1)
        try self.init(secKey: key)
    }

    private init(secKey: SecKey) throws {
        var error: Unmanaged<CFError>?
        guard let privateData = SecKeyCopyExternalRepresentation(secKey, &error) as Data? else {
            throw CryptoError.keyExportFailed(Self.describe(error))
        }
        guard let publicKey = SecKeyCopyPublicKey(secKey),
            let publicData = SecKeyCopyExternalRepresentation(publicKey, &error) as Data?
        else {
            throw CryptoError.keyExportFailed(Self.describe(error))
        }
        self.privateKeyPKCS1 = privateData
        self.publicKeyPKCS1 = publicData
    }

    public var privateKeyPKCS8: Data {
        DER.sequence([
            DER.integer(0),
            DER.algorithm(OID.rsaEncryption),
            DER.octetString(privateKeyPKCS1),
        ])
    }

    public var subjectPublicKeyInfo: Data {
        DER.sequence([
            DER.algorithm(OID.rsaEncryption),
            DER.bitString(publicKeyPKCS1),
        ])
    }

    public var privateKeyPEM: String {
        PEM.encode(privateKeyPKCS8, label: "PRIVATE KEY")
    }

    public func sign(_ message: Data) throws -> Data {
        let key = try Self.makePrivateKey(privateKeyPKCS1)
        var error: Unmanaged<CFError>?
        guard
            let signature = SecKeyCreateSignature(
                key, .rsaSignatureMessagePKCS1v15SHA256, message as CFData, &error) as Data?
        else {
            throw CryptoError.signingFailed(Self.describe(error))
        }
        return signature
    }

    public func matches(certificateDER: Data) -> Bool {
        guard let certificate = SecCertificateCreateWithData(nil, certificateDER as CFData),
            let publicKey = SecCertificateCopyKey(certificate),
            let data = SecKeyCopyExternalRepresentation(publicKey, nil) as Data?
        else { return false }
        return data == publicKeyPKCS1
    }

    private static func makePrivateKey(_ pkcs1: Data) throws -> SecKey {
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPrivate,
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(pkcs1 as CFData, attributes as CFDictionary, &error) else {
            throw CryptoError.keyImportFailed(describe(error))
        }
        return key
    }

    private static func describe(_ error: Unmanaged<CFError>?) -> String {
        guard let error = error?.takeRetainedValue() else { return "unknown error" }
        return (error as Error).localizedDescription
    }
}

public enum OID {
    public static let rsaEncryption = "1.2.840.113549.1.1.1"
    public static let sha256WithRSAEncryption = "1.2.840.113549.1.1.11"
    public static let commonName = "2.5.4.3"
    public static let organizationName = "2.5.4.10"
    public static let countryName = "2.5.4.6"
    public static let emailAddress = "1.2.840.113549.1.9.1"
    public static let data = "1.2.840.113549.1.7.1"
    public static let encryptedData = "1.2.840.113549.1.7.6"
    public static let pkcs8ShroudedKeyBag = "1.2.840.113549.1.12.10.1.2"
    public static let certBag = "1.2.840.113549.1.12.10.1.3"
    public static let x509Certificate = "1.2.840.113549.1.9.22.1"
    public static let friendlyName = "1.2.840.113549.1.9.20"
    public static let localKeyID = "1.2.840.113549.1.9.21"
    public static let pbeWithSHAAnd3KeyTripleDESCBC = "1.2.840.113549.1.12.1.3"
    public static let sha1 = "1.3.14.3.2.26"
    public static let userID = "0.9.2342.19200300.100.1.1"
    public static let organizationalUnitName = "2.5.4.11"
}

public enum PEM {
    public static func encode(_ der: Data, label: String) -> String {
        let body = der.base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed])
        return "-----BEGIN \(label)-----\n\(body)\n-----END \(label)-----\n"
    }

    public static func decode(_ pem: String) throws -> Data {
        let body = pem
            .split(whereSeparator: \.isNewline)
            .filter { !$0.hasPrefix("-----") }
            .joined()
            .trimmingCharacters(in: .whitespaces)
        guard let data = Data(base64Encoded: body), !data.isEmpty else { throw CryptoError.invalidPEM }
        return data
    }
}
