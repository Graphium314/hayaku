import AppKit
import SwiftUI

struct MenuBarContent: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Button("翻訳 (⌘⇧T)") {
            Task {
                await appState.translateSelectedText()
            }
        }
        .disabled(appState.isTranslating)

        Button("設定...") {
            appState.openSettingsWindow()
        }

        Divider()

        Button("終了") {
            NSApp.terminate(nil)
        }
    }
}
