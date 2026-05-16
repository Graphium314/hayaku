import AppKit
import SwiftUI

final class SettingsWindowController: NSWindowController {
    private static var shared: SettingsWindowController?

    static func show(appState: AppState) {
        if let existing = shared {
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let controller = SettingsWindowController(appState: appState)
        shared = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private init(appState: AppState) {
        let view = SettingsView().environmentObject(appState)
        let hosting = NSHostingController(rootView: view)
        hosting.view.frame = NSRect(x: 0, y: 0, width: 520, height: 320)

        let window = NSWindow(contentViewController: hosting)
        window.title = "HaYaku 設定"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 520, height: 320))
        window.center()

        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}

extension SettingsWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        SettingsWindowController.shared = nil
    }
}
