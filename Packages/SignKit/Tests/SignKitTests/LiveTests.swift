import Foundation
import Testing

@testable import SignKit

enum LiveEnvironment {
    static let environment = ProcessInfo.processInfo.environment

    static func value(_ name: String) -> String? {
        if let value = environment[name], !value.isEmpty { return value }
        guard let directory = environment["SIGNUTILS_E2E_DIR"] else { return nil }
        return try? String(contentsOfFile: "\(directory)/\(name)", encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static var credentials: APICredentials? {
        guard let keyID = value("APP_STORE_CONNECT_KEY_ID"), let issuerID = value("APP_STORE_CONNECT_ISSUER_ID"),
            let key = value("APP_STORE_CONNECT_PRIVATE_KEY_BASE64")
        else { return nil }
        return APICredentials(name: "E2E", keyID: keyID, issuerID: issuerID, privateKeyPEM: key)
    }

    static var isEnabled: Bool { environment["SIGNUTILS_E2E"] == "1" && credentials != nil }
    static var includesAdHoc: Bool { environment["SIGNUTILS_E2E_ADHOC"] == "1" }
}

@Suite("Live App Store Connect", .serialized, .enabled(if: LiveEnvironment.isEnabled))
struct LiveTests {
    let client: AppStoreConnectClient

    init() throws {
        let credentials = try #require(LiveEnvironment.credentials)
        try credentials.validate()
        client = AppStoreConnectClient(credentials: credentials)
    }

    @Test func readsTheTeam() async throws {
        let devices = try await client.devices()
        let certificates = try await client.certificates()
        let bundleIDs = try await client.bundleIDs()
        let profiles = try await client.profiles()
        #expect(!devices.isEmpty)
        #expect(!certificates.isEmpty)
        #expect(!bundleIDs.isEmpty)
        print("Live team: \(devices.count) devices, \(certificates.count) certificates, \(bundleIDs.count) App IDs, \(profiles.count) profiles")
    }

    @Test func generatesInstallableSigningAssetsAndRevokesThem() async throws {
        try await runFlow(kind: .development, certificateType: .development)
    }

    @Test(.enabled(if: LiveEnvironment.includesAdHoc))
    func generatesAdHocSigningAssetsAndRevokesThem() async throws {
        try await runFlow(kind: .adHoc, certificateType: .distribution)
    }

    private func runFlow(kind: SigningKind, certificateType: CertificateType) async throws {
        let device = try #require(
            try await client.devices().first {
                $0.status == .enabled && $0.platform == .ios && $0.deviceClass == .iPhone
            })
        let stamp = Int(Date().timeIntervalSince1970)
        let identifier = "dev.adrian.signtools.e2e\(kind == .development ? "dev" : "adhoc")\(stamp)"
        let vault = PrivateKeyVault(store: MemoryStore())
        let generator = SigningGenerator(service: client, keys: vault, credentialsKeyID: "E2E")
        let password = Passwords.generate()
        let capabilities: Set<CapabilityType> = [.appGroups, .associatedDomains, .iCloud, .pushNotifications]
        let log = ProgressLog()

        var artifacts: SigningArtifacts?
        var reusedProfileID: String?
        do {
            let generated = try await generator.generate(
                SigningRequest(
                    kind: kind,
                    appID: .new(identifier: identifier, name: "SignUtils E2E \(stamp)"),
                    capabilities: capabilities,
                    devices: [device],
                    certificate: .new(type: certificateType, commonName: "SignUtils E2E"),
                    password: password,
                    name: "SignUtils E2E \(kind.title) \(stamp)")
            ) { step, state in
                log.record(step, state)
                print("[\(step.title)] \(state)")
            }
            artifacts = generated

            let bundle = generated.bundle
            #expect(bundle.bundleIdentifier == identifier)
            #expect(bundle.certificateType == certificateType)
            #expect(bundle.profileType == kind.profileType(for: .iOS))
            #expect(Set(bundle.capabilities).isSuperset(of: capabilities))
            #expect(bundle.teamID.count == 10)

            let remoteCapabilities = Set(try await client.capabilities(bundleID: bundle.bundleIDResource).map(\.capabilityType))
            #expect(remoteCapabilities.isSuperset(of: capabilities))

            let profile = try ProvisioningProfile(data: generated.profile)
            #expect(profile.bundleIdentifier == identifier)
            #expect(profile.provisionedDevices.map { $0.uppercased() }.contains(device.udid.uppercased()))
            #expect(profile.contains(certificateDER: generated.certificate))
            #expect(profile.isDebuggable == (kind == .development))
            #expect(profile.entitlementKeys.contains("com.apple.security.application-groups"))
            #expect(profile.entitlementKeys.contains("aps-environment"))
            #expect(profile.entitlementKeys.contains("com.apple.developer.associated-domains"))
            #expect(profile.entitlementKeys.contains("com.apple.developer.icloud-container-identifiers"))

            let info = try CertificateInfo(der: generated.certificate)
            #expect(info.commonName.hasPrefix(certificateType == .development ? "Apple Development" : "Apple Distribution"))
            #expect(info.organizationalUnit == bundle.teamID)

            var items: CFArray?
            let status = SecPKCS12Import(
                generated.p12 as CFData, [kSecImportExportPassphrase: password] as CFDictionary, &items)
            #expect(status == errSecSuccess)

            let directory = try temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let zipURL = directory.appendingPathComponent(bundle.fileName)
            try generated.archive.write(to: zipURL)
            #expect(try run("/usr/bin/unzip", ["-t", zipURL.path]).status == 0)
            let p12URL = directory.appendingPathComponent("bundle.p12")
            try generated.p12.write(to: p12URL)
            let dump = try run(openssl(), ["pkcs12", "-in", p12URL.path, "-nodes", "-passin", "pass:\(password)"])
            #expect(dump.status == 0, "\(dump.output)")
            #expect(dump.output.contains(info.commonName))

            let reuse = try await generator.generate(
                SigningRequest(
                    kind: kind, appID: .existing(BundleID(
                        id: bundle.bundleIDResource, identifier: identifier, name: "", platform: .universal, seedID: nil)),
                    capabilities: [.appGroups], devices: [device],
                    certificate: .existing(try await client.certificate(id: bundle.certificateID)),
                    password: password, name: "SignUtils E2E Reuse \(stamp)"))
            reusedProfileID = reuse.bundle.profileID
            #expect(reuse.bundle.certificateID == bundle.certificateID)
            #expect(Set(try await client.capabilities(bundleID: bundle.bundleIDResource).map(\.capabilityType)).contains(.iCloud) == false)
        } catch {
            await cleanUp(artifacts: artifacts, extraProfile: reusedProfileID, identifier: identifier)
            throw error
        }
        await cleanUp(artifacts: artifacts, extraProfile: reusedProfileID, identifier: identifier)

        if let bundle = artifacts?.bundle {
            let certificates = try await client.certificates()
            #expect(!certificates.contains { $0.id == bundle.certificateID })
            let profiles = try await client.profiles()
            #expect(!profiles.contains { $0.id == bundle.profileID })
            let bundleIDs = try await client.bundleIDs()
            #expect(!bundleIDs.contains { $0.identifier == identifier })
        }
    }

    private func cleanUp(artifacts: SigningArtifacts?, extraProfile: String?, identifier: String) async {
        if let extraProfile {
            await attempt("delete profile \(extraProfile)") { try await client.deleteProfile(id: extraProfile) }
        }
        if let bundle = artifacts?.bundle {
            await attempt("delete profile \(bundle.profileID)") { try await client.deleteProfile(id: bundle.profileID) }
            await attempt("revoke certificate \(bundle.certificateID)") {
                try await client.revokeCertificate(id: bundle.certificateID)
            }
        }
        if let created = try? await client.bundleIDs().first(where: { $0.identifier == identifier }) {
            await attempt("delete App ID \(identifier)") { try await client.deleteBundleID(id: created.id) }
        }
    }

    private func attempt(_ label: String, _ operation: () async throws -> Void) async {
        do {
            try await operation()
            print("Cleaned up: \(label)")
        } catch {
            Issue.record("Cleanup failed (\(label)): \(error.localizedDescription)")
        }
    }
}
