import AppKit
import SwiftUI

@MainActor
final class PopupWindowController: NSWindowController, NSWindowDelegate {
    private let popupWindow: PopupWindow
    private let viewModel = PopupViewModel()

    init() {
        popupWindow = PopupWindow()
        super.init(window: popupWindow)
        popupWindow.delegate = self
        popupWindow.contentView = NSHostingView(rootView: TranslationPopupView(viewModel: viewModel))
        viewModel.onClose = { [weak self] in self?.close() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showLoading() {
        viewModel.showLoading()
        showNearMouse()
    }

    func startStreaming(original: String) {
        viewModel.startStreaming(original: original)
    }

    func appendDelta(_ s: String) {
        guard window?.isVisible == true else { return }
        viewModel.appendDelta(s)
        DispatchQueue.main.async { [weak self] in
            self?.resizeToFit()
        }
    }

    func showError(_ message: String) {
        viewModel.showError(message)
        showNearMouse()
    }

    private func resizeToFit() {
        guard let window, let contentView = window.contentView else { return }
        let fitting = contentView.fittingSize
        let newHeight = max(120, fitting.height)
        let currentFrame = window.frame
        window.setFrame(NSRect(
            x: currentFrame.minX,
            y: currentFrame.maxY - newHeight,
            width: currentFrame.width,
            height: newHeight
        ), display: true, animate: false)
    }

    private func showNearMouse() {
        guard let window else { return }

        let size = window.contentView?.fittingSize ?? window.frame.size
        let clampedSize = NSSize(width: max(350, size.width), height: max(120, size.height))
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) } ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? .zero

        var origin = NSPoint(x: mouseLocation.x + 16, y: mouseLocation.y - clampedSize.height - 16)

        if origin.x + clampedSize.width > visibleFrame.maxX {
            origin.x = mouseLocation.x - clampedSize.width - 16
        }

        if origin.y < visibleFrame.minY {
            origin.y = mouseLocation.y + 16
        }

        origin.x = min(max(origin.x, visibleFrame.minX + 8), visibleFrame.maxX - clampedSize.width - 8)
        origin.y = min(max(origin.y, visibleFrame.minY + 8), visibleFrame.maxY - clampedSize.height - 8)

        window.setFrame(NSRect(origin: origin, size: clampedSize), display: true)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

final class PopupWindow: NSWindow {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 350, height: 160),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = true
    }

    override var canBecomeKey: Bool {
        true
    }

    override func cancelOperation(_ sender: Any?) {
        close()
    }
}
