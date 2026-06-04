import Foundation

private let systemPrompt = """
You are a professional multilingual translator and localization expert.

Your task is to translate the user's input into natural, fluent Japanese (日本語).
The output must be:
- accurate
- natural
- context-aware
- culturally appropriate
- fluent for native Japanese speakers

Translation rules:
- Preserve the original meaning exactly.
- Prioritize natural phrasing over literal word-by-word translation.
- Preserve tone, nuance, politeness level, and intent.
- Keep technical terminology consistent and use terms commonly used by native Japanese professionals in the relevant field.
- Do not omit information.
- Do not add explanations or commentary.
- Do not summarize.
- If the source is ambiguous, choose the most contextually natural interpretation.
- Preserve formatting, markdown, emojis, bullet points, and line breaks whenever possible.
- Preserve names, URLs, code, and identifiers unless localization is explicitly required.
- If the input is already in Japanese, return it unchanged.

Output only the translated text.
"""

struct OpenAIClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func translateStream(_ text: String, baseURL: URL, apiKey: String, model: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let endpointURL = baseURL.appendingPathComponent("chat/completions")

                    var request = URLRequest(url: endpointURL)
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.timeoutInterval = 60

                    let body = ChatCompletionRequest(
                        model: model,
                        messages: [
                            .init(role: "system", content: systemPrompt),
                            .init(role: "user", content: text)
                        ],
                        temperature: 0.2,
                        stream: true
                    )
                    request.httpBody = try JSONEncoder().encode(body)

                    let (bytes, response) = try await session.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        continuation.finish(throwing: TranslationError.unknown("Invalid response"))
                        return
                    }

                    if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                        continuation.finish(throwing: TranslationError.invalidKey)
                        return
                    }
                    if httpResponse.statusCode == 429 {
                        continuation.finish(throwing: TranslationError.rateLimited)
                        return
                    }
                    if !(200..<300).contains(httpResponse.statusCode) {
                        var data = Data()
                        for try await byte in bytes { data.append(byte) }
                        let apiError = try? JSONDecoder().decode(APIErrorResponse.self, from: data)
                        continuation.finish(throwing: TranslationError.unknown(
                            apiError?.error.message ?? "HTTP \(httpResponse.statusCode)"
                        ))
                        return
                    }

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let json = String(line.dropFirst(6))
                        if json == "[DONE]" { break }
                        guard let data = json.data(using: .utf8),
                              let chunk = try? JSONDecoder().decode(StreamChunk.self, from: data),
                              let delta = chunk.choices.first?.delta.content,
                              !delta.isEmpty else { continue }
                        continuation.yield(delta)
                    }

                    continuation.finish()
                } catch let error as TranslationError {
                    continuation.finish(throwing: error)
                } catch {
                    continuation.finish(throwing: TranslationError.networkError(error.localizedDescription))
                }
            }
        }
    }
}

enum TranslationError: LocalizedError {
    case invalidKey
    case rateLimited
    case networkError(String)
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .invalidKey:
            "APIキーが無効です。"
        case .rateLimited:
            "APIのレート制限に達しました。"
        case .networkError(let message):
            "ネットワークエラー: \(message)"
        case .unknown(let message):
            "翻訳に失敗しました: \(message)"
        }
    }
}

// 後方互換のための型エイリアス
typealias OpenAIError = TranslationError

private struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [Message]
    let temperature: Double
    let stream: Bool

    struct Message: Encodable {
        let role: String
        let content: String
    }
}

private struct StreamChunk: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let delta: Delta
    }

    struct Delta: Decodable {
        let content: String?
    }
}

private struct APIErrorResponse: Decodable {
    let error: APIError

    struct APIError: Decodable {
        let message: String
    }
}
