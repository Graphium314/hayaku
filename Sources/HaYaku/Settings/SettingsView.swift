import ApplicationServices
import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var revealAPIKey = false
    @State private var accessibilityTrusted = SelectionCapture.isAccessibilityTrusted(prompt: false)

    private let models = ["gpt-5.4-mini", "gpt-4o-mini", "gpt-4o", "gpt-4.1-mini"]

    var body: some View {
        Form {
            Section {
                HStack {
                    Group {
                        if revealAPIKey {
                            TextField("sk-...", text: $appState.apiKey)
                        } else {
                            SecureField("sk-...", text: $appState.apiKey)
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

                Picker("モデル", selection: $appState.model) {
                    ForEach(models, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
            } header: {
                Text("OpenAI")
            }

            Section {
                KeyboardShortcuts.Recorder("翻訳", name: .translate)
            } header: {
                Text("ショートカット")
            }

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
