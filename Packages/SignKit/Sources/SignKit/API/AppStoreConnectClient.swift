import Foundation

public final class AppStoreConnectClient: AppStoreConnectService, @unchecked Sendable {
    public static let defaultBaseURL = URL(string: "https://api.appstoreconnect.apple.com")!

    private let credentials: APICredentials
    private let session: URLSession
    private let baseURL: URL
    private let tokenLock = NSLock()
    private var cachedToken: (value: String, expiry: Date)?

    public init(credentials: APICredentials, session: URLSession = .shared, baseURL: URL = defaultBaseURL) {
        self.credentials = credentials
        self.session = session
        self.baseURL = baseURL
    }

    public func certificates() async throws -> [Certificate] {
        let resources: [Resource<CertificateAttributes>] = try await all(
            "/v1/certificates", query: ["limit": "200", "sort": "-id"])
        return resources.map(Self.certificate)
    }

    public func certificate(id: String) async throws -> Certificate {
        let document: Document<Resource<CertificateAttributes>> = try await send("GET", "/v1/certificates/\(id)")
        return Self.certificate(document.data)
    }

    public func createCertificate(type: CertificateType, csr: CertificateSigningRequest) async throws -> Certificate {
        let body = Body(
            type: "certificates",
            attributes: ["certificateType": .string(type.rawValue), "csrContent": .string(csr.der.base64EncodedString())])
        let document: Document<Resource<CertificateAttributes>> = try await send("POST", "/v1/certificates", body: body)
        return Self.certificate(document.data)
    }

    public func revokeCertificate(id: String) async throws {
        try await sendEmpty("DELETE", "/v1/certificates/\(id)")
    }

    public func bundleIDs() async throws -> [BundleID] {
        let resources: [Resource<BundleIDAttributes>] = try await all(
            "/v1/bundleIds", query: ["limit": "200", "sort": "identifier"])
        return resources.map(Self.bundleID)
    }

    public func createBundleID(identifier: String, name: String, platform: BundleIDPlatform) async throws -> BundleID {
        let body = Body(
            type: "bundleIds",
            attributes: [
                "identifier": .string(identifier), "name": .string(name), "platform": .string(platform.rawValue),
            ])
        let document: Document<Resource<BundleIDAttributes>> = try await send("POST", "/v1/bundleIds", body: body)
        return Self.bundleID(document.data)
    }

    public func deleteBundleID(id: String) async throws {
        try await sendEmpty("DELETE", "/v1/bundleIds/\(id)")
    }

    public func capabilities(bundleID: String) async throws -> [BundleIDCapability] {
        let resources: [Resource<CapabilityAttributes>] = try await all(
            "/v1/bundleIds/\(bundleID)/bundleIdCapabilities", query: [:])
        return resources.map(Self.capability)
    }

    public func enableCapability(_ type: CapabilityType, settings: [CapabilitySetting], bundleID: String) async throws
        -> BundleIDCapability
    {
        var attributes: [String: JSONValue] = ["capabilityType": .string(type.rawValue)]
        if !settings.isEmpty {
            attributes["settings"] = try JSONValue(encoding: settings)
        }
        let body = Body(
            type: "bundleIdCapabilities", attributes: attributes,
            relationships: ["bundleId": .one(type: "bundleIds", id: bundleID)])
        let document: Document<Resource<CapabilityAttributes>> = try await send(
            "POST", "/v1/bundleIdCapabilities", body: body)
        return Self.capability(document.data)
    }

    public func disableCapability(id: String) async throws {
        try await sendEmpty("DELETE", "/v1/bundleIdCapabilities/\(id)")
    }

    public func devices() async throws -> [Device] {
        let resources: [Resource<DeviceAttributes>] = try await all(
            "/v1/devices", query: ["limit": "200", "sort": "name"])
        return resources.map(Self.device)
    }

    public func registerDevice(name: String, udid: String, platform: BundleIDPlatform) async throws -> Device {
        let body = Body(
            type: "devices",
            attributes: ["name": .string(name), "udid": .string(udid), "platform": .string(platform.rawValue)])
        let document: Document<Resource<DeviceAttributes>> = try await send("POST", "/v1/devices", body: body)
        return Self.device(document.data)
    }

    public func updateDevice(id: String, name: String?, status: Device.Status?) async throws -> Device {
        var attributes: [String: JSONValue] = [:]
        if let name { attributes["name"] = .string(name) }
        if let status { attributes["status"] = .string(status.rawValue) }
        let body = Body(type: "devices", id: id, attributes: attributes)
        let document: Document<Resource<DeviceAttributes>> = try await send("PATCH", "/v1/devices/\(id)", body: body)
        return Self.device(document.data)
    }

    public func profiles() async throws -> [Profile] {
        let resources: [Resource<ProfileAttributes>] = try await all(
            "/v1/profiles",
            query: [
                "limit": "200", "include": "bundleId,certificates,devices", "fields[profiles]":
                    "name,profileType,profileState,uuid,expirationDate,bundleId,certificates,devices",
                "limit[certificates]": "50", "limit[devices]": "50",
            ])
        return resources.map(Self.profile)
    }

    public func profile(id: String) async throws -> Profile {
        let document: Document<Resource<ProfileAttributes>> = try await send(
            "GET", "/v1/profiles/\(id)",
            query: ["include": "bundleId,certificates,devices", "limit[certificates]": "50", "limit[devices]": "50"])
        return Self.profile(document.data)
    }

    public func createProfile(
        name: String, type: ProfileType, bundleID: String, certificateIDs: [String], deviceIDs: [String]
    ) async throws -> Profile {
        var relationships: [String: Relationship] = [
            "bundleId": .one(type: "bundleIds", id: bundleID),
            "certificates": .many(type: "certificates", ids: certificateIDs),
        ]
        if type.includesDevices {
            relationships["devices"] = .many(type: "devices", ids: deviceIDs)
        }
        let body = Body(
            type: "profiles",
            attributes: ["name": .string(name), "profileType": .string(type.rawValue)],
            relationships: relationships)
        let document: Document<Resource<ProfileAttributes>> = try await send("POST", "/v1/profiles", body: body)
        var profile = Self.profile(document.data)
        if profile.bundleIDResource == nil { profile.bundleIDResource = bundleID }
        if profile.certificateIDs.isEmpty { profile.certificateIDs = certificateIDs }
        if profile.deviceIDs.isEmpty, type.includesDevices { profile.deviceIDs = deviceIDs }
        return profile
    }

    public func deleteProfile(id: String) async throws {
        try await sendEmpty("DELETE", "/v1/profiles/\(id)")
    }
}

extension AppStoreConnectClient {
    private func token() throws -> String {
        tokenLock.lock()
        defer { tokenLock.unlock() }
        if let cachedToken, cachedToken.expiry > Date().addingTimeInterval(60) {
            return cachedToken.value
        }
        let now = Date()
        let value = try JSONWebToken.make(credentials: credentials, now: now)
        cachedToken = (value, now.addingTimeInterval(15 * 60))
        return value
    }

    private func request(_ method: String, url: URL, body: Body?) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(try token())", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(["data": body])
        }
        return request
    }

    private func url(_ path: String, query: [String: String]) -> URL {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        return components.url!
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let items = (try? JSONDecoder().decode(ErrorDocument.self, from: data))?.errors ?? []
            throw AppStoreConnectError(statusCode: status, items: items)
        }
        return data
    }

    private func send<Response: Decodable>(
        _ method: String, _ path: String, query: [String: String] = [:], body: Body? = nil
    ) async throws -> Response {
        let data = try await perform(try request(method, url: url(path, query: query), body: body))
        return try Self.decoder.decode(Response.self, from: data)
    }

    private func sendEmpty(_ method: String, _ path: String) async throws {
        _ = try await perform(try request(method, url: url(path, query: [:]), body: nil))
    }

    private func all<Attributes: Decodable>(_ path: String, query: [String: String]) async throws
        -> [Resource<Attributes>]
    {
        var next: URL? = url(path, query: query)
        var collected: [Resource<Attributes>] = []
        while let current = next {
            let data = try await perform(try request("GET", url: current, body: nil))
            let page = try Self.decoder.decode(Page<Resource<Attributes>>.self, from: data)
            collected.append(contentsOf: page.data)
            next = page.links?.next
        }
        return collected
    }

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            if let date = parseDate(text) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: text))
        }
        return decoder
    }()

    static func parseDate(_ text: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: text) { return date }
        let plain = ISO8601DateFormatter()
        if let date = plain.date(from: text) { return date }
        let custom = DateFormatter()
        custom.locale = Locale(identifier: "en_US_POSIX")
        custom.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ"
        return custom.date(from: text)
    }

    static func certificate(_ resource: Resource<CertificateAttributes>) -> Certificate {
        let attributes = resource.attributes
        return Certificate(
            id: resource.id,
            name: attributes.name ?? attributes.displayName ?? "",
            displayName: attributes.displayName ?? attributes.name ?? "",
            certificateType: attributes.certificateType ?? CertificateType(rawValue: "UNKNOWN"),
            serialNumber: attributes.serialNumber ?? "",
            expirationDate: attributes.expirationDate,
            content: attributes.certificateContent.flatMap { Data(base64Encoded: $0) })
    }

    static func bundleID(_ resource: Resource<BundleIDAttributes>) -> BundleID {
        BundleID(
            id: resource.id,
            identifier: resource.attributes.identifier ?? "",
            name: resource.attributes.name ?? "",
            platform: resource.attributes.platform ?? .universal,
            seedID: resource.attributes.seedId)
    }

    static func capability(_ resource: Resource<CapabilityAttributes>) -> BundleIDCapability {
        BundleIDCapability(
            id: resource.id,
            capabilityType: resource.attributes.capabilityType ?? CapabilityType(rawValue: "UNKNOWN"),
            settings: resource.attributes.settings ?? [])
    }

    static func device(_ resource: Resource<DeviceAttributes>) -> Device {
        let attributes = resource.attributes
        return Device(
            id: resource.id,
            name: attributes.name ?? "",
            udid: attributes.udid ?? "",
            platform: attributes.platform ?? .ios,
            deviceClass: attributes.deviceClass ?? DeviceClass(rawValue: "UNKNOWN"),
            model: attributes.model,
            status: attributes.status ?? .enabled,
            addedDate: attributes.addedDate)
    }

    static func profile(_ resource: Resource<ProfileAttributes>) -> Profile {
        let attributes = resource.attributes
        return Profile(
            id: resource.id,
            name: attributes.name ?? "",
            profileType: attributes.profileType ?? ProfileType(rawValue: "UNKNOWN"),
            state: attributes.profileState ?? .active,
            uuid: attributes.uuid ?? "",
            expirationDate: attributes.expirationDate,
            content: attributes.profileContent.flatMap { Data(base64Encoded: $0) },
            bundleIDResource: resource.relationships?["bundleId"]?.data?.ids.first,
            certificateIDs: resource.relationships?["certificates"]?.data?.ids ?? [],
            deviceIDs: resource.relationships?["devices"]?.data?.ids ?? [])
    }
}

struct Page<Item: Decodable>: Decodable {
    struct Links: Decodable {
        var next: URL?
    }

    var data: [Item]
    var links: Links?
}

struct Document<Item: Decodable>: Decodable {
    var data: Item
}

struct ErrorDocument: Decodable {
    var errors: [AppStoreConnectError.Item]
}

struct Resource<Attributes: Decodable>: Decodable {
    var id: String
    var type: String
    var attributes: Attributes
    var relationships: [String: RelationshipPayload]?
}

struct RelationshipPayload: Decodable {
    enum Linkage: Decodable {
        case one(Identifier?)
        case many([Identifier])

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let many = try? container.decode([Identifier].self) {
                self = .many(many)
            } else {
                self = .one(try? container.decode(Identifier.self))
            }
        }

        var ids: [String] {
            switch self {
            case .one(let identifier): identifier.map { [$0.id] } ?? []
            case .many(let identifiers): identifiers.map(\.id)
            }
        }
    }

    struct Identifier: Decodable {
        var id: String
        var type: String
    }

    var data: Linkage?
}

struct CertificateAttributes: Decodable {
    var name: String?
    var displayName: String?
    var certificateType: CertificateType?
    var serialNumber: String?
    var expirationDate: Date?
    var certificateContent: String?
}

struct BundleIDAttributes: Decodable {
    var identifier: String?
    var name: String?
    var platform: BundleIDPlatform?
    var seedId: String?
}

struct CapabilityAttributes: Decodable {
    var capabilityType: CapabilityType?
    var settings: [CapabilitySetting]?
}

struct DeviceAttributes: Decodable {
    var name: String?
    var udid: String?
    var platform: BundleIDPlatform?
    var deviceClass: DeviceClass?
    var model: String?
    var status: Device.Status?
    var addedDate: Date?
}

struct ProfileAttributes: Decodable {
    var name: String?
    var profileType: ProfileType?
    var profileState: Profile.State?
    var uuid: String?
    var expirationDate: Date?
    var profileContent: String?
}

struct Body: Encodable {
    var type: String
    var id: String?
    var attributes: [String: JSONValue]
    var relationships: [String: Relationship]?
}

enum Relationship: Encodable {
    case one(type: String, id: String)
    case many(type: String, ids: [String])

    private struct Identifier: Encodable {
        var type: String
        var id: String
    }

    private enum CodingKeys: String, CodingKey {
        case data
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .one(let type, let id):
            try container.encode(Identifier(type: type, id: id), forKey: .data)
        case .many(let type, let ids):
            try container.encode(ids.map { Identifier(type: type, id: $0) }, forKey: .data)
        }
    }
}

enum JSONValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    init(encoding value: some Encodable) throws {
        let data = try JSONEncoder().encode(value)
        self = try JSONDecoder().decode(JSONValue.self, from: data)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}
