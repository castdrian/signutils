import CryptoKit
import Foundation
import Testing

@testable import SignKit

@Suite("DER")
struct DERTests {
    @Test func objectIdentifierRoundTrips() throws {
        for oid in [OID.rsaEncryption, OID.pkcs8ShroudedKeyBag, OID.sha1, OID.userID, "2.5.4.3"] {
            let node = try DERNode.parse(DER.objectIdentifier(oid))
            #expect(node.objectIdentifier == oid)
        }
    }

    @Test func longLengthsUseMultipleBytes() throws {
        let content = Data(repeating: 7, count: 300)
        let encoded = DER.octetString(content)
        #expect(Array(encoded.prefix(4)) == [0x04, 0x82, 0x01, 0x2C])
        #expect(try DERNode.parse(encoded).content == content)
    }

    @Test func integersAreMinimalAndPositive() throws {
        #expect(DER.integer(0) == Data([0x02, 0x01, 0x00]))
        #expect(DER.integer(128) == Data([0x02, 0x02, 0x00, 0x80]))
        #expect(DER.integer(2048) == Data([0x02, 0x02, 0x08, 0x00]))
        #expect(try DERNode.parse(DER.integer(65537)).integerValue == 65537)
    }

    @Test func setsAreSortedForDER() {
        let first = DER.octetString(Data([2]))
        let second = DER.octetString(Data([1]))
        #expect(DER.set([first, second]) == DER.encode(tag: 0x31, content: second + first))
    }

    @Test func truncatedInputThrows() {
        #expect(throws: DERError.truncated) { try DERNode.parse(Data([0x30, 0x05, 0x01])) }
    }
}

@Suite("PKCS#12 key derivation")
struct PKCS12KeyDerivationTests {
    @Test func matchesPublishedVectors() {
        let salt = Data([0x0A, 0x58, 0xCF, 0x64, 0x53, 0x0D, 0x82, 0x3F])
        let key = PKCS12KeyDerivation.derive(password: "smeg", salt: salt, id: .key, iterations: 1, length: 24)
        #expect(key.hex == "8AAAE6297B6CB04642AB5B077851284EB7128F1A2A7FBCA3")
        let iv = PKCS12KeyDerivation.derive(password: "smeg", salt: salt, id: .iv, iterations: 1, length: 8)
        #expect(iv.hex == "79993DFE048D3B76")
    }

    @Test func matchesPublishedVectorsWithManyIterations() {
        let salt = Data([0x16, 0x82, 0xC0, 0xFC, 0x5B, 0x3F, 0x7E, 0xC5])
        let key = PKCS12KeyDerivation.derive(password: "queeg", salt: salt, id: .key, iterations: 1000, length: 24)
        #expect(key.hex == "483DD6E919D7DE2E8E648BA8F862F3FBFBDC2BCB2C02957F")
    }
}

@Suite("Keys, CSR and PKCS#12")
struct CertificateTests {
    @Test func csrVerifiesWithOpenSSL() throws {
        let keyPair = try RSAKeyPair.generate()
        let csr = try CertificateSigningRequest(keyPair: keyPair, commonName: "SignUtils Test", emailAddress: "a@b.c")
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("request.pem")
        try csr.pem.write(to: url, atomically: true, encoding: .utf8)
        let result = try run(openssl(), ["req", "-in", url.path, "-verify", "-noout", "-subject"])
        #expect(result.status == 0, "\(result.output)")
        #expect(result.output.contains("SignUtils Test"))
        #expect(result.output.lowercased().contains("verify ok") || result.output.contains("verification OK"))
    }

    @Test func privateKeyRoundTripsThroughPKCS1() throws {
        let keyPair = try RSAKeyPair.generate()
        let restored = try RSAKeyPair(privateKeyPKCS1: keyPair.privateKeyPKCS1)
        #expect(restored.publicKeyPKCS1 == keyPair.publicKeyPKCS1)
    }

    @Test func certificateInfoReadsSelfSignedCertificate() throws {
        let keyPair = try RSAKeyPair.generate()
        let der = try selfSignedCertificate(for: keyPair, commonName: "Apple Development: Test")
        let info = try CertificateInfo(der: der)
        #expect(info.commonName == "Apple Development: Test")
        #expect(info.organizationalUnit == "TEAMID1234")
        #expect(info.notAfter > info.notBefore)
        #expect(info.sha1Fingerprint.count == 40)
        #expect(keyPair.matches(certificateDER: der))
        #expect(try !RSAKeyPair.generate().matches(certificateDER: der))
    }

    @Test(arguments: ["s3cret-Passw0rd", "", "with spaces & symbols !@#$%^*()"])
    func pkcs12OpensWithOpenSSL(password: String) throws {
        let keyPair = try RSAKeyPair.generate()
        let certificate = try selfSignedCertificate(for: keyPair)
        let p12 = try PKCS12(
            certificateDER: certificate, privateKeyPKCS8: keyPair.privateKeyPKCS8, password: password,
            friendlyName: "SignKit Test")
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("bundle.p12")
        try p12.der.write(to: url)
        let dump = try run(openssl(), ["pkcs12", "-in", url.path, "-nodes", "-passin", "pass:\(password)"])
        #expect(dump.status == 0, "\(dump.output)")
        #expect(dump.output.contains("BEGIN CERTIFICATE"))
        #expect(dump.output.contains("BEGIN PRIVATE KEY"))
        #expect(dump.output.contains("friendlyName: SignKit Test"))

        let keyURL = directory.appendingPathComponent("extracted.pem")
        try dump.output.write(to: keyURL, atomically: true, encoding: .utf8)
        let keyModulus = try run(openssl(), ["rsa", "-in", keyURL.path, "-noout", "-modulus"])
        let certModulus = try run(openssl(), ["x509", "-in", keyURL.path, "-noout", "-modulus"])
        #expect(keyModulus.status == 0)
        #expect(keyModulus.output == certModulus.output)

        let wrong = try run(openssl(), ["pkcs12", "-in", url.path, "-nodes", "-passin", "pass:wrong\(password)"])
        #expect(wrong.status != 0)
    }

    @Test func pkcs12ImportsIntoAppleKeychain() throws {
        let keyPair = try RSAKeyPair.generate()
        let certificate = try selfSignedCertificate(for: keyPair, commonName: "SignKit Keychain Test")
        let password = Passwords.generate()
        let p12 = try PKCS12(
            certificateDER: certificate, privateKeyPKCS8: keyPair.privateKeyPKCS8, password: password,
            friendlyName: "SignKit Keychain Test")
        var items: CFArray?
        let status = SecPKCS12Import(p12.der as CFData, [kSecImportExportPassphrase: password] as CFDictionary, &items)
        #expect(status == errSecSuccess)
        let first = (items as? [[String: Any]])?.first
        #expect(first?[kSecImportItemIdentity as String] != nil)
        #expect(first?[kSecImportItemLabel as String] as? String == "SignKit Keychain Test")

        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let keychain = directory.appendingPathComponent("test.keychain-db").path
        let url = directory.appendingPathComponent("bundle.p12")
        try p12.der.write(to: url)
        #expect(try run("/usr/bin/security", ["create-keychain", "-p", "test", keychain]).status == 0)
        defer { _ = try? run("/usr/bin/security", ["delete-keychain", keychain]) }
        let imported = try run(
            "/usr/bin/security", ["import", url.path, "-k", keychain, "-f", "pkcs12", "-P", password, "-A"])
        #expect(imported.status == 0, "\(imported.output)")
        let identities = try run("/usr/bin/security", ["find-identity", keychain])
        #expect(identities.output.contains("SignKit Keychain Test"), "\(identities.output)")
    }
}

@Suite("JSON Web Token")
struct JSONWebTokenTests {
    @Test func teamTokensAreSignedAndScoped() throws {
        let key = P256.Signing.PrivateKey()
        let credentials = APICredentials(
            name: "Test", keyID: "ABCDE12345", issuerID: "69a6de70-0000-47e3-e053-5b8c7c11a4d1",
            privateKeyPEM: key.pemRepresentation)
        try credentials.validate()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let token = try JSONWebToken.make(credentials: credentials, now: now)
        let parts = token.split(separator: ".").map(String.init)
        #expect(parts.count == 3)
        let header = try decodeSegment(parts[0])
        let payload = try decodeSegment(parts[1])
        #expect(header["kid"] as? String == "ABCDE12345")
        #expect(header["alg"] as? String == "ES256")
        #expect(payload["iss"] as? String == credentials.issuerID)
        #expect(payload["aud"] as? String == "appstoreconnect-v1")
        #expect(payload["exp"] as? Int == 1_800_000_900)
        let signature = try P256.Signing.ECDSASignature(rawRepresentation: base64URLDecode(parts[2]))
        #expect(key.publicKey.isValidSignature(signature, for: Data("\(parts[0]).\(parts[1])".utf8)))
    }

    @Test func individualTokensUseSubject() throws {
        let key = P256.Signing.PrivateKey()
        let credentials = APICredentials(
            name: "Me", kind: .individual, keyID: "ABCDE12345", issuerID: "", privateKeyPEM: key.pemRepresentation)
        try credentials.validate()
        let payload = try decodeSegment(String(try JSONWebToken.make(credentials: credentials).split(separator: ".")[1]))
        #expect(payload["sub"] as? String == "user")
        #expect(payload["iss"] == nil)
    }

    @Test func base64EncodedKeysAreAccepted() throws {
        let key = P256.Signing.PrivateKey()
        let encoded = Data(key.pemRepresentation.utf8).base64EncodedString()
        let credentials = APICredentials(
            name: "CI", keyID: "ABCDE12345", issuerID: UUID().uuidString, privateKeyPEM: encoded)
        try credentials.validate()
    }

    @Test func invalidCredentialsAreRejected() {
        let key = P256.Signing.PrivateKey().pemRepresentation
        #expect(throws: CredentialsError.invalidKeyID) {
            try APICredentials(name: "", keyID: "short", issuerID: UUID().uuidString, privateKeyPEM: key).validate()
        }
        #expect(throws: CredentialsError.invalidIssuerID) {
            try APICredentials(name: "", keyID: "ABCDE12345", issuerID: "nope", privateKeyPEM: key).validate()
        }
        #expect(throws: CredentialsError.invalidPrivateKey) {
            try APICredentials(name: "", keyID: "ABCDE12345", issuerID: UUID().uuidString, privateKeyPEM: "x")
                .validate()
        }
        #expect(APICredentials.keyID(fromFileName: "AuthKey_ABCDE12345.p8") == "ABCDE12345")
        #expect(APICredentials.keyID(fromFileName: "key.p8") == nil)
    }

    private func decodeSegment(_ segment: String) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: base64URLDecode(segment)) as? [String: Any] ?? [:]
    }

    private func base64URLDecode(_ text: String) -> Data {
        var base64 = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        return Data(base64Encoded: base64) ?? Data()
    }
}

extension Data {
    var hex: String { map { String(format: "%02X", $0) }.joined() }
}
