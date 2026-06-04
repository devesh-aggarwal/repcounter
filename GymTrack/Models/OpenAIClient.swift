import Foundation

/// Minimal OpenAI chat completions client for the in-app coach. Streams
/// responses from `POST /v1/chat/completions` using URLSession + SSE parsing.
/// No third-party SDK needed — the raw HTTP surface for streaming chat
/// completions is small.
///
/// Calls go directly from the device to api.openai.com using the user's own
/// API key; nothing transits a proxy.
actor OpenAIClient {
    private let apiKey: String
    private let model: String
    private let session: URLSession

    init(apiKey: String, model: String = "gpt-4o") {
        self.apiKey = apiKey
        self.model = model
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 600
        self.session = URLSession(configuration: config)
    }

    /// Streams a single assistant turn given the system prompt + prior chat
    /// history + the new user message. OpenAI auto-caches prefixes ≥1024
    /// tokens, so no explicit cache_control is needed for multi-turn reuse.
    func streamReply(
        systemPrompt: String,
        history: [ChatMessage],
        onDelta: @escaping @Sendable (String) async -> Void
    ) async throws {
        guard let endpoint = URL(string: "https://api.openai.com/v1/chat/completions") else {
            throw OpenAIError.malformedURL
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let body = buildRequestBody(systemPrompt: systemPrompt, history: history)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await session.bytes(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw OpenAIError.network("No HTTP response")
        }
        guard http.statusCode == 200 else {
            let errorBody = try? await readErrorBody(bytes)
            throw OpenAIError.api(status: http.statusCode, message: errorBody ?? "HTTP \(http.statusCode)")
        }

        // Parse SSE: each line begins with `data: `; the body is either a
        // JSON chunk with `choices[0].delta.content`, or the literal `[DONE]`
        // sentinel.
        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))
            if payload == "[DONE]" { break }
            guard !payload.isEmpty,
                  let data = payload.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            if let choices = object["choices"] as? [[String: Any]],
               let first = choices.first,
               let delta = first["delta"] as? [String: Any],
               let content = delta["content"] as? String,
               !content.isEmpty {
                await onDelta(content)
            }
            if let err = object["error"] as? [String: Any],
               let message = err["message"] as? String {
                throw OpenAIError.api(status: 500, message: message)
            }
        }
    }

    // MARK: - Helpers

    private func buildRequestBody(systemPrompt: String, history: [ChatMessage]) -> [String: Any] {
        var messages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt]
        ]
        for msg in history {
            messages.append(["role": msg.role.wireValue, "content": msg.text])
        }
        return [
            "model": model,
            "stream": true,
            "messages": messages
        ]
    }

    private func readErrorBody(_ bytes: URLSession.AsyncBytes) async throws -> String? {
        var collected = ""
        for try await line in bytes.lines {
            collected += line
            if collected.count > 4000 { break }
        }
        // The error body is usually `{"error": {"message": "..."}}` — extract
        // the friendly message when we can, fall back to the raw string.
        if let data = collected.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let err = object["error"] as? [String: Any],
           let message = err["message"] as? String {
            return message
        }
        return collected.isEmpty ? nil : collected
    }
}

enum OpenAIError: LocalizedError {
    case malformedURL
    case network(String)
    case api(status: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .malformedURL: return "Invalid URL."
        case .network(let msg): return msg
        case .api(let status, let msg):
            return "OpenAI API error (\(status)): \(msg)"
        }
    }
}
