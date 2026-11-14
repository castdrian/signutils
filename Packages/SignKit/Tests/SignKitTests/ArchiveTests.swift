import Foundation
import Testing

@testable import SignKit

@Suite("Archives and profiles")
struct ArchiveTests {
    @Test func zipRoundTripsAndPassesUnzip() throws {
        let entries = [
            ZipEntry(path: "bundle/a.txt", data: Data(String(repeating: "hello ", count: 500).utf8)),
            ZipEntry(path: "bundle/random.bin", data: PKCS12.randomBytes(4096)),
            ZipEntry(path: "bundle/empty.txt", data: Data()),
        ]
        let archive = try ZipArchive.make(entries)
        let read = try ZipArchive.read(archive)
        #expect(read.map(\.path) == entries.map(\.path))
        #expect(read.map(\.data) == entries.map(\.data))

        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("test.zip")
        try archive.write(to: url)
        let check = try run("/usr/bin/unzip", ["-t", url.path])
        #expect(check.status == 0, "\(check.output)")
        #expect(check.output.contains("No errors detected"))
        let ditto = try run("/usr/bin/ditto", ["-x", "-k", url.path, directory.appendingPathComponent("out").path])
        #expect(ditto.status == 0, "\(ditto.output)")
        #expect(
            try Data(contentsOf: directory.appendingPathComponent("out/bundle/random.bin")) == entries[1].data)
    }

    @Test func crcMatchesKnownValue() {
        #expect(CRC32.checksum(Data("123456789".utf8)) == 0xCBF4_3926)
    }

    @Test func readingGarbageThrows() {
        #expect(throws: ZipError.notAZipArchive) { try ZipArchive.read(Data(repeating: 1, count: 100)) }
    }

    @Test func provisioningProfileIsParsed() throws {
        let certificate = Data([1, 2, 3])
        let data = try sampleProfile(
            certificates: [certificate], devices: ["00008110-000A1C2E3C01801E"], bundleID: "dev.example.app")
        let profile = try ProvisioningProfile(data: data)
        #expect(profile.name == "Sample Profile")
        #expect(profile.teamIdentifier == "TEAMID1234")
        #expect(profile.bundleIdentifier == "dev.example.app")
        #expect(profile.provisionedDevices == ["00008110-000A1C2E3C01801E"])
        #expect(profile.contains(certificateDER: certificate))
        #expect(profile.isDebuggable)
        #expect(throws: ProfileError.notAProvisioningProfile) { try ProvisioningProfile(data: Data("nope".utf8)) }
    }

    @Test func validatorsAcceptRealWorldValues() {
        #expect(UDID.isValid("00008110-000A1C2E3C01801E"))
        #expect(UDID.isValid(" 00008110-000a1c2e3c01801e\n"))
        #expect(UDID.isValid(String(repeating: "a", count: 40)))
        #expect(!UDID.isValid("00008110000A1C2E3C01801E"))
        #expect(!UDID.isValid("not a udid"))
        #expect(BundleIdentifier.isValid("dev.adrian.signtools"))
        #expect(BundleIdentifier.isValid("com.example.*"))
        #expect(!BundleIdentifier.isValid("com.*.example"))
        #expect(!BundleIdentifier.isValid("single"))
        #expect(!BundleIdentifier.isValid("com.exa mple"))
        #expect(BundleIdentifier.suggestedName(for: "com.example.my-app") == "My app")
        #expect(BundleIdentifier.apiName("Field Notes (beta) #1") == "Field Notes beta 1")
        #expect(SigningBundle.slug("My App / Dev") == "My-App-Dev")
        #expect(Passwords.generate().count == 20)
    }
}

@Suite("Library")
struct LibraryTests {
    @Test func storesListsAndRemovesArchives() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = try SigningLibrary(directory: directory)
        let bundle = Fixtures.bundle(name: "First")
        let archive = try ZipArchive.make([ZipEntry(path: "x/info.json", data: Data("{}".utf8))])
        try library.add(
            SigningArtifacts(bundle: bundle, archive: archive, p12: Data(), profile: Data(), certificate: Data()))
        var second = Fixtures.bundle(name: "Second")
        second.createdAt = bundle.createdAt.addingTimeInterval(60)
        try library.add(
            SigningArtifacts(bundle: second, archive: archive, p12: Data(), profile: Data(), certificate: Data()))

        let reopened = try SigningLibrary(directory: directory)
        let entries = try reopened.entries()
        #expect(entries.map(\.bundle.name) == ["Second", "First"])
        #expect(try reopened.contents(of: entries[0]).first?.path == "x/info.json")

        let updated = try reopened.updateStatuses { $0.bundle.name == "First" ? .certificateRevoked : nil }
        #expect(updated.first { $0.bundle.name == "First" }?.status == .certificateRevoked)
        #expect(updated.allSatisfy { $0.checkedAt != nil })

        try reopened.remove(id: bundle.id)
        #expect(try reopened.entries().map(\.bundle.name) == ["Second"])
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(bundle.fileName).path))
    }

    @Test func expiredEntriesReportExpired() {
        var bundle = Fixtures.bundle(name: "Old")
        bundle.profileExpiration = Date(timeIntervalSinceNow: -10)
        #expect(LibraryEntry(bundle: bundle).effectiveStatus() == .expired)
        #expect(LibraryEntry(bundle: bundle, status: .revoked).effectiveStatus() == .revoked)
    }

    @Test func vaultsPersistKeysAndCredentials() throws {
        let store = MemoryStore()
        let keys = PrivateKeyVault(store: store)
        let keyPair = try RSAKeyPair.generate()
        try keys.save(keyPair, certificateID: "CERT1")
        #expect(try keys.keyPair(certificateID: "CERT1")?.publicKeyPKCS1 == keyPair.publicKeyPKCS1)
        #expect(try keys.certificateIDs() == ["CERT1"])
        try keys.remove(certificateID: "CERT1")
        #expect(try keys.keyPair(certificateID: "CERT1") == nil)

        let credentials = CredentialVault(store: store)
        let first = APICredentials(name: "A", keyID: "AAAAAAAAAA", issuerID: UUID().uuidString, privateKeyPEM: "x")
        try credentials.upsert(first)
        try credentials.upsert(APICredentials(name: "Renamed", keyID: "AAAAAAAAAA", issuerID: first.issuerID, privateKeyPEM: "x"))
        #expect(try credentials.all().map(\.name) == ["Renamed"])
        try credentials.remove(keyID: "AAAAAAAAAA")
        #expect(try credentials.all().isEmpty)
    }
}

enum Fixtures {
    static func bundle(name: String) -> SigningBundle {
        SigningBundle(
            name: name, kind: .development, platform: .iOS, teamID: "TEAMID1234", teamName: "Team",
            bundleIdentifier: "dev.example.app", bundleIDResource: "B1", capabilities: [.appGroups],
            devices: [.init(name: "iPhone", udid: "00008110-000A1C2E3C01801E", deviceClass: .iPhone)],
            certificateID: "C1", certificateType: .development, certificateName: "Apple Development: Test",
            certificateSerial: "01", certificateExpiration: Date(timeIntervalSinceNow: 86_400 * 300),
            profileID: "P1", profileUUID: "U1", profileName: name, profileType: .iosAppDevelopment,
            profileExpiration: Date(timeIntervalSinceNow: 86_400 * 300), password: "pw",
            fileName: "\(name)-\(UUID().uuidString.prefix(8)).zip", credentialsKeyID: "AAAAAAAAAA")
    }
}
