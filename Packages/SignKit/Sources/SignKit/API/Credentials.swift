import CryptoKit
import Foundation

public struct APICredentials: Codable, Sendable, Equatable, Hashable, Identifiable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case team
        case individual
    }

    public var id: String { keyID }
    public var name: String
    public var kind: Kind
    public var keyID: String
    public var issuerID: String
    public var privateKeyPEM: String

    public init(name: String, kind: Kind = .team, keyID: String, issuerID: String, privateKeyPEM: String) {
        self.name = name
        self.kind = kind
        self.keyID = keyID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.issuerID = issuerID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.privateKeyPEM = privateKeyPEM.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func keyID(fromFileName fileName: String) -> String? {
        let base = (fileName as NSString).deletingPathExtension
        guard base.hasPrefix("AuthKey_") else { return nil }
        let id = String(base.dropFirst("AuthKey_".count))
        return id.isEmpty ? nil : id
    }

    public func validate() throws {
        guard keyID.count == 10, keyID.allSatisfy({ $0.isLetter || $0.isNumber }) else {
            throw CredentialsError.invalidKeyID
        }
        if kind == .team {
            guard UUID(uuidString: issuerID) != nil else { throw CredentialsError.invalidIssuerID }
        }
        _ = try signingKey()
    }

    func signingKey() throws -> P256.Signing.PrivateKey {
        if let key = try? P256.Signing.PrivateKey(pemRepresentation: privateKeyPEM) {
            return key
        }
        if let data = Data(base64Encoded: privateKeyPEM.filter { !$0.isWhitespace }),
            let text = String(data: data, encoding: .utf8),
            let key = try? P256.Signing.PrivateKey(pemRepresentation: text)
        {
            return key
        }
        throw CredentialsError.invalidPrivateKey
    }
}

public enum CredentialsError: Error, LocalizedError, Equatable {
    case invalidKeyID
    case invalidIssuerID
    case invalidPrivateKey

    public var errorDescription: String? {
        switch self {
        case .invalidKeyID: "The key ID must be the 10 character identifier shown next to the key in App Store Connect."
        case .invalidIssuerID: "The issuer ID must be the UUID shown above the keys list in App Store Connect."
        case .invalidPrivateKey: "The private key must be the contents of the AuthKey .p8 file you downloaded."
        }
    }
}

public struct JSONWebToken {
    public static func make(credentials: APICredentials, now: Date = Date(), lifetime: TimeInterval = 15 * 60) throws -> String {
        let key = try credentials.signingKey()
        let header: [String: String] = ["alg": "ES256", "kid": credentials.keyID, "typ": "JWT"]
        var payload: [String: Any] = [
            "iat": Int(now.timeIntervalSince1970),
            "exp": Int(now.addingTimeInterval(lifetime).timeIntervalSince1970),
            "aud": "appstoreconnect-v1",
        ]
        switch credentials.kind {
        case .team:
            payload["iss"] = credentials.issuerID
        case .individual:
            payload["sub"] = "user"
        }
        let encodedHeader = try base64URL(JSONSerialization.data(withJSONObject: header, options: .sortedKeys))
        let encodedPayload = try base64URL(JSONSerialization.data(withJSONObject: payload, options: .sortedKeys))
        let signingInput = "\(encodedHeader).\(encodedPayload)"
        let signature = try key.signature(for: Data(signingInput.utf8))
        return "\(signingInput).\(base64URL(signature.rawRepresentation))"
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
