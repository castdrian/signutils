import CommonCrypto
import CryptoKit
import Foundation

public struct PKCS12 {
    public static let defaultIterations = 2048

    public let der: Data

    public init(
        certificateDER: Data,
        privateKeyPKCS8: Data,
        password: String,
        friendlyName: String,
        iterations: Int = PKCS12.defaultIterations
    ) throws {
        let localKeyID = Data(Insecure.SHA1.hash(data: certificateDER))
        let attributes = Self.bagAttributes(localKeyID: localKeyID, friendlyName: friendlyName)
        let certificateSafe = try Self.encryptedCertificateSafe(
            certificateDER: certificateDER, attributes: attributes, password: password, iterations: iterations)
        let keySafe = try Self.shroudedKeySafe(
            privateKeyPKCS8: privateKeyPKCS8, attributes: attributes, password: password, iterations: iterations)
        let authenticatedSafe = DER.sequence([certificateSafe, keySafe])
        let macSalt = Self.randomBytes(8)
        let macKey = PKCS12KeyDerivation.derive(
            password: password, salt: macSalt, id: .mac, iterations: iterations, length: 20)
        let mac = Data(HMAC<Insecure.SHA1>.authenticationCode(for: authenticatedSafe, using: SymmetricKey(data: macKey)))
        der = DER.sequence([
            DER.integer(3),
            DER.sequence([
                DER.objectIdentifier(OID.data),
                DER.explicit(0, DER.octetString(authenticatedSafe)),
            ]),
            DER.sequence([
                DER.sequence([DER.algorithm(OID.sha1), DER.octetString(mac)]),
                DER.octetString(macSalt),
                DER.integer(iterations),
            ]),
        ])
    }

    private static func bagAttributes(localKeyID: Data, friendlyName: String) -> Data {
        DER.set([
            DER.sequence([DER.objectIdentifier(OID.friendlyName), DER.set([DER.bmpString(friendlyName)])]),
            DER.sequence([DER.objectIdentifier(OID.localKeyID), DER.set([DER.octetString(localKeyID)])]),
        ])
    }

    private static func encryptedCertificateSafe(
        certificateDER: Data, attributes: Data, password: String, iterations: Int
    ) throws -> Data {
        let certificateBag = DER.sequence([
            DER.objectIdentifier(OID.certBag),
            DER.explicit(
                0,
                DER.sequence([
                    DER.objectIdentifier(OID.x509Certificate),
                    DER.explicit(0, DER.octetString(certificateDER)),
                ])),
            attributes,
        ])
        let safeContents = DER.sequence([certificateBag])
        let salt = randomBytes(8)
        let encrypted = try TripleDES.encrypt(safeContents, password: password, salt: salt, iterations: iterations)
        let encryptedData = DER.sequence([
            DER.integer(0),
            DER.sequence([
                DER.objectIdentifier(OID.data),
                pbeAlgorithm(salt: salt, iterations: iterations),
                DER.implicitPrimitive(0, encrypted),
            ]),
        ])
        return DER.sequence([
            DER.objectIdentifier(OID.encryptedData),
            DER.explicit(0, encryptedData),
        ])
    }

    private static func shroudedKeySafe(
        privateKeyPKCS8: Data, attributes: Data, password: String, iterations: Int
    ) throws -> Data {
        let salt = randomBytes(8)
        let encrypted = try TripleDES.encrypt(privateKeyPKCS8, password: password, salt: salt, iterations: iterations)
        let keyBag = DER.sequence([
            DER.objectIdentifier(OID.pkcs8ShroudedKeyBag),
            DER.explicit(
                0,
                DER.sequence([
                    pbeAlgorithm(salt: salt, iterations: iterations),
                    DER.octetString(encrypted),
                ])),
            attributes,
        ])
        return DER.sequence([
            DER.objectIdentifier(OID.data),
            DER.explicit(0, DER.octetString(DER.sequence([keyBag]))),
        ])
    }

    private static func pbeAlgorithm(salt: Data, iterations: Int) -> Data {
        DER.sequence([
            DER.objectIdentifier(OID.pbeWithSHAAnd3KeyTripleDESCBC),
            DER.sequence([DER.octetString(salt), DER.integer(iterations)]),
        ])
    }

    static func randomBytes(_ count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return Data(bytes)
    }
}

enum TripleDES {
    static func encrypt(_ plaintext: Data, password: String, salt: Data, iterations: Int) throws -> Data {
        let key = PKCS12KeyDerivation.derive(password: password, salt: salt, id: .key, iterations: iterations, length: 24)
        let iv = PKCS12KeyDerivation.derive(password: password, salt: salt, id: .iv, iterations: iterations, length: 8)
        return try crypt(CCOperation(kCCEncrypt), plaintext, key: key, iv: iv)
    }

    static func decrypt(_ ciphertext: Data, password: String, salt: Data, iterations: Int) throws -> Data {
        let key = PKCS12KeyDerivation.derive(password: password, salt: salt, id: .key, iterations: iterations, length: 24)
        let iv = PKCS12KeyDerivation.derive(password: password, salt: salt, id: .iv, iterations: iterations, length: 8)
        return try crypt(CCOperation(kCCDecrypt), ciphertext, key: key, iv: iv)
    }

    private static func crypt(_ operation: CCOperation, _ input: Data, key: Data, iv: Data) throws -> Data {
        var output = Data(count: input.count + kCCBlockSize3DES)
        let capacity = output.count
        var moved = 0
        let status = output.withUnsafeMutableBytes { outputBytes in
            input.withUnsafeBytes { inputBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            operation, CCAlgorithm(kCCAlgorithm3DES), CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress, key.count, ivBytes.baseAddress,
                            inputBytes.baseAddress, input.count,
                            outputBytes.baseAddress, capacity, &moved)
                    }
                }
            }
        }
        guard status == kCCSuccess else { throw CryptoError.encryptionFailed(status) }
        return output.prefix(moved)
    }
}

public enum PKCS12KeyDerivation {
    public enum Purpose: UInt8 {
        case key = 1
        case iv = 2
        case mac = 3
    }

    private static let blockSize = 64
    private static let hashSize = 20

    public static func derive(password: String, salt: Data, id: Purpose, iterations: Int, length: Int) -> Data {
        var passwordBytes = Data()
        for unit in password.utf16 {
            passwordBytes.append(UInt8(unit >> 8))
            passwordBytes.append(UInt8(unit & 0xFF))
        }
        passwordBytes.append(contentsOf: [0, 0])
        let diversifier = Data(repeating: id.rawValue, count: blockSize)
        var input = repeated(salt) + repeated(passwordBytes)
        var output = Data()
        while output.count < length {
            var digest = diversifier + input
            for _ in 0..<iterations {
                digest = Data(Insecure.SHA1.hash(data: digest))
            }
            output.append(digest)
            guard output.count < length else { break }
            let filler = repeated(digest, to: blockSize)
            input = adjust(input, adding: filler)
        }
        return output.prefix(length)
    }

    private static func repeated(_ data: Data) -> Data {
        guard !data.isEmpty else { return Data() }
        let target = blockSize * ((data.count + blockSize - 1) / blockSize)
        return repeated(data, to: target)
    }

    private static func repeated(_ data: Data, to count: Int) -> Data {
        var output = Data(capacity: count)
        while output.count < count {
            output.append(data.prefix(count - output.count))
        }
        return output
    }

    private static func adjust(_ input: Data, adding filler: Data) -> Data {
        var bytes = [UInt8](input)
        let fillerBytes = [UInt8](filler)
        for blockStart in stride(from: 0, to: bytes.count, by: blockSize) {
            var carry = 1
            for index in stride(from: blockSize - 1, through: 0, by: -1) {
                let sum = Int(bytes[blockStart + index]) + Int(fillerBytes[index]) + carry
                bytes[blockStart + index] = UInt8(sum & 0xFF)
                carry = sum >> 8
            }
        }
        return Data(bytes)
    }
}
