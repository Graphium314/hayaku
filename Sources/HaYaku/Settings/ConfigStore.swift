import Foundation

enum ProviderKind: String, Codable, CaseIterable {
    case openai
    case openrouter
    case custom

    var displayName: String {
        switch self {
        case .openai: "OpenAI"
        case .openrouter: "OpenRouter"
        case .custom: "カスタム"
        }
    }

    var baseURL: URL? {
        switch self {
        case .openai: URL(string: "https://api.openai.com/v1")
        case .openrouter: URL(string: "https://openrouter.ai/api/v1")
        case .custom: nil
        }
    }
}

struct ProviderConfig: Codable {
    var apiKey: String
    var model: String
    var baseURL: String

    init(apiKey: String = "", model: String = "", baseURL: String = "") {
        self.apiKey = apiKey
        self.model = model
        self.baseURL = baseURL
    }
}

struct AppConfig: Codable {
    var activeProvider: ProviderKind
    var openai: ProviderConfig
    var openrouter: ProviderConfig
    var custom: ProviderConfig

    static let `default` = AppConfig(
        activeProvider: .openai,
        openai: ProviderConfig(model: "gpt-5.4-mini"),
        openrouter: ProviderConfig(model: "openai/gpt-4o-mini"),
        custom: ProviderConfig()
    )
}

struct ConfigStore {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    private var configDirectoryURL: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("HaYaku", isDirectory: true)
    }

    private var configFileURL: URL {
        configDirectoryURL.appendingPathComponent("config.json", isDirectory: false)
    }

    func load() throws -> AppConfig {
        guard fileManager.fileExists(atPath: configFileURL.path) else {
            return .default
        }

        let data = try Data(contentsOf: configFileURL)

        // 新スキーマで読めたらそのまま返す
        if let config = try? JSONDecoder().decode(AppConfig.self, from: data) {
            return config
        }

        // 旧スキーマ（openaiApiKey + model のフラット構造）からの移行
        if let legacy = try? JSONDecoder().decode(LegacyConfig.self, from: data) {
            var config = AppConfig.default
            config.openai.apiKey = legacy.openaiApiKey
            if !legacy.model.isEmpty {
                config.openai.model = legacy.model
            }
            return config
        }

        return .default
    }

    func save(_ config: AppConfig) throws {
        try fileManager.createDirectory(at: configDirectoryURL, withIntermediateDirectories: true)

        let data = try JSONEncoder.pretty.encode(config)
        try data.write(to: configFileURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configFileURL.path)
    }
}

private struct LegacyConfig: Decodable {
    var openaiApiKey: String
    var model: String
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
