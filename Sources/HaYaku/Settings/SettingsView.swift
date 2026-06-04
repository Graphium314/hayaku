import ApplicationServices
import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var revealAPIKey = false
    @State private var accessibilityTrusted = SelectionCapture.isAccessibilityTrusted(prompt: false)
    @State private var customModelInput = ""

    private let openAIModels = ["gpt-5.4-mini", "gpt-4o-mini", "gpt-4o", "gpt-4.1-mini"]
    private let openRouterPresets = [
        "openai/gpt-4o-mini",
        "anthropic/claude-sonnet-4-5",
        "google/gemini-2.0-flash-exp:free",
        "meta-llama/llama-3.3-70b-instruct"
    ]

    var body: some View {
        Form {
            // プロバイダー選択
            Section {
                Picker("プロバイダー", selection: Binding(
                    get: { appState.activeProvider },
                    set: { appState.activeProvider = $0 }
                )) {
                    ForEach(ProviderKind.allCases, id: \.self) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("プロバイダー")
            }

            // APIキー
            Section {
                HStack {
                    Group {
                        if revealAPIKey {
                            TextField("APIキー", text: apiKeyBinding)
                        } else {
                            SecureField("APIキー", text: apiKeyBinding)
                        }
                    }
                    .textFieldStyle(.roundedBorder)

                    Button {
                        revealAPIKey.toggle()
                    } label: {
                        Image(systemName: revealAPIKey ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                    .help(revealAPIKey ? "APIキーを隠す" : "APIキーを表示")
                }

                if appState.activeProvider == .openrouter {
                    Text("OpenRouter のキーは openrouter.ai/keys で取得できます。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("APIキー")
            }

            // モデル
            Section {
                switch appState.activeProvider {
                case .openai:
                    Picker("モデル", selection: modelBinding) {
                        ForEach(openAIModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }

                case .openrouter:
                    Picker("プリセット", selection: modelBinding) {
                        ForEach(openRouterPresets, id: \.self) { model in
                            Text(model).tag(model)
                        }
                        Text("カスタム入力").tag("__custom__")
                    }
                    if !openRouterPresets.contains(modelBinding.wrappedValue) {
                        TextField("モデルID (例: openai/gpt-4o)", text: modelBinding)
                            .textFieldStyle(.roundedBorder)
                    }

                case .custom:
                    TextField("Base URL (例: http://localhost:8080/v1)", text: baseURLBinding)
                        .textFieldStyle(.roundedBorder)
                    TextField("モデルID", text: modelBinding)
                        .textFieldStyle(.roundedBorder)
                }
            } header: {
                Text("モデル")
            }

            // ショートカット
            Section {
                KeyboardShortcuts.Recorder("翻訳", name: .translate)
            } header: {
                Text("ショートカット")
            }

            // アクセシビリティ権限
            Section {
                HStack {
                    Image(systemName: accessibilityTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(accessibilityTrusted ? .green : .orange)

                    Text(accessibilityTrusted ? "許可されています" : "許可されていません")

                    Spacer()

                    Button("システム設定を開く") {
                        _ = SelectionCapture.isAccessibilityTrusted(prompt: true)
                        openAccessibilitySettings()
                    }
                }

                if !accessibilityTrusted {
                    HStack {
                        Text("権限を付与済みなのに動かない場合は、一度リセットして再登録してください。")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button("権限をリセット") {
                            resetAccessibilityPermission()
                        }
                        .foregroundStyle(.orange)
                    }
                }
            } header: {
                Text("アクセシビリティ権限")
            }

            HStack {
                Button("保存") {
                    appState.saveConfig()
                }
                .keyboardShortcut(.defaultAction)

                Button("翻訳テスト") {
                    Task {
                        await appState.translateTestText()
                    }
                }
                .disabled(appState.isTranslating)

                if appState.isTranslating {
                    ProgressView()
                        .scaleEffect(0.75)
                }

                Spacer()
            }

            if let errorMessage = appState.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
        .padding(20)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            accessibilityTrusted = SelectionCapture.isAccessibilityTrusted(prompt: false)
        }
    }

    // MARK: - Bindings

    private var apiKeyBinding: Binding<String> {
        Binding(
            get: { appState.providerConfig(for: appState.activeProvider).apiKey },
            set: {
                var c = appState.providerConfig(for: appState.activeProvider)
                c.apiKey = $0
                appState.setProviderConfig(c, for: appState.activeProvider)
            }
        )
    }

    private var modelBinding: Binding<String> {
        Binding(
            get: { appState.providerConfig(for: appState.activeProvider).model },
            set: {
                var c = appState.providerConfig(for: appState.activeProvider)
                c.model = $0
                appState.setProviderConfig(c, for: appState.activeProvider)
            }
        )
    }

    private var baseURLBinding: Binding<String> {
        Binding(
            get: { appState.config.custom.baseURL },
            set: { appState.config.custom.baseURL = $0 }
        )
    }

    // MARK: - Actions

    private func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func resetAccessibilityPermission() {
        let task = Process()
        task.launchPath = "/usr/bin/tccutil"
        task.arguments = ["reset", "Accessibility", "com.personal.HaYaku"]
        try? task.run()
        task.waitUntilExit()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            openAccessibilitySettings()
        }
    }
}
