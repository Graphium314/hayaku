import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let appState = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "character.bubble", accessibilityDescription: "HaYaku")
            button.image?.isTemplate = true
            button.action = #selector(showMenu)
            button.target = self
        }

        appState.configureIfNeeded()

        if appState.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.appState.openSettingsWindow()
            }
        }
    }

    @objc private func showMenu() {
        let menu = NSMenu()

        let translateItem = NSMenuItem(title: "翻訳 (⌘⇧T)", action: #selector(triggerTranslation), keyEquivalent: "")
        translateItem.target = self
        menu.addItem(translateItem)

        let settingsItem = NSMenuItem(title: "設定...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    @objc private func triggerTranslation() {
        Task {
            await self.appState.translateSelectedText()
        }
    }

    @objc private func openSettings() {
        appState.openSettingsWindow()
    }
}
