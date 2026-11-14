import Foundation

public actor DemoAppStoreConnect: AppStoreConnectService {
    public static let teamID = "DEMO7TEAM1"
    public static let teamName = "Demo Studio"

    public var latency: Duration
    public private(set) var certificateStore: [Certificate]
    public private(set) var bundleIDStore: [BundleID]
    public private(set) var capabilityStore: [String: [BundleIDCapability]]
    public private(set) var deviceStore: [Device]
    public private(set) var profileStore: [Profile]
    public var failure: (@Sendable (String) -> AppStoreConnectError?)?
    private let authority: RSAKeyPair
    private var counter = 0

    public init(latency: Duration = .zero, seeded: Bool = true) throws {
        self.latency = latency
        let authority = try RSAKeyPair.generate()
        self.authority = authority
        let seed = seeded ? Self.seed(authority: authority) : Seed()
        self.certificateStore = seed.certificates
        self.bundleIDStore = seed.bundleIDs
        self.capabilityStore = seed.capabilities
        self.deviceStore = seed.devices
        self.profileStore = []
    }

    private struct Seed {
        var certificates: [Certificate] = []
        var bundleIDs: [BundleID] = []
        var capabilities: [String: [BundleIDCapability]] = [:]
        var devices: [Device] = []
    }

    public func setFailure(_ failure: (@Sendable (String) -> AppStoreConnectError?)?) {
        self.failure = failure
    }

    private static func seed(authority: RSAKeyPair) -> Seed {
        let now = Date()
        var seed = Seed()
        seed.devices = [
            Device(
                id: "DEV1", name: "Adrian’s iPhone 17 Pro", udid: "00008150-001A2B3C4D5E6F70", platform: .ios,
                deviceClass: .iPhone, model: "iPhone 17 Pro", status: .enabled, addedDate: now.addingTimeInterval(-9e6)),
            Device(
                id: "DEV2", name: "Studio iPad Pro", udid: "00008142-000E1D2C3B4A5968", platform: .ios,
                deviceClass: .iPad, model: "iPad Pro 13-inch (M5)", status: .enabled,
                addedDate: now.addingTimeInterval(-6e6)),
            Device(
                id: "DEV3", name: "Test iPhone 16e", udid: "00008140-0019283746556473", platform: .ios,
                deviceClass: .iPhone, model: "iPhone 16e", status: .enabled, addedDate: now.addingTimeInterval(-3e6)),
            Device(
                id: "DEV4", name: "Living Room", udid: "00008110-00112233445566FF", platform: .ios,
                deviceClass: .appleTV, model: "Apple TV 4K", status: .enabled, addedDate: now.addingTimeInterval(-2e6)),
            Device(
                id: "DEV5", name: "Old iPhone XS", udid: "a1b2c3d4e5f60718293a4b5c6d7e8f9012345678", platform: .ios,
                deviceClass: .iPhone, model: "iPhone XS", status: .disabled, addedDate: now.addingTimeInterval(-4e7)),
        ]
        seed.bundleIDs = [
            BundleID(id: "BID1", identifier: "com.demo.fieldnotes", name: "Field Notes", platform: .universal, seedID: Self.teamID),
            BundleID(id: "BID2", identifier: "com.demo.pixelstudio", name: "Pixel Studio", platform: .universal, seedID: Self.teamID),
            BundleID(id: "BID3", identifier: "com.demo.*", name: "Demo Wildcard", platform: .universal, seedID: Self.teamID),
            BundleID(id: "BID4", identifier: "com.demo.music", name: "Music Player", platform: .ios, seedID: Self.teamID),
        ]
        seed.capabilities = [
            "BID1": [
                BundleIDCapability(id: "BID1_APP_GROUPS", capabilityType: .appGroups),
                BundleIDCapability(id: "BID1_ASSOCIATED_DOMAINS", capabilityType: .associatedDomains),
            ],
            "BID2": [BundleIDCapability(id: "BID2_GAME_CENTER", capabilityType: .gameCenter)],
        ]
        for (index, type) in [CertificateType.development, .distribution, .developerIDApplication].enumerated() {
            let keyPair = try? RSAKeyPair.generate()
            let commonName = "\(type.displayName): Demo Studio (\(Self.teamID))"
            let content = keyPair.flatMap {
                try? issue(authority: authority, serial: 0x100 + index, publicKeyInfo: $0.subjectPublicKeyInfo, commonName: commonName)
            }
            seed.certificates.append(
                Certificate(
                    id: "SEED\(index)", name: commonName, displayName: "Demo Studio", certificateType: type,
                    serialNumber: String(format: "%016X", 0xA1B2_C3D4 + index), expirationDate: now.addingTimeInterval(2.5e7),
                    content: content))
        }
        return seed
    }

    private func pause(_ operation: String) async throws {
        if latency > .zero {
            try await Task.sleep(for: latency)
        }
        if let error = failure?(operation) {
            throw error
        }
    }

    private func nextID(_ prefix: String) -> String {
        counter += 1
        return "\(prefix)\(counter)"
    }

    public func certificates() async throws -> [Certificate] {
        try await pause("certificates")
        return certificateStore
    }

    public func certificate(id: String) async throws -> Certificate {
        try await pause("certificate")
        guard let certificate = certificateStore.first(where: { $0.id == id }) else { throw notFound("certificate") }
        return certificate
    }

    public func createCertificate(type: CertificateType, csr: CertificateSigningRequest) async throws -> Certificate {
        try await pause("createCertificate")
        let limit = type.isDistribution ? 3 : 20
        guard certificateStore.filter({ $0.certificateType == type }).count < limit else {
            throw AppStoreConnectError(
                statusCode: 409,
                items: [
                    .init(
                        status: "409", code: "ENTITY_ERROR", title: "There is a problem with the request entity",
                        detail: "You already have a current \(type.displayName) certificate or a pending certificate request.")
                ])
        }
        let request = try DERNode.parse(csr.der).children()[0].children()
        let commonName = "\(type.displayName): Demo Studio (\(Self.teamID))"
        let content = try issue(publicKeyInfo: request[2].encoded, commonName: commonName)
        let certificate = Certificate(
            id: nextID("CERT"), name: commonName, displayName: "Demo Studio", certificateType: type,
            serialNumber: String(format: "%016X", counter + 0x5000), expirationDate: Date().addingTimeInterval(3.15e7),
            content: content)
        certificateStore.append(certificate)
        return certificate
    }

    public func revokeCertificate(id: String) async throws {
        try await pause("revokeCertificate")
        guard certificateStore.contains(where: { $0.id == id }) else { throw notFound("certificate") }
        certificateStore.removeAll { $0.id == id }
        for index in profileStore.indices where profileStore[index].certificateIDs.contains(id) {
            profileStore[index].state = .invalid
        }
    }

    public func bundleIDs() async throws -> [BundleID] {
        try await pause("bundleIDs")
        return bundleIDStore.sorted { $0.identifier < $1.identifier }
    }

    public func createBundleID(identifier: String, name: String, platform: BundleIDPlatform) async throws -> BundleID {
        try await pause("createBundleID")
        guard !bundleIDStore.contains(where: { $0.identifier == identifier }) else {
            throw AppStoreConnectError(
                statusCode: 409,
                items: [.init(status: "409", code: "ENTITY_ERROR.ATTRIBUTE.INVALID", title: "An attribute value is invalid",
                              detail: "An App ID with Identifier '\(identifier)' is not available. Please enter a different string.")])
        }
        let bundleID = BundleID(id: nextID("BID"), identifier: identifier, name: name, platform: platform, seedID: Self.teamID)
        bundleIDStore.append(bundleID)
        return bundleID
    }

    public func deleteBundleID(id: String) async throws {
        try await pause("deleteBundleID")
        bundleIDStore.removeAll { $0.id == id }
        capabilityStore[id] = nil
    }

    public func capabilities(bundleID: String) async throws -> [BundleIDCapability] {
        try await pause("capabilities")
        return capabilityStore[bundleID] ?? []
    }

    public func enableCapability(_ type: CapabilityType, settings: [CapabilitySetting], bundleID: String) async throws
        -> BundleIDCapability
    {
        try await pause("enableCapability")
        let capability = BundleIDCapability(id: "\(bundleID)_\(type.rawValue)", capabilityType: type, settings: settings)
        capabilityStore[bundleID, default: []].removeAll { $0.capabilityType == type }
        capabilityStore[bundleID, default: []].append(capability)
        return capability
    }

    public func disableCapability(id: String) async throws {
        try await pause("disableCapability")
        for key in capabilityStore.keys {
            capabilityStore[key]?.removeAll { $0.id == id }
        }
    }

    public func devices() async throws -> [Device] {
        try await pause("devices")
        return deviceStore.sorted { $0.name < $1.name }
    }

    public func registerDevice(name: String, udid: String, platform: BundleIDPlatform) async throws -> Device {
        try await pause("registerDevice")
        let device = Device(
            id: nextID("DEV"), name: name, udid: udid, platform: platform, deviceClass: .iPhone, model: nil,
            status: .enabled, addedDate: Date())
        deviceStore.append(device)
        return device
    }

    public func updateDevice(id: String, name: String?, status: Device.Status?) async throws -> Device {
        try await pause("updateDevice")
        guard let index = deviceStore.firstIndex(where: { $0.id == id }) else { throw notFound("device") }
        if let name { deviceStore[index].name = name }
        if let status { deviceStore[index].status = status }
        return deviceStore[index]
    }

    public func profiles() async throws -> [Profile] {
        try await pause("profiles")
        return profileStore.map { var copy = $0; copy.content = nil; return copy }
    }

    public func profile(id: String) async throws -> Profile {
        try await pause("profile")
        guard let profile = profileStore.first(where: { $0.id == id }) else { throw notFound("profile") }
        return profile
    }

    public func createProfile(
        name: String, type: ProfileType, bundleID: String, certificateIDs: [String], deviceIDs: [String]
    ) async throws -> Profile {
        try await pause("createProfile")
        guard let bundle = bundleIDStore.first(where: { $0.id == bundleID }) else { throw notFound("bundleId") }
        let certificates = certificateStore.filter { certificateIDs.contains($0.id) }.compactMap(\.content)
        let devices = deviceStore.filter { deviceIDs.contains($0.id) }.map(\.udid)
        let uuid = UUID().uuidString
        let expiration = Date().addingTimeInterval(type == .iosAppAdHoc ? 3.15e7 : 3.15e7)
        let content = try Self.profileData(
            name: name, uuid: uuid, bundleIdentifier: bundle.identifier, certificates: certificates, devices: devices,
            debuggable: type == .iosAppDevelopment || type == .tvosAppDevelopment, expiration: expiration)
        let profile = Profile(
            id: nextID("PROF"), name: name, profileType: type, state: .active, uuid: uuid, expirationDate: expiration,
            content: content, bundleIDResource: bundleID, certificateIDs: certificateIDs, deviceIDs: deviceIDs)
        profileStore.append(profile)
        return profile
    }

    public func deleteProfile(id: String) async throws {
        try await pause("deleteProfile")
        profileStore.removeAll { $0.id == id }
    }

    private func notFound(_ type: String) -> AppStoreConnectError {
        AppStoreConnectError(
            statusCode: 404,
            items: [.init(status: "404", code: "NOT_FOUND", title: "The specified resource does not exist", detail: "There is no \(type) with this id.")])
    }

    private func issue(publicKeyInfo: Data, commonName: String) throws -> Data {
        counter += 1
        return try Self.issue(authority: authority, serial: 0x1000 + counter, publicKeyInfo: publicKeyInfo, commonName: commonName)
    }

    private static func issue(authority: RSAKeyPair, serial: Int, publicKeyInfo: Data, commonName: String) throws -> Data {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyMMddHHmmss'Z'"
        let now = Date()
        let name: (String) -> Data = { common in
            DER.sequence([
                DER.set([DER.sequence([DER.objectIdentifier(OID.userID), DER.utf8String(Self.teamID)])]),
                DER.set([DER.sequence([DER.objectIdentifier(OID.commonName), DER.utf8String(common)])]),
                DER.set([DER.sequence([DER.objectIdentifier(OID.organizationalUnitName), DER.utf8String(Self.teamID)])]),
                DER.set([DER.sequence([DER.objectIdentifier(OID.organizationName), DER.utf8String(Self.teamName)])]),
                DER.set([DER.sequence([DER.objectIdentifier(OID.countryName), DER.printableString("US")])]),
            ])
        }
        let tbs = DER.sequence([
            DER.explicit(0, DER.integer(2)),
            DER.integer(serial),
            DER.algorithm(OID.sha256WithRSAEncryption),
            DER.sequence([DER.set([DER.sequence([DER.objectIdentifier(OID.commonName), DER.utf8String("SignUtils Demo Authority")])])]),
            DER.sequence([
                DER.encode(tag: 0x17, content: Data(formatter.string(from: now.addingTimeInterval(-60)).utf8)),
                DER.encode(tag: 0x17, content: Data(formatter.string(from: now.addingTimeInterval(3.15e7)).utf8)),
            ]),
            name(commonName),
            publicKeyInfo,
        ])
        return DER.sequence([tbs, DER.algorithm(OID.sha256WithRSAEncryption), DER.bitString(try authority.sign(tbs))])
    }

    static func profileData(
        name: String, uuid: String, bundleIdentifier: String, certificates: [Data], devices: [String], debuggable: Bool,
        expiration: Date
    ) throws -> Data {
        var plist: [String: Any] = [
            "Name": name,
            "UUID": uuid,
            "AppIDName": name,
            "TeamIdentifier": [teamID],
            "TeamName": teamName,
            "CreationDate": Date(),
            "ExpirationDate": expiration,
            "DeveloperCertificates": certificates,
            "Platform": ["iOS"],
            "Entitlements": [
                "application-identifier": "\(teamID).\(bundleIdentifier)",
                "com.apple.developer.team-identifier": teamID,
                "get-task-allow": debuggable,
                "keychain-access-groups": ["\(teamID).*"],
            ],
        ]
        if !devices.isEmpty {
            plist["ProvisionedDevices"] = devices
        }
        let xml = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        return DER.sequence([DER.objectIdentifier("1.2.840.113549.1.7.2")]) + xml
    }
}
