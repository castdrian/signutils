import Foundation
import Testing

@testable import SignKit

final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [(GenerationStep, StepState)] = []

    func record(_ step: GenerationStep, _ state: StepState) {
        lock.withLock { storage.append((step, state)) }
    }

    var final: [GenerationStep: StepState] {
        lock.withLock { Dictionary(storage.map { ($0.0, $0.1) }, uniquingKeysWith: { $1 }) }
    }
}

@Suite("Generator")
struct GeneratorTests {
    @Test func generatesACompleteDevelopmentBundleWithNewAppIDAndDevice() async throws {
        let service = try DemoAppStoreConnect()
        let vault = PrivateKeyVault(store: MemoryStore())
        let generator = SigningGenerator(service: service, keys: vault, credentialsKeyID: "DEMOKEY123")
        let devices = try await service.devices().filter { $0.status == .enabled && $0.deviceClass == .iPhone }
        let request = SigningRequest(
            kind: .development,
            appID: .new(identifier: "com.demo.newapp", name: "New App"),
            capabilities: [.appGroups, .iCloud, .pushNotifications],
            devices: devices,
            newDevices: [NewDevice(name: "Friend’s iPhone", udid: "00008120-000A1B2C3D4E5F60")],
            certificate: .new(type: .development, commonName: "SignUtils"),
            password: "hunter2-hunter2",
            name: "New App Dev")
        let log = ProgressLog()
        let artifacts = try await generator.generate(request) { log.record($0, $1) }

        #expect(log.final.values.allSatisfy { if case .done = $0 { true } else { false } })
        #expect(artifacts.bundle.bundleIdentifier == "com.demo.newapp")
        #expect(artifacts.bundle.teamID == DemoAppStoreConnect.teamID)
        #expect(Set(artifacts.bundle.capabilities) == [.appGroups, .iCloud, .pushNotifications])
        #expect(artifacts.bundle.devices.count == devices.count + 1)
        #expect(artifacts.bundle.profileType == .iosAppDevelopment)

        let entries = try ZipArchive.read(artifacts.archive)
        #expect(
            Set(entries.map(\.path)) == [
                "New-App-Dev/New-App-Dev.p12", "New-App-Dev/New-App-Dev.mobileprovision", "New-App-Dev/password.txt",
                "New-App-Dev/certificate.cer", "New-App-Dev/info.json", "New-App-Dev/README.txt",
            ])
        let profile = try ProvisioningProfile(data: artifacts.profile)
        #expect(profile.contains(certificateDER: artifacts.certificate))
        #expect(profile.provisionedDevices.contains("00008120-000A1B2C3D4E5F60"))

        var items: CFArray?
        let status = SecPKCS12Import(
            artifacts.p12 as CFData, [kSecImportExportPassphrase: "hunter2-hunter2"] as CFDictionary, &items)
        #expect(status == errSecSuccess)

        let stored = try vault.certificateIDs()
        #expect(stored == [artifacts.bundle.certificateID])
        let registered = try await service.devices()
        #expect(registered.contains { $0.udid == "00008120-000A1B2C3D4E5F60" })
    }

    @Test func reusesAnExistingCertificateAndSyncsCapabilities() async throws {
        let service = try DemoAppStoreConnect()
        let vault = PrivateKeyVault(store: MemoryStore())
        let generator = SigningGenerator(service: service, keys: vault, credentialsKeyID: "DEMOKEY123")
        let fieldNotes = try await service.bundleIDs().first { $0.identifier == "com.demo.fieldnotes" }!
        let device = try await service.devices().first { $0.deviceClass == .iPad }!
        let first = try await generator.generate(
            SigningRequest(
                kind: .adHoc, appID: .existing(fieldNotes), capabilities: [.appGroups, .healthKit], devices: [device],
                certificate: .new(type: .distribution, commonName: "SignUtils"), password: "a", name: "Field Notes"))
        #expect(Set(first.bundle.capabilities) == [.appGroups, .healthKit])
        #expect(first.bundle.profileType == .iosAppAdHoc)

        let certificate = try await service.certificate(id: first.bundle.certificateID)
        let second = try await generator.generate(
            SigningRequest(
                kind: .adHoc, appID: .existing(fieldNotes), capabilities: [.appGroups, .healthKit], devices: [device],
                certificate: .existing(certificate), password: "b", name: "Field Notes"))
        #expect(second.bundle.certificateID == first.bundle.certificateID)
        #expect(second.bundle.profileID != first.bundle.profileID)
        #expect(try await service.certificates().filter { $0.certificateType == .distribution }.count == 2)
    }

    @Test func refusesCertificatesWithoutAStoredKey() async throws {
        let service = try DemoAppStoreConnect()
        let generator = SigningGenerator(
            service: service, keys: PrivateKeyVault(store: MemoryStore()), credentialsKeyID: "DEMOKEY123")
        let seeded = try await service.certificates().first { $0.certificateType == .development }!
        let device = try await service.devices().first!
        await #expect(throws: GenerationError.missingPrivateKey(seeded.displayName)) {
            try await generator.generate(
                SigningRequest(
                    kind: .development, appID: .new(identifier: "com.demo.x", name: "X"), devices: [device],
                    certificate: .existing(seeded), password: "a", name: "X"))
        }
    }

    @Test func revokesTheNewCertificateWhenProfileCreationFails() async throws {
        let service = try DemoAppStoreConnect()
        await service.setFailure { operation in
            operation == "createProfile"
                ? AppStoreConnectError(statusCode: 500, items: [.init(status: "500", code: nil, title: nil, detail: "Boom")])
                : nil
        }
        let vault = PrivateKeyVault(store: MemoryStore())
        let generator = SigningGenerator(service: service, keys: vault, credentialsKeyID: "DEMOKEY123")
        let before = try await service.certificates().count
        let device = try await service.devices().first!
        let log = ProgressLog()
        await #expect(throws: AppStoreConnectError.self) {
            try await generator.generate(
                SigningRequest(
                    kind: .development, appID: .new(identifier: "com.demo.fail", name: "Fail"), devices: [device],
                    certificate: .new(type: .development, commonName: "SignUtils"), password: "a", name: "Fail")
            ) { log.record($0, $1) }
        }
        #expect(try await service.certificates().count == before)
        #expect(try vault.certificateIDs().isEmpty)
        #expect(log.final[.profile] == .failed("Boom"))
    }

    @Test func wildcardAppIDsSkipCapabilities() async throws {
        let service = try DemoAppStoreConnect()
        let generator = SigningGenerator(
            service: service, keys: PrivateKeyVault(store: MemoryStore()), credentialsKeyID: "DEMOKEY123")
        let wildcard = try await service.bundleIDs().first { $0.isWildcard }!
        let device = try await service.devices().first!
        let log = ProgressLog()
        let artifacts = try await generator.generate(
            SigningRequest(
                kind: .development, appID: .existing(wildcard), capabilities: [.iCloud], devices: [device],
                certificate: .new(type: .development, commonName: "SignUtils"), password: "a", name: "Wild")
        ) { log.record($0, $1) }
        #expect(artifacts.bundle.capabilities.isEmpty)
        #expect(log.final[.capabilities] == .skipped("Wildcard App IDs cannot have capabilities"))
    }

    @Test func existingIdentifiersAreReusedWhenRegistrationConflicts() async throws {
        let service = try DemoAppStoreConnect()
        let generator = SigningGenerator(
            service: service, keys: PrivateKeyVault(store: MemoryStore()), credentialsKeyID: "DEMOKEY123")
        let device = try await service.devices().first!
        let artifacts = try await generator.generate(
            SigningRequest(
                kind: .development, appID: .new(identifier: "com.demo.fieldnotes", name: "Field Notes"), capabilities: [.appGroups],
                devices: [device], certificate: .new(type: .development, commonName: "SignUtils"), password: "a",
                name: "Field Notes"))
        #expect(artifacts.bundle.bundleIDResource == "BID1")
    }

    @Test func validationCatchesBadInput() throws {
        let generator = SigningGenerator(
            service: try DemoAppStoreConnect(), keys: PrivateKeyVault(store: MemoryStore()), credentialsKeyID: "X")
        #expect(throws: GenerationError.noDevices) {
            try generator.validate(
                SigningRequest(
                    kind: .development, appID: .new(identifier: "com.a.b", name: "B"),
                    certificate: .new(type: .development, commonName: "X"), password: "", name: "B"))
        }
        #expect(throws: GenerationError.invalidUDID("bad")) {
            try generator.validate(
                SigningRequest(
                    kind: .development, appID: .new(identifier: "com.a.b", name: "B"),
                    newDevices: [NewDevice(name: "x", udid: "bad")], certificate: .new(type: .development, commonName: "X"),
                    password: "", name: "B"))
        }
        #expect(throws: GenerationError.invalidBundleIdentifier("nope")) {
            try generator.validate(
                SigningRequest(
                    kind: .development, appID: .new(identifier: "nope", name: "B"),
                    newDevices: [NewDevice(name: "x", udid: "00008120-000A1B2C3D4E5F60")],
                    certificate: .new(type: .development, commonName: "X"), password: "", name: "B"))
        }
    }

    @Test func revokingInvalidatesProfiles() async throws {
        let service = try DemoAppStoreConnect()
        let generator = SigningGenerator(
            service: service, keys: PrivateKeyVault(store: MemoryStore()), credentialsKeyID: "DEMOKEY123")
        let device = try await service.devices().first!
        let artifacts = try await generator.generate(
            SigningRequest(
                kind: .development, appID: .new(identifier: "com.demo.rev", name: "Rev"), devices: [device],
                certificate: .new(type: .development, commonName: "SignUtils"), password: "a", name: "Rev"))
        try await service.revokeCertificate(id: artifacts.bundle.certificateID)
        let profile = try await service.profile(id: artifacts.bundle.profileID)
        #expect(profile.state == .invalid)
    }
}
