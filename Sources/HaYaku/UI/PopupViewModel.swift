import SwiftUI

@MainActor
final class PopupViewModel: ObservableObject {
    @Published var state: TranslationPopupState = .loading
    var onClose: () -> Void = {}

    func showLoading() {
        state = .loading
    }

    func showError(_ message: String) {
        state = .error(message)
    }

    func startStreaming(original: String) {
        state = .result(original: original, translation: "")
    }

    func appendDelta(_ s: String) {
        guard case .result(let original, let translation) = state else { return }
        state = .result(original: original, translation: translation + s)
    }
}
