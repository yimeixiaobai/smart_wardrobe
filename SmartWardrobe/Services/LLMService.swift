import Foundation

actor LLMService {
    static let shared = LLMService()

    // MARK: - Types (Text)

    struct ChatMessage: Codable {
        let role: String
        let content: String
    }

    // MARK: - Types (Vision / Multimodal)

    struct ContentPart: Encodable {
        let type: String
        let text: String?
        let image_url: ImageURL?

        struct ImageURL: Encodable {
            let url: String
            let detail: String?
        }

        static func text(_ text: String) -> ContentPart {
            ContentPart(type: "text", text: text, image_url: nil)
        }

        static func imageBase64(_ base64: String, detail: String = "low") -> ContentPart {
            ContentPart(
                type: "image_url",
                text: nil,
                image_url: ImageURL(url: "data:image/jpeg;base64,\(base64)", detail: detail)
            )
        }
    }

    struct VisionMessage: Encodable {
        let role: String
        let content: [ContentPart]
    }

    // MARK: - Request / Response

    struct ChatRequest: Codable {
        let model: String
        let messages: [ChatMessage]
        let response_format: ResponseFormat?
        let temperature: Double?
        let max_tokens: Int?
    }

    private struct VisionRequest: Encodable {
        let model: String
        let messages: [VisionMessage]
        let response_format: ResponseFormat?
        let temperature: Double?
        let max_tokens: Int?
    }

    struct ResponseFormat: Codable {
        let type: String
    }

    struct ChatResponse: Codable {
        struct Choice: Codable {
            struct Message: Codable {
                let content: String
            }
            let message: Message
        }
        let choices: [Choice]
    }

    struct ErrorResponse: Codable {
        struct ErrorDetail: Codable {
            let message: String
        }
        let error: ErrorDetail
    }

    enum ServiceError: LocalizedError {
        case noAPIKey
        case invalidURL
        case networkError(String)
        case apiError(String)
        case emptyResponse
        case decodingError(String)

        var errorDescription: String? {
            switch self {
            case .noAPIKey: return "未配置 AI 服务，请在「AI 设置」中完成配置"
            case .invalidURL: return "请求地址错误"
            case .networkError(let msg): return "网络错误：\(msg)"
            case .apiError(let msg): return "API 错误：\(msg)"
            case .emptyResponse: return "模型返回为空"
            case .decodingError(let msg): return "解析错误：\(msg)"
            }
        }
    }

    // MARK: - Text Chat

    func chat(
        messages: [ChatMessage],
        jsonMode: Bool = true,
        temperature: Double = 0.7,
        maxTokens: Int = 10000
    ) async throws -> String {
        let (apiKey, url, model) = try resolveConfig()

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 60

        let chatRequest = ChatRequest(
            model: model,
            messages: messages,
            response_format: jsonMode ? ResponseFormat(type: "json_object") : nil,
            temperature: temperature,
            max_tokens: maxTokens
        )

        let bodyData = try JSONEncoder().encode(chatRequest)
        request.httpBody = bodyData

        return try await performRequest(request)
    }

    // MARK: - Vision Chat

    func visionChat(
        messages: [VisionMessage],
        temperature: Double = 0.3,
        maxTokens: Int = 10000
    ) async throws -> String {
        let (apiKey, url, model) = try resolveConfig()

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 120

        let visionRequest = VisionRequest(
            model: model,
            messages: messages,
            response_format: ResponseFormat(type: "json_object"),
            temperature: temperature,
            max_tokens: maxTokens
        )

        let bodyData = try JSONEncoder().encode(visionRequest)
        request.httpBody = bodyData

        return try await performRequest(request)
    }

    // MARK: - Config

    private func resolveConfig() throws -> (apiKey: String, url: URL, model: String) {
        guard let apiKey = APIKeyManager.shared.llmAPIKey,
              !apiKey.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw ServiceError.noAPIKey
        }
        guard let baseURL = APIKeyManager.shared.llmBaseURL,
              let url = URL(string: baseURL) else {
            throw ServiceError.invalidURL
        }
        guard let model = APIKeyManager.shared.llmModel,
              !model.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw ServiceError.noAPIKey
        }
        return (apiKey, url, model)
    }

    // MARK: - Shared HTTP

    private func performRequest(_ request: URLRequest) async throws -> String {
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ServiceError.networkError("无效的响应")
        }

        if httpResponse.statusCode != 200 {
            if let errorResp = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                throw ServiceError.apiError(errorResp.error.message)
            }
            throw ServiceError.apiError("HTTP \(httpResponse.statusCode)")
        }

        let chatResponse = try JSONDecoder().decode(ChatResponse.self, from: data)

        guard let content = chatResponse.choices.first?.message.content, !content.isEmpty else {
            throw ServiceError.emptyResponse
        }

        return content
    }
}
