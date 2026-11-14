import Foundation

public enum SigningKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case development
    case adHoc

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .development: "Development"
        case .adHoc: "Ad Hoc"
        }
    }

    public var summary: String {
        switch self {
        case .development:
            "Debuggable builds for your team’s registered devices, with get-task-allow so the debugger can attach."
        case .adHoc:
            "Release builds for up to 100 devices per device type. Not debuggable, closest to how App Store apps run."
        }
    }

    public var certificateTypes: [CertificateType] {
        switch self {
        case .development: [.development, .iosDevelopment]
        case .adHoc: [.distribution, .iosDistribution]
        }
    }

    public func profileType(for platform: SigningPlatform) -> ProfileType {
        switch (self, platform) {
        case (.development, .iOS): .iosAppDevelopment
        case (.adHoc, .iOS): .iosAppAdHoc
        case (.development, .tvOS): .tvosAppDevelopment
        case (.adHoc, .tvOS): .tvosAppAdHoc
        }
    }
}

public enum SigningPlatform: String, Codable, Sendable, CaseIterable, Identifiable {
    case iOS
    case tvOS

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .iOS: "iOS, iPadOS and visionOS"
        case .tvOS: "tvOS"
        }
    }

    public func accepts(_ device: Device) -> Bool {
        guard device.platform == .ios || device.platform == .universal else { return false }
        switch self {
        case .iOS: return device.deviceClass != .appleTV && device.deviceClass != .mac
        case .tvOS: return device.deviceClass == .appleTV
        }
    }
}

public enum AppIDChoice: Sendable, Equatable {
    case existing(BundleID)
    case new(identifier: String, name: String)

    public var identifier: String {
        switch self {
        case .existing(let bundleID): bundleID.identifier
        case .new(let identifier, _): identifier
        }
    }
}

public enum CertificateChoice: Sendable, Equatable {
    case new(type: CertificateType, commonName: String)
    case existing(Certificate)
}

public struct NewDevice: Sendable, Equatable, Hashable {
    public var name: String
    public var udid: String

    public init(name: String, udid: String) {
        self.name = name
        self.udid = udid
    }
}

public struct SigningRequest: Sendable, Equatable {
    public var kind: SigningKind
    public var platform: SigningPlatform
    public var appID: AppIDChoice
    public var capabilities: Set<CapabilityType>
    public var manageCapabilities: Bool
    public var devices: [Device]
    public var newDevices: [NewDevice]
    public var certificate: CertificateChoice
    public var password: String
    public var name: String

    public init(
        kind: SigningKind,
        platform: SigningPlatform = .iOS,
        appID: AppIDChoice,
        capabilities: Set<CapabilityType> = [],
        manageCapabilities: Bool = true,
        devices: [Device] = [],
        newDevices: [NewDevice] = [],
        certificate: CertificateChoice,
        password: String,
        name: String
    ) {
        self.kind = kind
        self.platform = platform
        self.appID = appID
        self.capabilities = capabilities
        self.manageCapabilities = manageCapabilities
        self.devices = devices
        self.newDevices = newDevices
        self.certificate = certificate
        self.password = password
        self.name = name
    }
}

public enum UDID {
    public static func normalize(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    public static func isValid(_ text: String) -> Bool {
        let value = normalize(text)
        let hex = CharacterSet(charactersIn: "0123456789ABCDEF")
        if value.count == 40 {
            return value.unicodeScalars.allSatisfy(hex.contains)
        }
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        if parts.count == 2, parts[0].count == 8, parts[1].count == 16 {
            return parts.joined().unicodeScalars.allSatisfy(hex.contains)
        }
        return false
    }
}

public enum BundleIdentifier {
    public static func isValid(_ text: String) -> Bool {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return false }
        for (index, part) in parts.enumerated() {
            if part == "*" {
                if index != parts.count - 1 { return false }
                continue
            }
            guard !part.isEmpty, part.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) else {
                return false
            }
        }
        return true
    }

    public static func suggestedName(for identifier: String) -> String {
        let parts = identifier.split(separator: ".").map(String.init).filter { $0 != "*" }
        let base = parts.last ?? identifier
        let cleaned = base.replacingOccurrences(of: "-", with: " ")
        let title = cleaned.prefix(1).uppercased() + cleaned.dropFirst()
        return identifier.hasSuffix("*") ? "\(title) Wildcard" : title
    }

    public static func apiName(_ name: String) -> String {
        let allowed = name.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) || scalar == " " ? Character(scalar) : " "
        }
        let collapsed = String(allowed).split(separator: " ").joined(separator: " ")
        return collapsed.isEmpty ? "SignUtils App" : collapsed
    }
}

public enum Passwords {
    public static func isAllowed(_ password: String) -> Bool {
        password.unicodeScalars.allSatisfy { $0.value >= 0x20 && $0.value < 0x7F }
    }

    public static func generate(length: Int = 20) -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789")
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        return String(bytes.map { alphabet[Int($0) % alphabet.count] })
    }
}
