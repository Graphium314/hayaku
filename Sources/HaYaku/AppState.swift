import AppKit
import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var config: AppConfig
    @Published var isTranslating = false
    @Published var translationResult = ""
    @Published var errorMessage: String?
    @Published var showSettings = false
    @Published var showPopup = false

    private let configStore = ConfigStore()
    private let openAIClient = OpenAIClient()
    private let popupWindowController = PopupWindowController()
    private var didConfigure = false

    init() {
        config = (try? configStore.load()) ?? AppConfig.default
    }

    // MARK: - Convenience accessors for SettingsView bindings

    var activeProvider: ProviderKind {
        get { config.activeProvider }
        set { config.activeProvider = newValue }
    }

    var currentProviderConfig: ProviderConfig {
        get { providerConfig(for: config.activeProvider) }
        set { setProviderConfig(newValue, for: config.activeProvider) }
    }

    func providerConfig(for kind: ProviderKind) -> ProviderConfig {
        switch kind {
        case .openai: config.openai
        case .openrouter: config.openrouter
        case .custom: config.custom
        }
    }

    func setProviderConfig(_ value: ProviderConfig, for kind: ProviderKind) {
        switch kind {
        case .openai: config.openai = value
        case .openrouter: config.openrouter = value
        case .custom: config.custom = value
        }
    }

    func configureIfNeeded() {
        guard !didConfigure else { return }
        didConfigure = true

        HotkeyManager.shared.register { [weak self] in
            Task { @MainActor in
                await self?.translateSelectedText()
            }
        }

        if config.openai.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
           config.openrouter.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
           config.custom.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            openSettingsWindow()
        }
    }

    func saveConfig() {
        do {
            try configStore.save(config)
            errorMessage = nil
        } catch {
            errorMessage = "設定の保存に失敗しました: \(error.localizedDescription)"
        }
    }

    func openSettingsWindow() {
        showSettings = true
        SettingsWindowController.show(appState: self)
    }

    func translateSelectedText() async {
        guard !isTranslating else { return }

        guard let (baseURL, apiKey, model) = resolveActiveProvider() else { return }

        if !SelectionCapture.isAccessibilityTrusted(prompt: true) {
            showError("アクセシビリティ権限が必要です。設定画面を開き、「権限をリセット」→ システム設定でチェックを入れてアプリを再起動してください。")
            openSettingsWindow()
            return
        }

        isTranslating = true
        errorMessage = nil

        do {
            let capture = await SelectionCapture.captureWithDiagnostics()
            guard let selectedText = capture.text,
                  !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AppError.noSelection(diagnostics: capture.diagnosticSummary)
            }

            popupWindowController.showLoading()
            showPopup = true

            let stream = openAIClient.translateStream(selectedText, baseURL: baseURL, apiKey: apiKey, model: model)
            var accumulated = ""
            var receivedFirst = false
            for try await delta in stream {
                if !receivedFirst {
                    receivedFirst = true
                    popupWindowController.startStreaming(original: selectedText)
                }
                accumulated += delta
                popupWindowController.appendDelta(delta)
            }

            if !receivedFirst {
                throw TranslationError.unknown("Empty translation")
            }

            translationResult = accumulated
        } catch {
            let message = userFacingMessage(for: error)
            errorMessage = message
            showError(message)
        }

        isTranslating = false
    }

    func translateTestText() async {
        await translateText("Hello, world.")
    }

    private func translateText(_ text: String) async {
        guard let (baseURL, apiKey, model) = resolveActiveProvider() else { return }

        isTranslating = true
        errorMessage = nil

        do {
            popupWindowController.showLoading()

            let stream = openAIClient.translateStream(text, baseURL: baseURL, apiKey: apiKey, model: model)
            var accumulated = ""
            var receivedFirst = false
            for try await delta in stream {
                if !receivedFirst {
                    receivedFirst = true
                    popupWindowController.startStreaming(original: text)
                }
                accumulated += delta
                popupWindowController.appendDelta(delta)
            }

            if !receivedFirst {
                throw TranslationError.unknown("Empty translation")
            }

            translationResult = accumulated
        } catch {
            errorMessage = userFacingMessage(for: error)
        }

        isTranslating = false
    }

    // アクティブプロバイダーの (baseURL, apiKey, model) を解決して返す
    // 問題があれば errorMessage をセットして nil を返す
    private func resolveActiveProvider() -> (baseURL: URL, apiKey: String, model: String)? {
        let kind = config.activeProvider
        let provConfig = providerConfig(for: kind)
        let trimmedKey = provConfig.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedKey.isEmpty else {
            showError("\(kind.displayName) の APIキーを設定してください。")
            openSettingsWindow()
            return nil
        }

        let baseURL: URL
        if kind == .custom {
            let trimmedURL = provConfig.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedURL.isEmpty, let url = URL(string: trimmedURL) else {
                showError("カスタムプロバイダーの Base URL を設定してください。")
                openSettingsWindow()
                return nil
            }
            baseURL = url
        } else {
            baseURL = kind.baseURL!
        }

        let trimmedModel = provConfig.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModel.isEmpty else {
            showError("モデルを設定してください。")
            openSettingsWindow()
            return nil
        }

        return (baseURL, trimmedKey, trimmedModel)
    }

    private func showError(_ message: String) {
        errorMessage = message
        showPopup = true
        popupWindowController.showError(message)
    }

    private func userFacingMessage(for error: Error) -> String {
        if let appError = error as? AppError {
            return appError.localizedDescription
        }

        if let translationError = error as? TranslationError {
            return translationError.localizedDescription
        }

        return error.localizedDescription
    }
}

enum AppError: LocalizedError {
    case noSelection(diagnostics: String)

    var errorDescription: String? {
        switch self {
        case .noSelection(let diag):
            "テキストを選択してから試してください。\n[診断] \(diag)"
        }
    }
}

extension CaptureResult {
    var diagnosticSummary: String {
        let role = axFocusedRole.map { " role=\($0)" } ?? ""
        return "AX: \(axStage)\(role) / Copy: \(copyStage)"
    }
}
