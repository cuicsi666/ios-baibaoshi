import Foundation

final class ServerAPI {
    static let shared = ServerAPI()
    private init() {}

    var baseURL: String {
        let s = UserDefaults.standard.string(forKey: "serverURL") ?? "http://6.6.6.130:8901"
        return s.hasSuffix("/") ? String(s.dropLast()) : s
    }

    /// 上传音频做语音识别（小米 mimo-v2.5），返回转写文字
    func transcribe(audioURL: URL) async throws -> String {
        var request = URLRequest(url: URL(string: "\(baseURL)/asr")!)
        request.httpMethod = "POST"
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)",
                         forHTTPHeaderField: "Content-Type")
        var body = Data()
        func append(_ s: String) { body.append(s.data(using: .utf8)!) }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"voice.wav\"\r\n")
        append("Content-Type: audio/wav\r\n\r\n")
        body.append(try Data(contentsOf: audioURL))
        append("\r\n--\(boundary)--\r\n")
        request.httpBody = body

        let (data, resp) = try await URLSession.shared.data(for: request)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        struct R: Decodable { let text: String }
        return try JSONDecoder().decode(R.self, from: data).text
    }

    /// 文字对话：小龙虾回复（服务端同时推送飞书播报会话，feishu-voice 自动播放）
    func chat(text: String) async throws -> String {
        var request = URLRequest(url: URL(string: "\(baseURL)/chat")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["text": text])
        let (data, resp) = try await URLSession.shared.data(for: request)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        struct R: Decodable { let reply: String }
        return try JSONDecoder().decode(R.self, from: data).reply
    }
}