import Foundation

struct AppConfig: Codable {
    var openaiApiKey: String
    var model: String

    static let `default` = AppConfig(openaiApiKey: "", model: "gpt-5.4-mini")
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
        return try JSONDecoder().decode(AppConfig.self, from: data)
    }

    func save(_ config: AppConfig) throws {
        try fileManager.createDirectory(at: configDirectoryURL, withIntermediateDirectories: true)

        let data = try JSONEncoder.pretty.encode(config)
        try data.write(to: configFileURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configFileURL.path)
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
