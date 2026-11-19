import Foundation

/// SSE framing is decoded only after complete lines, so network splits cannot corrupt UTF-8.
struct AITextStream {
    let format: String
    private var line = Data()
    private var eventData: [String] = []
    private var output = ""
    private var stopped = false
    private(set) var completed = false

    mutating func consume(_ byte: UInt8) throws {
        if byte != 10 { line.append(byte); return }
        if line.last == 13 { line.removeLast() }
        guard let value = String(data: line, encoding: .utf8) else { throw aiError("The API returned invalid text encoding.") }
        line.removeAll(keepingCapacity: true)
        if value.isEmpty {
            guard !eventData.isEmpty else { return }
            let payload = eventData.joined(separator: "\n")
            eventData.removeAll(keepingCapacity: true)
            try event(payload)
        } else if value.hasPrefix("data:") {
            let content = value.dropFirst(5)
            eventData.append(String(content.first == " " ? content.dropFirst() : content))
        }
    }

    private mutating func event(_ payload: String) throws {
        if payload == "[DONE]" {
            guard format == "Chat Completions", stopped else { throw unfinished() }
            completed = true
            return
        }
        guard let object = try JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any] else { throw unfinished() }
        if object["error"] != nil { throw aiError("The API reported an error while generating text. Check your API settings and available credit.") }
        if format == "Chat Completions" {
            let choices = object["choices"] as? [[String: Any]] ?? []
            guard let choice = choices.first(where: { ($0["index"] as? Int ?? 0) == 0 }) else { return }
            if let delta = choice["delta"] as? [String: Any], let text = delta["content"] as? String { output.append(text) }
            if let reason = choice["finish_reason"] as? String {
                guard reason == "stop" else { throw unfinished() }
                stopped = true
            }
        } else {
            switch object["type"] as? String {
            case "response.output_text.delta":
                if let delta = object["delta"] as? String { output.append(delta) }
            case "response.completed":
                guard let response = object["response"] as? [String: Any], response["status"] as? String == "completed" else { throw unfinished() }
                // The final response is authoritative, including multiple output text parts.
                output = try AIClient.parse(data: JSONSerialization.data(withJSONObject: response), status: 200, format: format)
                completed = true
            case "response.failed", "response.incomplete", "error": throw unfinished()
            default: break
            }
        }
    }

    func result() throws -> String {
        guard completed else { throw unfinished() }
        let text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw aiError("The API returned no text. The request may have been refused.") }
        return text
    }
    private func unfinished() -> NSError {
        aiError("The API stopped before completing the text. No partial translation was inserted. Try a smaller selection or another model.")
    }
}
