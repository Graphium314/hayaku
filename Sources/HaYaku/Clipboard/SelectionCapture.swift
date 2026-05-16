import AppKit
import ApplicationServices

struct CaptureResult {
    let text: String?
    let axStage: String
    let axFocusedRole: String?
    let copyStage: String
}

@MainActor
enum SelectionCapture {
    static func isAccessibilityTrusted(prompt: Bool) -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func captureSelectedText() async -> String? {
        let result = await captureWithDiagnostics()
        return result.text
    }

    static func captureWithDiagnostics() async -> CaptureResult {
        guard isAccessibilityTrusted(prompt: false) else {
            return CaptureResult(text: nil, axStage: "permission_denied", axFocusedRole: nil, copyStage: "not_attempted")
        }

        let (axText, axStage, axRole) = captureViaAccessibility()
        if let text = axText, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return CaptureResult(text: text, axStage: "ok(\(axStage))", axFocusedRole: axRole, copyStage: "not_attempted")
        }

        let (copyText, copyStage) = await captureViaCopyShortcut()
        return CaptureResult(text: copyText, axStage: axStage, axFocusedRole: axRole, copyStage: copyStage)
    }

    // MARK: - AX API

    private static func captureViaAccessibility() -> (String?, String, String?) {
        // フロントアプリの PID から app 要素を作成し、そこから focusedElement を取得する。
        // システムワイドの kAXFocusedUIElement は AXWindow を返すことがあり、
        // kAXSelectedText が取れないケースがある。
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            return captureViaSystemWideAX()
        }

        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)
        var focusedRef: AnyObject?
        let focusErr = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedRef)

        guard focusErr == .success, let focusedRef else {
            return captureViaSystemWideAX()
        }

        // swiftlint:disable force_cast
        let focusedElement = focusedRef as! AXUIElement
        return extractText(from: focusedElement, source: "app")
    }

    private static func captureViaSystemWideAX() -> (String?, String, String?) {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: AnyObject?
        let focusErr = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef)
        guard focusErr == .success, let focusedRef else {
            return (nil, "no_focused_element:\(focusErr.rawValue)", nil)
        }
        // swiftlint:disable force_cast
        let focusedElement = focusedRef as! AXUIElement
        return extractText(from: focusedElement, source: "syswide")
    }

    private static func extractText(from element: AXUIElement, source: String) -> (String?, String, String?) {
        let role = axRole(of: element)

        var selectedTextRef: AnyObject?
        let textErr = AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedTextRef)

        if textErr == .success, let text = selectedTextRef as? String {
            if !text.isEmpty {
                return (text, "ok_direct_\(source)", role)
            }
            return (nil, "empty_string_\(source)", role)
        }

        // kAXSelectedTextRange + kAXValue で切り出す
        if let extracted = extractViaRange(element: element), !extracted.isEmpty {
            return (extracted, "ok_range_\(source)", role)
        }

        // 子孫要素を BFS で探索
        if let found = searchDescendantsForSelection(element, maxDepth: 5) {
            return (found, "ok_descendant_\(source)", role)
        }

        return (nil, "no_selected_text:\(textErr.rawValue)_\(source) role=\(role ?? "nil")", role)
    }

    private static func axRole(of element: AXUIElement) -> String? {
        var roleRef: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success,
              let role = roleRef as? String else { return nil }
        return role
    }

    private static func extractViaRange(element: AXUIElement) -> String? {
        var rangeRef: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let cfRange = rangeRef else { return nil }

        var valueRef: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
              let fullText = valueRef as? String else { return nil }

        var range = CFRange()
        // swiftlint:disable force_cast
        AXValueGetValue(cfRange as! AXValue, AXValueType.cfRange, &range)

        guard range.length > 0, range.location >= 0, range.location <= fullText.count else { return nil }
        let clampedLength = min(range.length, fullText.count - range.location)
        guard clampedLength > 0 else { return nil }

        let startIdx = fullText.index(fullText.startIndex, offsetBy: range.location)
        let endIdx = fullText.index(startIdx, offsetBy: clampedLength)
        return String(fullText[startIdx..<endIdx])
    }

    private static func searchDescendantsForSelection(_ element: AXUIElement, maxDepth: Int) -> String? {
        guard maxDepth > 0 else { return nil }

        var childrenRef: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else { return nil }

        for child in children {
            var textRef: AnyObject?
            if AXUIElementCopyAttributeValue(child, kAXSelectedTextAttribute as CFString, &textRef) == .success,
               let text = textRef as? String, !text.isEmpty {
                return text
            }
            if let found = searchDescendantsForSelection(child, maxDepth: maxDepth - 1) {
                return found
            }
        }
        return nil
    }

    // MARK: - CGEvent Cmd+C フォールバック

    private static func captureViaCopyShortcut() async -> (String?, String) {
        let didRelease = await waitForModifierKeysReleased(timeoutMs: 1000)
        if !didRelease {
            return (nil, "modifier_timeout")
        }

        let pasteboard = NSPasteboard.general
        let previousChangeCount = pasteboard.changeCount

        synthesizeCopyShortcut()

        for _ in 0..<20 {
            try? await Task.sleep(nanoseconds: 30_000_000)
            if pasteboard.changeCount != previousChangeCount {
                let text = pasteboard.string(forType: .string)
                return (text, "ok")
            }
        }

        return (nil, "no_change_count")
    }

    @discardableResult
    private static func waitForModifierKeysReleased(timeoutMs: Int) async -> Bool {
        let steps = timeoutMs / 30
        for _ in 0..<steps {
            let flags = CGEventSource.flagsState(.combinedSessionState)
            if !flags.contains(.maskCommand) && !flags.contains(.maskShift) {
                return true
            }
            try? await Task.sleep(nanoseconds: 30_000_000)
        }
        return false
    }

    private static func synthesizeCopyShortcut() {
        let source = CGEventSource(stateID: .privateState)
        let cKeyCode: CGKeyCode = 8

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: cKeyCode, keyDown: true)
        keyDown?.flags = .maskCommand

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: cKeyCode, keyDown: false)
        keyUp?.flags = .maskCommand

        // .cghidEventTap は HID レイヤーに直接送るため、
        // CGEvent を受け付けにくいアプリでも届きやすい
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
