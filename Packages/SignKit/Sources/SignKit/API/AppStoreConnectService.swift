import Foundation

public protocol AppStoreConnectService: Sendable {
    func certificates() async throws -> [Certificate]
    func certificate(id: String) async throws -> Certificate
    func createCertificate(type: CertificateType, csr: CertificateSigningRequest) async throws -> Certificate
    func revokeCertificate(id: String) async throws

    func bundleIDs() async throws -> [BundleID]
    func createBundleID(identifier: String, name: String, platform: BundleIDPlatform) async throws -> BundleID
    func deleteBundleID(id: String) async throws
    func capabilities(bundleID: String) async throws -> [BundleIDCapability]
    func enableCapability(_ type: CapabilityType, settings: [CapabilitySetting], bundleID: String) async throws
        -> BundleIDCapability
    func disableCapability(id: String) async throws

    func devices() async throws -> [Device]
    func registerDevice(name: String, udid: String, platform: BundleIDPlatform) async throws -> Device
    func updateDevice(id: String, name: String?, status: Device.Status?) async throws -> Device

    func profiles() async throws -> [Profile]
    func profile(id: String) async throws -> Profile
    func createProfile(
        name: String, type: ProfileType, bundleID: String, certificateIDs: [String], deviceIDs: [String]
    ) async throws -> Profile
    func deleteProfile(id: String) async throws
}

public struct AppStoreConnectError: Error, LocalizedError, Equatable, Sendable {
    public struct Item: Codable, Equatable, Sendable {
        public var status: String?
        public var code: String?
        public var title: String?
        public var detail: String?
    }

    public let statusCode: Int
    public let items: [Item]

    public init(statusCode: Int, items: [Item]) {
        self.statusCode = statusCode
        self.items = items
    }

    public var errorDescription: String? {
        let messages = items.compactMap { $0.detail ?? $0.title }
        if messages.isEmpty {
            return "App Store Connect returned HTTP \(statusCode)."
        }
        return messages.joined(separator: "\n")
    }

    public var isUnauthorized: Bool { statusCode == 401 }
    public var isForbidden: Bool { statusCode == 403 }
    public var isConflict: Bool { statusCode == 409 }
}
