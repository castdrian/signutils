import Foundation

public struct CapabilityType: OpenEnum, Identifiable, Comparable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public var id: String { rawValue }

    public static func < (lhs: CapabilityType, rhs: CapabilityType) -> Bool {
        lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
    }

    public static let accessWiFiInformation = CapabilityType(rawValue: "ACCESS_WIFI_INFORMATION")
    public static let appGroups = CapabilityType(rawValue: "APP_GROUPS")
    public static let applePay = CapabilityType(rawValue: "APPLE_PAY")
    public static let associatedDomains = CapabilityType(rawValue: "ASSOCIATED_DOMAINS")
    public static let autofillCredentialProvider = CapabilityType(rawValue: "AUTOFILL_CREDENTIAL_PROVIDER")
    public static let classKit = CapabilityType(rawValue: "CLASSKIT")
    public static let coreMediaHLSLowLatency = CapabilityType(rawValue: "COREMEDIA_HLS_LOW_LATENCY")
    public static let dataProtection = CapabilityType(rawValue: "DATA_PROTECTION")
    public static let gameCenter = CapabilityType(rawValue: "GAME_CENTER")
    public static let healthKit = CapabilityType(rawValue: "HEALTHKIT")
    public static let homeKit = CapabilityType(rawValue: "HOMEKIT")
    public static let hotspot = CapabilityType(rawValue: "HOT_SPOT")
    public static let iCloud = CapabilityType(rawValue: "ICLOUD")
    public static let inAppPurchase = CapabilityType(rawValue: "IN_APP_PURCHASE")
    public static let interAppAudio = CapabilityType(rawValue: "INTER_APP_AUDIO")
    public static let maps = CapabilityType(rawValue: "MAPS")
    public static let multipath = CapabilityType(rawValue: "MULTIPATH")
    public static let networkCustomProtocol = CapabilityType(rawValue: "NETWORK_CUSTOM_PROTOCOL")
    public static let networkExtensions = CapabilityType(rawValue: "NETWORK_EXTENSIONS")
    public static let nfcTagReading = CapabilityType(rawValue: "NFC_TAG_READING")
    public static let personalVPN = CapabilityType(rawValue: "PERSONAL_VPN")
    public static let pushNotifications = CapabilityType(rawValue: "PUSH_NOTIFICATIONS")
    public static let signInWithApple = CapabilityType(rawValue: "APPLE_ID_AUTH")
    public static let siriKit = CapabilityType(rawValue: "SIRIKIT")
    public static let systemExtensionInstall = CapabilityType(rawValue: "SYSTEM_EXTENSION_INSTALL")
    public static let userManagement = CapabilityType(rawValue: "USER_MANAGEMENT")
    public static let wallet = CapabilityType(rawValue: "WALLET")
    public static let wirelessAccessoryConfiguration = CapabilityType(rawValue: "WIRELESS_ACCESSORY_CONFIGURATION")

    public static let catalog: [CapabilityType] = [
        .accessWiFiInformation, .appGroups, .applePay, .associatedDomains, .autofillCredentialProvider, .classKit,
        .coreMediaHLSLowLatency, .dataProtection, .gameCenter, .healthKit, .homeKit, .hotspot, .iCloud, .inAppPurchase,
        .interAppAudio, .maps, .multipath, .networkCustomProtocol, .networkExtensions, .nfcTagReading, .personalVPN,
        .pushNotifications, .signInWithApple, .siriKit, .systemExtensionInstall, .userManagement, .wallet,
        .wirelessAccessoryConfiguration,
    ].sorted()

    public static let commonCapabilities: [CapabilityType] = [
        .appGroups, .associatedDomains, .iCloud, .pushNotifications, .networkExtensions, .personalVPN, .siriKit,
        .healthKit, .homeKit, .accessWiFiInformation,
    ]

    public var displayName: String {
        switch self {
        case .accessWiFiInformation: "Access Wi-Fi Information"
        case .appGroups: "App Groups"
        case .applePay: "Apple Pay"
        case .associatedDomains: "Associated Domains"
        case .autofillCredentialProvider: "AutoFill Credential Provider"
        case .classKit: "ClassKit"
        case .coreMediaHLSLowLatency: "Low Latency HLS"
        case .dataProtection: "Data Protection"
        case .gameCenter: "Game Center"
        case .healthKit: "HealthKit"
        case .homeKit: "HomeKit"
        case .hotspot: "Hotspot"
        case .iCloud: "iCloud"
        case .inAppPurchase: "In-App Purchase"
        case .interAppAudio: "Inter-App Audio"
        case .maps: "Maps"
        case .multipath: "Multipath"
        case .networkCustomProtocol: "Custom Network Protocol"
        case .networkExtensions: "Network Extensions"
        case .nfcTagReading: "NFC Tag Reading"
        case .personalVPN: "Personal VPN"
        case .pushNotifications: "Push Notifications"
        case .signInWithApple: "Sign in with Apple"
        case .siriKit: "SiriKit"
        case .systemExtensionInstall: "System Extension"
        case .userManagement: "User Management"
        case .wallet: "Wallet"
        case .wirelessAccessoryConfiguration: "Wireless Accessory Configuration"
        default: rawValue.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    public var symbolName: String {
        switch self {
        case .accessWiFiInformation: "wifi"
        case .appGroups: "square.on.square"
        case .applePay: "creditcard"
        case .associatedDomains: "link"
        case .autofillCredentialProvider: "key.fill"
        case .classKit: "graduationcap"
        case .coreMediaHLSLowLatency: "play.rectangle"
        case .dataProtection: "lock.shield"
        case .gameCenter: "gamecontroller"
        case .healthKit: "heart"
        case .homeKit: "house"
        case .hotspot: "personalhotspot"
        case .iCloud: "icloud"
        case .inAppPurchase: "cart"
        case .interAppAudio: "waveform"
        case .maps: "map"
        case .multipath: "point.3.connected.trianglepath.dotted"
        case .networkCustomProtocol: "network"
        case .networkExtensions: "network.badge.shield.half.filled"
        case .nfcTagReading: "wave.3.right"
        case .personalVPN: "lock.rectangle.stack"
        case .pushNotifications: "bell.badge"
        case .signInWithApple: "apple.logo"
        case .siriKit: "mic"
        case .systemExtensionInstall: "puzzlepiece.extension"
        case .userManagement: "person.2"
        case .wallet: "wallet.pass"
        case .wirelessAccessoryConfiguration: "antenna.radiowaves.left.and.right"
        default: "checkmark.seal"
        }
    }

    public var defaultSettings: [CapabilitySetting] {
        switch self {
        case .iCloud:
            [CapabilitySetting(key: "ICLOUD_VERSION", options: [CapabilityOption(key: "XCODE_6")])]
        case .dataProtection:
            [
                CapabilitySetting(
                    key: "DATA_PROTECTION_PERMISSION_LEVEL", options: [CapabilityOption(key: "COMPLETE_PROTECTION")])
            ]
        case .signInWithApple:
            [CapabilitySetting(key: "APPLE_ID_AUTH_APP_CONSENT", options: [CapabilityOption(key: "PRIMARY_APP_CONSENT")])]
        default:
            []
        }
    }

    public var isAlwaysOn: Bool {
        [.inAppPurchase, .gameCenter].contains(self)
    }
}
