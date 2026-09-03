import Foundation

enum VaultTimestamp {
    static func normalized(_ date: Date) -> Date {
        let milliseconds = (date.timeIntervalSince1970 * 1_000).rounded()
        return Date(timeIntervalSince1970: milliseconds / 1_000)
    }
}

enum CredentialKind: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case website
    case ssh
    case apiKey

    var id: Self { self }

    var label: String {
        switch self {
        case .website: "Website"
        case .ssh: "SSH"
        case .apiKey: "API Key"
        }
    }
}

struct Credential: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    var username: String
    var password: String
    var kind: CredentialKind
    var website: String
    var allowedPasswordSymbols: String
    var sshHost: String
    var sshCommand: String
    var apiKey: String
    var apiEndpoint: String
    var notes: String
    var createdAt: Date
    var updatedAt: Date
    var revision: UUID

    init(
        id: UUID = UUID(),
        name: String,
        username: String = "",
        password: String = "",
        kind: CredentialKind = .website,
        website: String = "",
        allowedPasswordSymbols: String = "",
        sshHost: String = "",
        sshCommand: String = "",
        apiKey: String = "",
        apiEndpoint: String = "",
        notes: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        revision: UUID = UUID()
    ) {
        self.id = id
        self.name = name
        self.username = username
        self.password = password
        self.kind = kind
        self.website = website
        self.allowedPasswordSymbols = allowedPasswordSymbols
        self.sshHost = sshHost
        self.sshCommand = sshCommand
        self.apiKey = apiKey
        self.apiEndpoint = apiEndpoint
        self.notes = notes
        self.createdAt = VaultTimestamp.normalized(createdAt)
        self.updatedAt = VaultTimestamp.normalized(updatedAt)
        self.revision = revision
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case username
        case password
        case kind
        case website
        case allowedPasswordSymbols
        case sshHost
        case sshCommand
        case apiKey
        case apiEndpoint
        case notes
        case createdAt
        case updatedAt
        case revision
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        username = try container.decode(String.self, forKey: .username)
        password = try container.decode(String.self, forKey: .password)
        kind = try container.decodeIfPresent(CredentialKind.self, forKey: .kind) ?? .website
        website = try container.decode(String.self, forKey: .website)
        allowedPasswordSymbols = try container.decodeIfPresent(String.self, forKey: .allowedPasswordSymbols) ?? ""
        sshHost = try container.decodeIfPresent(String.self, forKey: .sshHost) ?? ""
        sshCommand = try container.decodeIfPresent(String.self, forKey: .sshCommand) ?? ""
        apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
        apiEndpoint = try container.decodeIfPresent(String.self, forKey: .apiEndpoint) ?? ""
        notes = try container.decode(String.self, forKey: .notes)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        revision = try container.decode(UUID.self, forKey: .revision)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(username, forKey: .username)
        try container.encode(password, forKey: .password)
        try container.encode(kind, forKey: .kind)
        try container.encode(website, forKey: .website)
        try container.encode(allowedPasswordSymbols, forKey: .allowedPasswordSymbols)
        try container.encode(sshHost, forKey: .sshHost)
        try container.encode(sshCommand, forKey: .sshCommand)
        try container.encode(apiKey, forKey: .apiKey)
        try container.encode(apiEndpoint, forKey: .apiEndpoint)
        try container.encode(notes, forKey: .notes)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(revision, forKey: .revision)
    }

    mutating func markUpdated(at date: Date = Date()) {
        updatedAt = VaultTimestamp.normalized(date)
        revision = UUID()
    }
}
