import AppKit

func runAITests(editor: EditorController) throws {
    func check(_ value: Bool, _ message: String) throws { if !value { throw aiError("Test failed: " + message) } }
    try check(translationLanguages.count == 24 && translationLanguages == translationLanguages.sorted(), "FENNEC languages in alphabetical order")
    var config = AIConfiguration(); config.endpoint = "https://api.example.test/v1/responses"; config.model = "gpt-6-luna"; config.apiFormat = "Responses"; config.streaming = false
    let request = try AIClient.request(config: config, key: "test-placeholder", text: "Only selected text", instruction: "Rewrite")
    let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
    try check(body["input"] as? String == "Only selected text" && body["store"] as? Bool == false && body["model"] as? String == "gpt-6-luna", "Responses payload: selected text only, no storage, exact model")
    try check(body["stream"] as? Bool == false && request.timeoutInterval == 600, "Explicit streaming opt-out with longer inactivity timeout")
    func streamed(_ payload: String, format: String) throws -> String {
        var stream = AITextStream(format: format)
        for byte in payload.utf8 { try stream.consume(byte) }
        return try stream.result()
    }
    let chatStream = ": heartbeat\r\n\r\ndata: {\"choices\":[{\"index\":0,\"delta\":{\"content\":\"ترجمة 🌿\"},\"finish_reason\":null}]}\r\n\r\ndata: {\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n"
    try check(try streamed(chatStream, format: "Chat Completions") == "ترجمة 🌿", "Streaming preserves Arabic and emoji across individual UTF-8 bytes")
    for payload in ["data: {\"choices\":[{\"delta\":{\"content\":\"partial\"}}]}\n\n", "data: {\"choices\":[{\"finish_reason\":\"length\"}]}\n\ndata: [DONE]\n\n", "data: {\"type\":\"response.incomplete\"}\n\n"] {
        do { _ = try streamed(payload, format: payload.contains("response.incomplete") ? "Responses" : "Chat Completions"); throw NSError(domain: "test", code: 0) }
        catch let error as NSError { try check(error.domain == "qlm.AI", "Interrupted or truncated streams must not insert partial text") }
    }
    let completedStream = "event: response.completed\ndata: {\"type\":\"response.completed\",\n" + "data: \"response\":{\"status\":\"completed\",\"output\":[{\"type\":\"message\",\"content\":[{\"type\":\"output_text\",\"text\":\"Complete\"}]}]}}\n\n"
    try check(try streamed(completedStream, format: "Responses") == "Complete", "Responses completion and multiline SSE data")
    let response = Data(#"{"status":"completed","output":[{"type":"reasoning","summary":[]},{"type":"message","content":[{"type":"output_text","text":"Rewritten text"}]}]}"#.utf8)
    try check(try AIClient.parse(data: response, status: 200, format: "Responses") == "Rewritten text", "Responses extraction")
    config.apiFormat = "Chat Completions"
    config.streaming = true
    let chat = try AIClient.request(config: config, key: "test-placeholder", text: "Selection", instruction: "Translate")
    let chatBody = try JSONSerialization.jsonObject(with: chat.httpBody!) as! [String: Any]
    try check((chatBody["messages"] as? [[String: String]])?.last?["content"] == "Selection", "Chat payload")
    try check(chatBody["stream"] as? Bool == true, "Streaming opt-in changes request payload")
    let chatResponse = Data(#"{"choices":[{"finish_reason":"stop","message":{"content":"ترجمة"}}]}"#.utf8)
    try check(try AIClient.parse(data: chatResponse, status: 200, format: "Chat Completions") == "ترجمة", "Chat response and Arabic")
    do { _ = try AIClient.parse(data: response, status: 401, format: "Responses"); throw NSError(domain: "test", code: 0) } catch let error as NSError { try check(error.domain == "qlm.AI", "HTTP error handling") }
    let incomplete = Data(#"{"status":"incomplete","output":[]}"#.utf8)
    do { _ = try AIClient.parse(data: incomplete, status: 200, format: "Responses"); throw NSError(domain: "test", code: 0) } catch let error as NSError { try check(error.domain == "qlm.AI", "Incomplete output must not be inserted") }
    var arc = config
    APIProvider.virginiaTechARC.apply(to: &arc)
    try check(arc.endpoint == APIProvider.arcEndpoint && arc.model == "DeepSeek-V4.1-Flash" && arc.apiFormat == "Chat Completions", "ARC preset configures endpoint, model, and protocol")
    let arcRequest = try AIClient.request(config: arc, key: "arc-test-placeholder", text: "Selection", instruction: "Rewrite")
    let arcBody = try JSONSerialization.jsonObject(with: arcRequest.httpBody!) as! [String: Any]
    try check(arcRequest.url?.absoluteString == APIProvider.arcEndpoint && arcBody["model"] as? String == "DeepSeek-V4.1-Flash" && arcBody["messages"] != nil && arcBody["input"] == nil, "ARC uses Chat Completions payload")
    try check(arcRequest.value(forHTTPHeaderField: "Authorization") == "Bearer arc-test-placeholder", "ARC bearer authentication")
    arc.model = "another-arc-model"
    try check(APIProvider.matching(endpoint: arc.endpoint, format: arc.apiFormat) == .virginiaTechARC, "ARC inferred with customized model")
    let suite = "com.willtaggart.qlm.tests." + UUID().uuidString
    let preferences = UserDefaults(suiteName: suite)!
    defer { preferences.removePersistentDomain(forName: suite) }
    let setupDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: setupDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: setupDirectory) }
    let setupFile = setupDirectory.appendingPathComponent(".qlm-api.json")
    var setup = AIConfiguration(defaults: preferences, fileURL: setupFile)
    setup.endpoint = "https://provider.example.test/v1/chat/completions"
    setup.model = "saved-model"; setup.apiFormat = "Chat Completions"; setup.rewrite = "Keep my voice."; setup.streaming = true
    try setup.saveSetup(newKey: " test-key ", fileURL: setupFile)
    let reopened = AIConfiguration(defaults: preferences, fileURL: setupFile)
    try check(reopened.endpoint == setup.endpoint && reopened.model == setup.model && reopened.apiFormat == setup.apiFormat && reopened.rewrite == setup.rewrite, "API setup persists in dotfile")
    try check(reopened.streaming, "Streaming preference persists in API setup")
    let legacyConfig = Data(#"{"endpoint":"https://example.test","model":"test","apiFormat":"Responses","rewrite":"Rewrite"}"#.utf8)
    try check(try JSONDecoder().decode(AIConfiguration.self, from: legacyConfig).streaming == true, "API setups without a streaming preference default to on")
    try check(try APISettingsFile.load(from: setupFile)?.keys[setup.endpoint] == "test-key", "API key saved in dotfile")
    try setup.saveSetup(newKey: "   ", fileURL: setupFile)
    try check(try APISettingsFile.load(from: setupFile)?.keys[setup.endpoint] == "test-key", "Blank field keeps saved key")
    try arc.saveSetup(newKey: "arc-test-key", fileURL: setupFile)
    let reopenedARC = AIConfiguration(defaults: preferences, fileURL: setupFile)
    try check(APIProvider.matching(endpoint: reopenedARC.endpoint, format: reopenedARC.apiFormat) == .virginiaTechARC && reopenedARC.model == "another-arc-model", "ARC provider and custom model restored")
    let savedKeys = try APISettingsFile.load(from: setupFile)!.keys
    try check(savedKeys[arc.endpoint] == "arc-test-key" && savedKeys[setup.endpoint] == "test-key", "Provider keys remain separate")
    let attributes = try FileManager.default.attributesOfItem(atPath: setupFile.path)
    try check((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600, "Dotfile permissions are 0600")
    let badFile = setupDirectory.appendingPathComponent("bad.json")
    try Data("broken json".utf8).write(to: badFile)
    do { try setup.saveSetup(newKey: "replacement", fileURL: badFile); throw NSError(domain: "test", code: 0) }
    catch let error as NSError { try check(error.domain == "qlm.AI", "Invalid existing configuration must not be overwritten") }
    for index in 0..<35 { RecentFiles.record(URL(fileURLWithPath: "/tmp/qlm-recent-\(index).txt"), in: preferences) }
    RecentFiles.record(URL(fileURLWithPath: "/tmp/qlm-recent-20.txt"), in: preferences)
    let recent = RecentFiles.urls(in: preferences)
    try check(recent.count == 30 && recent.first?.lastPathComponent == "qlm-recent-20.txt" && Set(recent).count == 30, "Persistent latest 30 unique recent files")
    let screenBounds = NSRect(x: -1440, y: 25, width: 1440, height: 875)
    let constrained = EditorController.boundedFrame(NSRect(x: -1300, y: 0, width: 5000, height: 1200), within: screenBounds)
    try check(constrained == screenBounds, "Oversized windows fit the usable screen, including negative monitor coordinates")
    let frameBefore = editor.window!.frame
    editor.text.string = "Original"
    let noWrap = NSMutableParagraphStyle(); noWrap.lineBreakMode = .byClipping; noWrap.headIndent = 800; noWrap.tailIndent = 2000
    editor.text.typingAttributes[.paragraphStyle] = noWrap
    let longProse = String(repeating: "Long rewritten passage with العربية and words. ", count: 2000)
    editor.insertGeneratedText(longProse, after: NSRange(location: 0, length: 8))
    try check(editor.window!.frame == frameBefore, "Long AI output preserves window size")
    let generatedStyle = editor.text.textStorage!.attribute(.paragraphStyle, at: 10, effectiveRange: nil) as! NSParagraphStyle
    try check(generatedStyle.lineBreakMode == .byWordWrapping && generatedStyle.headIndent == 0 && generatedStyle.tailIndent == 0, "AI prose soft-wraps without inherited oversized indents")
    try check(editor.text.string == "Original\n\n" + longProse, "Soft wrapping preserves generated paragraph characters")
    try check(abs(editor.text.frame.width - editor.scroll.contentView.bounds.width) < 1, "Long AI output stays inside viewport")
    editor.text.undoManager?.removeAllActions()
    let original = "Before. Original 🌿 text. After."
    editor.text.string = original
    let selected = (original as NSString).range(of: "Original 🌿 text.")
    editor.insertGeneratedText("Rewritten text.", after: selected)
    try check(editor.text.string == "Before. Original 🌿 text.\n\nRewritten text.\n\n After.", "Original and suffix preserved; blank line insertion; UTF-16 selection")
    editor.text.undoManager?.undo()
    try check(editor.text.string == original, "Generated insertion is undoable")
    print("Verified API payloads/parsers, error handling, 24 languages, Unicode-safe insertion, and undo without live API calls.")
}
