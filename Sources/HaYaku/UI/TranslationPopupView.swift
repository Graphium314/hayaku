import AppKit
import SwiftUI

enum TranslationPopupState {
    case loading
    case result(original: String, translation: String)
    case error(String)
}

struct TranslationPopupView: View {
    @ObservedObject var viewModel: PopupViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch viewModel.state {
            case .loading:
                HStack(spacing: 10) {
                    ProgressView()
                    Text("翻訳中...")
                        .font(.body)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

            case .result(let original, let translation):
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(original)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(5)

                        Text(translation)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                    }

                    Spacer(minLength: 8)

                    VStack(spacing: 8) {
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(translation, forType: .string)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .help("訳文をコピー")

                        Button {
                            viewModel.onClose()
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .help("閉じる")
                    }
                    .buttonStyle(.borderless)
                }

            case .error(let message):
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)

                    Text(message)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 8)

                    Button {
                        viewModel.onClose()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.borderless)
                    .help("閉じる")
                }
            }
        }
        .padding(14)
        .frame(width: 350, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
