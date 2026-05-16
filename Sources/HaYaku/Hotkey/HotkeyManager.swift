import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let translate = Self(
        "translate",
        default: KeyboardShortcuts.Shortcut(.t, modifiers: [.command, .shift])
    )
}

@MainActor
final class HotkeyManager {
    static let shared = HotkeyManager()

    private init() {}

    func register(action: @escaping @Sendable () -> Void) {
        KeyboardShortcuts.onKeyUp(for: .translate) {
            action()
        }
    }
}
