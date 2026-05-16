import AppKit
import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var apiKey: String
    @Published var model: String
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
        let config = (try? configStore.load()) ?? AppConfig.default
        apiKey = config.openaiApiKey
        model = config.model
    }

    func configureIfNeeded() {
        guard !didConfigure else { return }
        didConfigure = true

        HotkeyManager.shared.register { [weak self] in
            Task { @MainActor in
                await self?.translateSelectedText()
            }
        }

        if apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            openSettingsWindow()
        }
    }

    func saveConfig() {
        do {
            try configStore.save(AppConfig(openaiApiKey: apiKey, model: model))
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

        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAPIKey.isEmpty else {
            showError("OpenAI APIキーを設定してください。")
            openSettingsWindow()
            return
        }

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

            let stream = openAIClient.translateStream(selectedText, apiKey: trimmedAPIKey, model: model)
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
                throw OpenAIError.unknown("Empty translation")
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
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAPIKey.isEmpty else {
            errorMessage = "OpenAI APIキーを設定してください。"
            return
        }

        isTranslating = true
        errorMessage = nil

        do {
            popupWindowController.showLoading()

            let stream = openAIClient.translateStream(text, apiKey: trimmedAPIKey, model: model)
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
                throw OpenAIError.unknown("Empty translation")
            }

            translationResult = accumulated
        } catch {
            errorMessage = userFacingMessage(for: error)
        }

        isTranslating = false
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

        if let openAIError = error as? OpenAIError {
            return openAIError.localizedDescription
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
