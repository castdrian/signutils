import Foundation

public protocol OpenEnum: RawRepresentable, Codable, Hashable, Sendable where RawValue == String {
    init(rawValue: String)
}

extension OpenEnum {
    public init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct CertificateType: OpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let development = CertificateType(rawValue: "DEVELOPMENT")
    public static let distribution = CertificateType(rawValue: "DISTRIBUTION")
    public static let iosDevelopment = CertificateType(rawValue: "IOS_DEVELOPMENT")
    public static let iosDistribution = CertificateType(rawValue: "IOS_DISTRIBUTION")
    public static let macAppDevelopment = CertificateType(rawValue: "MAC_APP_DEVELOPMENT")
    public static let macAppDistribution = CertificateType(rawValue: "MAC_APP_DISTRIBUTION")
    public static let macInstallerDistribution = CertificateType(rawValue: "MAC_INSTALLER_DISTRIBUTION")
    public static let developerIDApplication = CertificateType(rawValue: "DEVELOPER_ID_APPLICATION")
    public static let developerIDApplicationG2 = CertificateType(rawValue: "DEVELOPER_ID_APPLICATION_G2")
    public static let developerIDKext = CertificateType(rawValue: "DEVELOPER_ID_KEXT")

    public var displayName: String {
        switch self {
        case .development: "Apple Development"
        case .distribution: "Apple Distribution"
        case .iosDevelopment: "iOS Development"
        case .iosDistribution: "iOS Distribution"
        case .macAppDevelopment: "Mac Development"
        case .macAppDistribution: "Mac App Distribution"
        case .macInstallerDistribution: "Mac Installer Distribution"
        case .developerIDApplication: "Developer ID Application"
        case .developerIDApplicationG2: "Developer ID Application (G2)"
        case .developerIDKext: "Developer ID Kext"
        default: rawValue.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    public var isDistribution: Bool {
        [.distribution, .iosDistribution, .macAppDistribution].contains(self)
    }
}

public struct ProfileType: OpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let iosAppDevelopment = ProfileType(rawValue: "IOS_APP_DEVELOPMENT")
    public static let iosAppAdHoc = ProfileType(rawValue: "IOS_APP_ADHOC")
    public static let iosAppStore = ProfileType(rawValue: "IOS_APP_STORE")
    public static let tvosAppDevelopment = ProfileType(rawValue: "TVOS_APP_DEVELOPMENT")
    public static let tvosAppAdHoc = ProfileType(rawValue: "TVOS_APP_ADHOC")
    public static let macAppDevelopment = ProfileType(rawValue: "MAC_APP_DEVELOPMENT")
    public static let macAppStore = ProfileType(rawValue: "MAC_APP_STORE")
    public static let macAppDirect = ProfileType(rawValue: "MAC_APP_DIRECT")

    public var displayName: String {
        switch self {
        case .iosAppDevelopment: "iOS Development"
        case .iosAppAdHoc: "iOS Ad Hoc"
        case .iosAppStore: "iOS App Store"
        case .tvosAppDevelopment: "tvOS Development"
        case .tvosAppAdHoc: "tvOS Ad Hoc"
        case .macAppDevelopment: "macOS Development"
        case .macAppStore: "Mac App Store"
        case .macAppDirect: "Developer ID"
        default: rawValue.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    public var includesDevices: Bool {
        [.iosAppDevelopment, .iosAppAdHoc, .tvosAppDevelopment, .tvosAppAdHoc, .macAppDevelopment].contains(self)
    }
}

public struct BundleIDPlatform: OpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let ios = BundleIDPlatform(rawValue: "IOS")
    public static let macOS = BundleIDPlatform(rawValue: "MAC_OS")
    public static let universal = BundleIDPlatform(rawValue: "UNIVERSAL")
    public static let services = BundleIDPlatform(rawValue: "SERVICES")

    public var displayName: String {
        switch self {
        case .ios: "iOS"
        case .macOS: "macOS"
        case .universal: "Universal"
        case .services: "Services"
        default: rawValue.capitalized
        }
    }
}

public struct DeviceClass: OpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let iPhone = DeviceClass(rawValue: "IPHONE")
    public static let iPad = DeviceClass(rawValue: "IPAD")
    public static let iPod = DeviceClass(rawValue: "IPOD")
    public static let appleTV = DeviceClass(rawValue: "APPLE_TV")
    public static let appleWatch = DeviceClass(rawValue: "APPLE_WATCH")
    public static let appleVisionPro = DeviceClass(rawValue: "APPLE_VISION_PRO")
    public static let mac = DeviceClass(rawValue: "MAC")

    public var displayName: String {
        switch self {
        case .iPhone: "iPhone"
        case .iPad: "iPad"
        case .iPod: "iPod touch"
        case .appleTV: "Apple TV"
        case .appleWatch: "Apple Watch"
        case .appleVisionPro: "Apple Vision Pro"
        case .mac: "Mac"
        default: rawValue.capitalized
        }
    }

    public var symbolName: String {
        switch self {
        case .iPhone: "iphone"
        case .iPad: "ipad"
        case .iPod: "ipodtouch"
        case .appleTV: "appletv"
        case .appleWatch: "applewatch"
        case .appleVisionPro: "visionpro"
        case .mac: "macbook"
        default: "questionmark.square.dashed"
        }
    }
}

public struct Certificate: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var displayName: String
    public var certificateType: CertificateType
    public var serialNumber: String
    public var expirationDate: Date?
    public var content: Data?

    public init(
        id: String, name: String, displayName: String, certificateType: CertificateType, serialNumber: String,
        expirationDate: Date?, content: Data?
    ) {
        self.id = id
        self.name = name
        self.displayName = displayName
        self.certificateType = certificateType
        self.serialNumber = serialNumber
        self.expirationDate = expirationDate
        self.content = content
    }
}

public struct BundleID: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var identifier: String
    public var name: String
    public var platform: BundleIDPlatform
    public var seedID: String?

    public init(id: String, identifier: String, name: String, platform: BundleIDPlatform, seedID: String?) {
        self.id = id
        self.identifier = identifier
        self.name = name
        self.platform = platform
        self.seedID = seedID
    }

    public var isWildcard: Bool { identifier.hasSuffix("*") }
}

public struct BundleIDCapability: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var capabilityType: CapabilityType
    public var settings: [CapabilitySetting]

    public init(id: String, capabilityType: CapabilityType, settings: [CapabilitySetting] = []) {
        self.id = id
        self.capabilityType = capabilityType
        self.settings = settings
    }
}

public struct CapabilitySetting: Codable, Sendable, Hashable {
    public var key: String
    public var options: [CapabilityOption]

    public init(key: String, options: [CapabilityOption]) {
        self.key = key
        self.options = options
    }
}

public struct CapabilityOption: Codable, Sendable, Hashable {
    public var key: String
    public var enabled: Bool?

    public init(key: String, enabled: Bool? = true) {
        self.key = key
        self.enabled = enabled
    }
}

public struct Device: Codable, Sendable, Hashable, Identifiable {
    public enum Status: String, Codable, Sendable {
        case enabled = "ENABLED"
        case disabled = "DISABLED"
        case processing = "PROCESSING"
    }

    public var id: String
    public var name: String
    public var udid: String
    public var platform: BundleIDPlatform
    public var deviceClass: DeviceClass
    public var model: String?
    public var status: Status
    public var addedDate: Date?

    public init(
        id: String, name: String, udid: String, platform: BundleIDPlatform, deviceClass: DeviceClass, model: String?,
        status: Status, addedDate: Date?
    ) {
        self.id = id
        self.name = name
        self.udid = udid
        self.platform = platform
        self.deviceClass = deviceClass
        self.model = model
        self.status = status
        self.addedDate = addedDate
    }
}

public struct Profile: Codable, Sendable, Hashable, Identifiable {
    public enum State: String, Codable, Sendable {
        case active = "ACTIVE"
        case invalid = "INVALID"
    }

    public var id: String
    public var name: String
    public var profileType: ProfileType
    public var state: State
    public var uuid: String
    public var expirationDate: Date?
    public var content: Data?
    public var bundleIDResource: String?
    public var certificateIDs: [String]
    public var deviceIDs: [String]

    public init(
        id: String, name: String, profileType: ProfileType, state: State, uuid: String, expirationDate: Date?,
        content: Data?, bundleIDResource: String?, certificateIDs: [String], deviceIDs: [String]
    ) {
        self.id = id
        self.name = name
        self.profileType = profileType
        self.state = state
        self.uuid = uuid
        self.expirationDate = expirationDate
        self.content = content
        self.bundleIDResource = bundleIDResource
        self.certificateIDs = certificateIDs
        self.deviceIDs = deviceIDs
    }
}
