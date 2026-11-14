import Foundation

public struct SigningBundle: Codable, Sendable, Hashable, Identifiable {
    public struct DeviceSummary: Codable, Sendable, Hashable {
        public var name: String
        public var udid: String
        public var deviceClass: DeviceClass

        public init(name: String, udid: String, deviceClass: DeviceClass) {
            self.name = name
            self.udid = udid
            self.deviceClass = deviceClass
        }
    }

    public var id: UUID
    public var name: String
    public var createdAt: Date
    public var kind: SigningKind
    public var platform: SigningPlatform
    public var teamID: String
    public var teamName: String
    public var bundleIdentifier: String
    public var bundleIDResource: String
    public var capabilities: [CapabilityType]
    public var devices: [DeviceSummary]
    public var certificateID: String
    public var certificateType: CertificateType
    public var certificateName: String
    public var certificateSerial: String
    public var certificateExpiration: Date
    public var profileID: String
    public var profileUUID: String
    public var profileName: String
    public var profileType: ProfileType
    public var profileExpiration: Date
    public var password: String
    public var fileName: String
    public var credentialsKeyID: String

    public init(
        id: UUID = UUID(), name: String, createdAt: Date = Date(), kind: SigningKind, platform: SigningPlatform,
        teamID: String, teamName: String, bundleIdentifier: String, bundleIDResource: String,
        capabilities: [CapabilityType], devices: [DeviceSummary], certificateID: String,
        certificateType: CertificateType, certificateName: String, certificateSerial: String,
        certificateExpiration: Date, profileID: String, profileUUID: String, profileName: String,
        profileType: ProfileType, profileExpiration: Date, password: String, fileName: String,
        credentialsKeyID: String
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.kind = kind
        self.platform = platform
        self.teamID = teamID
        self.teamName = teamName
        self.bundleIdentifier = bundleIdentifier
        self.bundleIDResource = bundleIDResource
        self.capabilities = capabilities
        self.devices = devices
        self.certificateID = certificateID
        self.certificateType = certificateType
        self.certificateName = certificateName
        self.certificateSerial = certificateSerial
        self.certificateExpiration = certificateExpiration
        self.profileID = profileID
        self.profileUUID = profileUUID
        self.profileName = profileName
        self.profileType = profileType
        self.profileExpiration = profileExpiration
        self.password = password
        self.fileName = fileName
        self.credentialsKeyID = credentialsKeyID
    }

    public var expiration: Date { min(certificateExpiration, profileExpiration) }

    public var archiveBaseName: String { SigningBundle.slug(name) }

    public static func slug(_ text: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let mapped = text.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let collapsed = String(mapped).split(separator: "-").joined(separator: "-")
        return collapsed.isEmpty ? "signing" : collapsed
    }
}

public struct SigningArtifacts: Sendable {
    public var bundle: SigningBundle
    public var archive: Data
    public var p12: Data
    public var profile: Data
    public var certificate: Data
}

public enum SigningArchive {
    public static func entries(
        bundle: SigningBundle, p12: Data, profile: Data, certificate: Data, createdAt: Date = Date()
    ) throws -> [ZipEntry] {
        let base = bundle.archiveBaseName
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let info = try encoder.encode(Manifest(bundle: bundle))
        return [
            ZipEntry(path: "\(base)/\(base).p12", data: p12, modified: createdAt),
            ZipEntry(path: "\(base)/\(base).mobileprovision", data: profile, modified: createdAt),
            ZipEntry(path: "\(base)/password.txt", data: Data((bundle.password + "\n").utf8), modified: createdAt),
            ZipEntry(path: "\(base)/certificate.cer", data: certificate, modified: createdAt),
            ZipEntry(path: "\(base)/info.json", data: info, modified: createdAt),
            ZipEntry(path: "\(base)/README.txt", data: Data(readme(bundle).utf8), modified: createdAt),
        ]
    }

    static func readme(_ bundle: SigningBundle) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let devices = bundle.devices.map { "  - \($0.name) (\($0.udid))" }.joined(separator: "\n")
        return """
            \(bundle.name)
            Generated by SignUtils on \(formatter.string(from: bundle.createdAt))

            Team: \(bundle.teamName) (\(bundle.teamID))
            App ID: \(bundle.bundleIdentifier)
            Signing: \(bundle.kind.title) (\(bundle.certificateType.displayName))
            Certificate expires: \(formatter.string(from: bundle.certificateExpiration))
            Profile expires: \(formatter.string(from: bundle.profileExpiration))
            P12 password: \(bundle.password)

            Devices:
            \(devices.isEmpty ? "  none" : devices)

            Import \(bundle.archiveBaseName).p12 and \(bundle.archiveBaseName).mobileprovision into your signing tool
            and enter the password from password.txt. Keep this archive private: anyone with it can sign apps as your team.

            """
    }

    struct Manifest: Encodable {
        var name: String
        var createdAt: Date
        var kind: SigningKind
        var platform: SigningPlatform
        var teamID: String
        var teamName: String
        var bundleIdentifier: String
        var capabilities: [String]
        var devices: [SigningBundle.DeviceSummary]
        var certificate: [String: String]
        var profile: [String: String]
        var password: String

        init(bundle: SigningBundle) {
            let iso = ISO8601DateFormatter()
            name = bundle.name
            createdAt = bundle.createdAt
            kind = bundle.kind
            platform = bundle.platform
            teamID = bundle.teamID
            teamName = bundle.teamName
            bundleIdentifier = bundle.bundleIdentifier
            capabilities = bundle.capabilities.map(\.rawValue).sorted()
            devices = bundle.devices
            certificate = [
                "id": bundle.certificateID, "type": bundle.certificateType.rawValue, "name": bundle.certificateName,
                "serialNumber": bundle.certificateSerial, "expires": iso.string(from: bundle.certificateExpiration),
            ]
            profile = [
                "id": bundle.profileID, "uuid": bundle.profileUUID, "name": bundle.profileName,
                "type": bundle.profileType.rawValue, "expires": iso.string(from: bundle.profileExpiration),
            ]
            password = bundle.password
        }
    }
}
