import Foundation
import Observation
import SignKit
import SwiftUI

@MainActor
@Observable
final class AppModel {
    enum Mode: Equatable {
        case live
        case demo
    }

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded(Date)
        case failed(String)
    }

    struct LaunchOptions {
        var demo = false
        var screenshots = false
        var uiTesting = false

        static var current: LaunchOptions {
            let arguments = ProcessInfo.processInfo.arguments
            return LaunchOptions(
                demo: arguments.contains("-demo"),
                screenshots: arguments.contains("-screenshots"),
                uiTesting: arguments.contains("-uiTesting"))
        }
    }

    private(set) var mode: Mode = .live
    private(set) var accounts: [APICredentials] = []
    private(set) var activeKeyID: String?
    private(set) var service: AppStoreConnectService?
    private(set) var library: SigningLibrary?
    private(set) var keys: PrivateKeyVault
    private let credentialVault: CredentialVault
    private let launchOptions: LaunchOptions
    private let demoStore = MemoryStore()

    var certificates: [Certificate] = []
    var bundleIDs: [BundleID] = []
    var devices: [Device] = []
    var profiles: [Profile] = []
    var entries: [LibraryEntry] = []
    var keyedCertificateIDs: Set<String> = []
    var loadState: LoadState = .idle
    var toast: Toast?
    var isCreating = false
    var selection: SidebarItem = .library

    var hasAccount: Bool { service != nil }
    var isDemo: Bool { mode == .demo }
    var activeAccount: APICredentials? { accounts.first { $0.keyID == activeKeyID } }
    var accountName: String { isDemo ? DemoAppStoreConnect.teamName : activeAccount?.name ?? "" }

    init(launchOptions: LaunchOptions, keychainService: String) {
        self.launchOptions = launchOptions
        let store: SecureStore = launchOptions.uiTesting ? MemoryStore() : KeychainStore(service: keychainService)
        self.credentialVault = CredentialVault(store: store)
        self.keys = PrivateKeyVault(store: store)
    }

    static func launch() -> AppModel {
        AppModel(launchOptions: .current, keychainService: "dev.adrian.signtools")
    }

    func start() async {
        guard service == nil else { return }
        if launchOptions.demo || launchOptions.screenshots {
            await enterDemo(seedLibrary: launchOptions.screenshots)
            return
        }
        do {
            accounts = try credentialVault.all().sorted { $0.name < $1.name }
        } catch {
            show(error)
        }
        let stored = UserDefaults.standard.string(forKey: "activeKeyID")
        if let account = accounts.first(where: { $0.keyID == stored }) ?? accounts.first {
            await activate(account)
        }
    }

    func activate(_ account: APICredentials) async {
        mode = .live
        activeKeyID = account.keyID
        UserDefaults.standard.set(account.keyID, forKey: "activeKeyID")
        service = AppStoreConnectClient(credentials: account)
        keys = PrivateKeyVault(store: launchOptions.uiTesting ? demoStore : KeychainStore(service: "dev.adrian.signtools"))
        openLibrary(directory: libraryDirectory(named: "Library"))
        clearRemoteData()
        await refresh()
    }

    func enterDemo(seedLibrary: Bool = false) async {
        do {
            let latency: Duration = launchOptions.screenshots ? .zero : .milliseconds(350)
            let demo = try await Task.detached(priority: .userInitiated) { try DemoAppStoreConnect(latency: latency) }.value
            mode = .demo
            activeKeyID = nil
            service = demo
            keys = PrivateKeyVault(store: demoStore)
            let directory = libraryDirectory(named: "DemoLibrary")
            try? FileManager.default.removeItem(at: directory)
            openLibrary(directory: directory)
            clearRemoteData()
            if seedLibrary {
                await seedDemoLibrary(demo)
            }
            await refresh()
        } catch {
            show(error)
        }
    }

    func leaveDemo() async {
        service = nil
        library = nil
        clearRemoteData()
        entries = []
        mode = .live
        if let account = accounts.first {
            await activate(account)
        }
    }

    func addAccount(_ credentials: APICredentials) async throws {
        try credentials.validate()
        let client = AppStoreConnectClient(credentials: credentials)
        _ = try await client.devices()
        try credentialVault.upsert(credentials)
        accounts = try credentialVault.all().sorted { $0.name < $1.name }
        await activate(credentials)
        toast = Toast("Connected to \(credentials.name)", symbol: "checkmark.circle.fill")
    }

    func removeAccount(_ credentials: APICredentials) async {
        do {
            try credentialVault.remove(keyID: credentials.keyID)
            accounts = try credentialVault.all().sorted { $0.name < $1.name }
            if activeKeyID == credentials.keyID {
                service = nil
                library = nil
                activeKeyID = nil
                clearRemoteData()
                entries = []
                if let next = accounts.first {
                    await activate(next)
                }
            }
        } catch {
            show(error)
        }
    }

    func refresh() async {
        guard let service else { return }
        loadState = .loading
        do {
            async let certificates = service.certificates()
            async let bundleIDs = service.bundleIDs()
            async let devices = service.devices()
            async let profiles = service.profiles()
            let loaded = try await (certificates, bundleIDs, devices, profiles)
            self.certificates = loaded.0.sorted { ($0.expirationDate ?? .distantPast) > ($1.expirationDate ?? .distantPast) }
            self.bundleIDs = loaded.1
            self.devices = loaded.2
            self.profiles = loaded.3.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            keyedCertificateIDs = (try? keys.certificateIDs()) ?? []
            updateLibraryStatuses()
            loadState = .loaded(Date())
        } catch {
            loadState = .failed(error.localizedDescription)
            reloadLibrary()
        }
    }

    func generator() -> SigningGenerator? {
        guard let service else { return nil }
        return SigningGenerator(service: service, keys: keys, credentialsKeyID: activeKeyID ?? "DEMO")
    }

    func store(_ artifacts: SigningArtifacts) throws -> LibraryEntry {
        guard let library else { throw CocoaError(.fileNoSuchFile) }
        let entry = try library.add(artifacts)
        reloadLibrary()
        keyedCertificateIDs = (try? keys.certificateIDs()) ?? keyedCertificateIDs
        return entry
    }

    func archiveURL(for entry: LibraryEntry) -> URL? {
        library?.archiveURL(for: entry)
    }

    func contents(of entry: LibraryEntry) -> [ZipEntry] {
        (try? library?.contents(of: entry)) ?? []
    }

    func removeFromLibrary(_ entry: LibraryEntry) {
        do {
            try library?.remove(id: entry.id)
            reloadLibrary()
        } catch {
            show(error)
        }
    }

    func revoke(_ entry: LibraryEntry, certificate: Bool, profile: Bool) async {
        guard let service else { return }
        do {
            if profile, profiles.contains(where: { $0.id == entry.bundle.profileID }) {
                try await service.deleteProfile(id: entry.bundle.profileID)
            }
            if certificate, certificates.contains(where: { $0.id == entry.bundle.certificateID }) {
                try await service.revokeCertificate(id: entry.bundle.certificateID)
                try? keys.remove(certificateID: entry.bundle.certificateID)
            }
            var updated = entry
            updated.status = certificate ? .revoked : .profileDeleted
            try library?.update(updated)
            toast = Toast(certificate ? "Certificate revoked" : "Profile deleted", symbol: "xmark.seal.fill")
            await refresh()
        } catch {
            show(error)
            await refresh()
        }
    }

    func revokeCertificate(_ certificate: Certificate) async {
        await perform("Revoked \(certificate.certificateType.displayName)", symbol: "xmark.seal.fill") { service in
            try await service.revokeCertificate(id: certificate.id)
            try? self.keys.remove(certificateID: certificate.id)
        }
    }

    func deleteProfile(_ profile: Profile) async {
        await perform("Deleted \(profile.name)", symbol: "trash.fill") { service in
            try await service.deleteProfile(id: profile.id)
        }
    }

    func deleteBundleID(_ bundleID: BundleID) async {
        await perform("Deleted \(bundleID.identifier)", symbol: "trash.fill") { service in
            try await service.deleteBundleID(id: bundleID.id)
        }
    }

    func createBundleID(identifier: String, name: String, platform: BundleIDPlatform) async -> BundleID? {
        guard let service else { return nil }
        do {
            let created = try await service.createBundleID(
                identifier: identifier, name: BundleIdentifier.apiName(name), platform: platform)
            toast = Toast("Registered \(identifier)", symbol: "checkmark.circle.fill")
            await refresh()
            return created
        } catch {
            show(error)
            return nil
        }
    }

    func capabilities(for bundleID: BundleID) async -> [BundleIDCapability] {
        guard let service else { return [] }
        do {
            return try await service.capabilities(bundleID: bundleID.id)
        } catch {
            show(error)
            return []
        }
    }

    func setCapability(_ type: CapabilityType, enabled: Bool, bundleID: BundleID, current: [BundleIDCapability]) async
        -> [BundleIDCapability]
    {
        guard let service else { return current }
        do {
            if enabled {
                let capability = try await service.enableCapability(type, settings: type.defaultSettings, bundleID: bundleID.id)
                return current.filter { $0.capabilityType != type } + [capability]
            }
            if let existing = current.first(where: { $0.capabilityType == type }) {
                try await service.disableCapability(id: existing.id)
            }
            return current.filter { $0.capabilityType != type }
        } catch {
            show(error)
            return current
        }
    }

    func registerDevice(name: String, udid: String) async -> Device? {
        guard let service else { return nil }
        do {
            let device = try await service.registerDevice(name: name, udid: UDID.normalize(udid), platform: .ios)
            toast = Toast("Registered \(name)", symbol: "checkmark.circle.fill")
            await refresh()
            return device
        } catch {
            show(error)
            return nil
        }
    }

    func setDevice(_ device: Device, enabled: Bool) async {
        await perform(enabled ? "Enabled \(device.name)" : "Disabled \(device.name)", symbol: "iphone") { service in
            _ = try await service.updateDevice(id: device.id, name: nil, status: enabled ? .enabled : .disabled)
        }
    }

    func rename(_ device: Device, to name: String) async {
        await perform("Renamed to \(name)", symbol: "pencil") { service in
            _ = try await service.updateDevice(id: device.id, name: name, status: nil)
        }
    }

    func profileContent(_ profile: Profile) async -> Data? {
        guard let service else { return nil }
        do {
            return try await service.profile(id: profile.id).content
        } catch {
            show(error)
            return nil
        }
    }

    func show(_ error: Error) {
        toast = Toast(error.localizedDescription, symbol: "exclamationmark.triangle.fill", isError: true)
    }

    func bundleID(id: String?) -> BundleID? {
        bundleIDs.first { $0.id == id }
    }

    func entries(forCertificate id: String) -> [LibraryEntry] {
        entries.filter { $0.bundle.certificateID == id }
    }

    private func perform(_ message: String, symbol: String, _ operation: (AppStoreConnectService) async throws -> Void) async {
        guard let service else { return }
        do {
            try await operation(service)
            toast = Toast(message, symbol: symbol)
        } catch {
            show(error)
        }
        await refresh()
    }

    private func clearRemoteData() {
        certificates = []
        bundleIDs = []
        devices = []
        profiles = []
        loadState = .idle
    }

    private func libraryDirectory(named name: String) -> URL {
        if launchOptions.uiTesting {
            return FileManager.default.temporaryDirectory.appendingPathComponent("SignUtils-UITests/\(name)")
        }
        return SigningLibrary.defaultDirectory().deletingLastPathComponent().appendingPathComponent(name)
    }

    private func openLibrary(directory: URL) {
        do {
            library = try SigningLibrary(directory: directory)
            reloadLibrary()
        } catch {
            show(error)
        }
    }

    private func reloadLibrary() {
        let keyID = isDemo ? "DEMO" : activeKeyID
        entries = ((try? library?.entries()) ?? []).filter { $0.bundle.credentialsKeyID == keyID }
    }

    private func updateLibraryStatuses() {
        guard let library else { return }
        let keyID = isDemo ? "DEMO" : activeKeyID
        let certificateIDs = Set(certificates.map(\.id))
        let profileStates = Dictionary(profiles.map { ($0.id, $0.state) }, uniquingKeysWith: { first, _ in first })
        _ = try? library.updateStatuses { entry in
            guard entry.bundle.credentialsKeyID == keyID else { return nil }
            let certificateGone = !certificateIDs.contains(entry.bundle.certificateID)
            let profileState = profileStates[entry.bundle.profileID]
            switch (certificateGone, profileState) {
            case (true, nil): return .revoked
            case (true, _): return .certificateRevoked
            case (false, nil): return .profileDeleted
            case (false, .invalid): return .profileInvalid
            default: return .active
            }
        }
        reloadLibrary()
    }

    private func seedDemoLibrary(_ demo: DemoAppStoreConnect) async {
        let generator = SigningGenerator(service: demo, keys: keys, credentialsKeyID: "DEMO")
        guard let devices = try? await demo.devices(), let bundleIDs = try? await demo.bundleIDs() else { return }
        let phones = devices.filter { $0.status == .enabled && $0.deviceClass != .appleTV }
        let plans: [(String, SigningKind, String, Set<CapabilityType>)] = [
            ("Field Notes", .development, "com.demo.fieldnotes", [.appGroups, .associatedDomains, .networkExtensions]),
            ("Pixel Studio Ad Hoc", .adHoc, "com.demo.pixelstudio", [.gameCenter, .iCloud]),
            ("Music Player", .development, "com.demo.music", [.pushNotifications, .appGroups]),
        ]
        for (index, plan) in plans.enumerated() {
            guard let bundleID = bundleIDs.first(where: { $0.identifier == plan.2 }) else { continue }
            let request = SigningRequest(
                kind: plan.1, appID: .existing(bundleID), capabilities: plan.3,
                devices: index == 2 ? Array(phones.prefix(1)) : phones,
                certificate: .new(type: plan.1 == .development ? .development : .distribution, commonName: "SignUtils"),
                password: Passwords.generate(), name: plan.0)
            if var artifacts = try? await generator.generate(request) {
                artifacts.bundle.createdAt = Date().addingTimeInterval(TimeInterval(-86_400 * (index * 3 + 1)))
                _ = try? library?.add(artifacts)
            }
        }
        reloadLibrary()
    }
}

struct Toast: Equatable, Identifiable {
    let id = UUID()
    var message: String
    var symbol: String
    var isError = false

    init(_ message: String, symbol: String, isError: Bool = false) {
        self.message = message
        self.symbol = symbol
        self.isError = isError
    }
}

enum SidebarItem: String, Hashable, CaseIterable, Identifiable {
    case library
    case certificates
    case profiles
    case appIDs
    case devices
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .library: "Library"
        case .certificates: "Certificates"
        case .profiles: "Profiles"
        case .appIDs: "App IDs"
        case .devices: "Devices"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .library: "tray.full"
        case .certificates: "checkmark.seal"
        case .profiles: "doc.badge.gearshape"
        case .appIDs: "app.badge"
        case .devices: "iphone.gen3"
        case .settings: "gearshape"
        }
    }
}
