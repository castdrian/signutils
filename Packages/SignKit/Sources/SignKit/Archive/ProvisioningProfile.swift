import Foundation

public struct ProvisioningProfile: Sendable, Equatable {
    public let name: String
    public let uuid: String
    public let teamIdentifier: String
    public let teamName: String
    public let appIDName: String
    public let applicationIdentifier: String
    public let creationDate: Date
    public let expirationDate: Date
    public let provisionedDevices: [String]
    public let developerCertificates: [Data]
    public let entitlementKeys: [String]
    public let isDebuggable: Bool

    public var bundleIdentifier: String {
        guard let dot = applicationIdentifier.firstIndex(of: ".") else { return applicationIdentifier }
        return String(applicationIdentifier[applicationIdentifier.index(after: dot)...])
    }

    public init(data: Data) throws {
        guard let start = data.range(of: Data("<?xml".utf8)),
            let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex)
        else {
            throw ProfileError.notAProvisioningProfile
        }
        let plistData = data.subdata(in: start.lowerBound..<end.upperBound)
        guard
            let plist = try PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any]
        else {
            throw ProfileError.notAProvisioningProfile
        }
        let entitlements = plist["Entitlements"] as? [String: Any] ?? [:]
        name = plist["Name"] as? String ?? ""
        uuid = plist["UUID"] as? String ?? ""
        teamIdentifier = (plist["TeamIdentifier"] as? [String])?.first ?? ""
        teamName = plist["TeamName"] as? String ?? ""
        appIDName = plist["AppIDName"] as? String ?? ""
        applicationIdentifier =
            entitlements["application-identifier"] as? String ?? entitlements["com.apple.application-identifier"]
            as? String ?? ""
        creationDate = plist["CreationDate"] as? Date ?? Date(timeIntervalSince1970: 0)
        expirationDate = plist["ExpirationDate"] as? Date ?? Date(timeIntervalSince1970: 0)
        provisionedDevices = plist["ProvisionedDevices"] as? [String] ?? []
        developerCertificates = plist["DeveloperCertificates"] as? [Data] ?? []
        entitlementKeys = entitlements.keys.sorted()
        isDebuggable = entitlements["get-task-allow"] as? Bool ?? false
    }

    public func contains(certificateDER: Data) -> Bool {
        developerCertificates.contains(certificateDER)
    }
}

public enum ProfileError: Error, Equatable, LocalizedError {
    case notAProvisioningProfile

    public var errorDescription: String? {
        "The file is not a provisioning profile."
    }
}
