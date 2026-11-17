import AppKit
import SwiftUI
import Darwin

enum APIProvider: String, CaseIterable {
    case openAI = "OpenAI"
    case virginiaTechARC = "Virginia Tech ARC"
    case custom = "Custom"

    static let arcEndpoint = "https://llm-api.arc.vt.edu/api/v1/chat/completions"
    static func matching(endpoint: String, format: String) -> APIProvider {
        if endpoint == arcEndpoint && format == "Chat Completions" { return .virginiaTechARC }
        if endpoint == "https://api.openai.com/v1/responses" && format == "Responses" { return .openAI }
        return .custom
    }
    func apply(to configuration: inout AIConfiguration) {
        switch self {
        case .openAI:
            configuration.endpoint = "https://api.openai.com/v1/responses"
            configuration.apiFormat = "Responses"
            configuration.model = "gpt-6-luna"
        case .virginiaTechARC:
            configuration.endpoint = Self.arcEndpoint
            configuration.apiFormat = "Chat Completions"
            configuration.model = "DeepSeek-V4.1-Flash"
        case .custom: break
        }
    }
}

struct AIConfiguration: Codable {
    static let defaultRewrite = "Rewrite this text for clarity, flow, and concision while preserving its meaning, voice, factual claims, and original language. Return only the rewritten text."
    var endpoint: String
    var model: String
    var apiFormat: String
    var rewrite: String
    init(defaults: UserDefaults = .standard, fileURL: URL = APISettingsFile.url) {
        if let saved = try? APISettingsFile.load(from: fileURL) { self = saved.configuration; return }
        endpoint = defaults.string(forKey: "ai.endpoint") ?? "https://api.openai.com/v1/responses"
        model = defaults.string(forKey: "ai.model") ?? "gpt-6-luna"
        apiFormat = defaults.string(forKey: "ai.format") ?? "Responses"
        rewrite = defaults.string(forKey: "ai.rewrite") ?? Self.defaultRewrite
    }
    var summary: String { "\(URL(string: endpoint)?.host ?? endpoint) · \(model) · \(apiFormat)" }
    func saveSetup(newKey: String, fileURL: URL = APISettingsFile.url) throws {
        _ = try validatedURL()
        guard !rewrite.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw aiError("Enter rewrite instructions.") }
        var keys = try APISettingsFile.load(from: fileURL)?.keys ?? [:]
        let key = newKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty { keys[endpoint] = key }
        try APISettingsFile.write(StoredAPISetup(configuration: self, keys: keys), to: fileURL)
    }
    func validatedURL() throws -> URL {
        guard let url = URL(string: endpoint), url.scheme == "https", url.host != nil, url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else {
            throw aiError("Enter a complete HTTPS API endpoint without credentials or query parameters.")
        }
        guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw aiError("Enter an API model in Settings.") }
        return url
    }
}
func aiError(_ message: String) -> NSError { NSError(domain: "qlm.AI", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }

struct StoredAPISetup: Codable {
    var configuration: AIConfiguration
    var keys: [String: String]
}

enum APISettingsFile {
    static let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".qlm-api.json")
    static func load(from url: URL = url) throws -> StoredAPISetup? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let info = try FileManager.default.attributesOfItem(atPath: url.path)
        guard info[.type] as? FileAttributeType == .typeRegular else { throw aiError("The API setup path must be a regular file.") }
        do { return try JSONDecoder().decode(StoredAPISetup.self, from: Data(contentsOf: url)) }
        catch { throw aiError("Could not read the API setup file. Check \(url.path) before saving again.") }
    }
    static func write(_ setup: StoredAPISetup, to url: URL = url) throws {
        // Validate an existing file before replacing it, including malformed files.
        _ = try load(from: url)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(setup)
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".qlm-api-" + UUID().uuidString + ".tmp")
        let descriptor = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode_t(0o600))
        guard descriptor >= 0 else { throw aiError("Could not create the private API setup file.") }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close(); try? FileManager.default.removeItem(at: temporary) }
        try handle.write(contentsOf: data)
        try handle.synchronize()
        try handle.close()
        guard rename(temporary.path, url.path) == 0 else { throw aiError("Could not save the API setup file.") }
    }
    static func ensureExists() throws {
        if try load() == nil { try write(StoredAPISetup(configuration: AIConfiguration(), keys: [:])) }
    }
}

enum APIKeyStore {
    static func status(_ endpoint: String) -> String {
        do {
            let key = try read(endpoint)
            return key.isEmpty ? "No API key saved for this endpoint in ~/.qlm-api.json." : "API key saved in ~/.qlm-api.json."
        } catch { return error.localizedDescription }
    }
    static func read(_ endpoint: String) throws -> String { try APISettingsFile.load()?.keys[endpoint] ?? "" }
    static func write(_ key: String, endpoint: String) throws {
        var setup = try APISettingsFile.load() ?? StoredAPISetup(configuration: AIConfiguration(), keys: [:])
        if key.isEmpty { setup.keys.removeValue(forKey: endpoint) } else { setup.keys[endpoint] = key }
        try APISettingsFile.write(setup)
    }
}

final class NoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

enum AIClient {
    static func request(config: AIConfiguration, key: String, text: String, instruction: String) throws -> URLRequest {
        var request = URLRequest(url: try config.validatedURL())
        guard !key.isEmpty else { throw aiError("Add your API key in qlm → Settings before using Rewrite or Translate.") }
        request.httpMethod = "POST"; request.timeoutInterval = 120
        request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any]
        if config.apiFormat == "Chat Completions" {
            body = ["model": config.model, "messages": [["role": "system", "content": instruction], ["role": "user", "content": text]]]
        } else {
            body = ["model": config.model, "instructions": instruction, "input": text, "store": false]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }
    static func parse(data: Data, status: Int, format: String) throws -> String {
        guard (200..<300).contains(status) else { throw aiError("The API returned HTTP \(status). Check the endpoint, model, key, and available API credit in Settings.") }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw aiError("The API returned an unreadable response.") }
        if let state = json["status"] as? String, ["incomplete", "failed", "cancelled"].contains(state) { throw aiError("The API did not complete the text. Try a shorter selection or another model.") }
        let output: String
        if format == "Chat Completions" {
            let choices = json["choices"] as? [[String: Any]] ?? []
            if let reason = choices.first?["finish_reason"] as? String, reason != "stop" { throw aiError("The API did not finish the text (\(reason)). Try a shorter selection.") }
            output = ((choices.first?["message"] as? [String: Any])?["content"] as? String) ?? ""
        } else {
            output = (json["output"] as? [[String: Any]] ?? []).filter { $0["type"] as? String == "message" }.flatMap { $0["content"] as? [[String: Any]] ?? [] }.filter { $0["type"] as? String == "output_text" }.compactMap { $0["text"] as? String }.joined(separator: "\n")
        }
        let result = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { throw aiError("The API returned no text. The request may have been refused.") }
        return result
    }
    static func generate(config: AIConfiguration, key: String, text: String, instruction: String) async throws -> String {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false; configuration.urlCache = nil
        let session = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request(config: config, key: key, text: text, instruction: instruction))
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else { throw aiError("No HTTP response from the API.") }
        return try parse(data: data, status: response.statusCode, format: config.apiFormat)
    }
}

let translationLanguages = ["English", "Arabic", "Chinese", "Japanese", "French", "German", "Italian", "Spanish", "Portuguese", "Russian", "Korean", "Hindi", "Bengali", "Urdu", "Persian", "Turkish", "Hebrew", "Greek", "Dutch", "Polish", "Ukrainian", "Swahili", "Vietnamese", "Indonesian"].sorted()

final class SettingsController: NSWindowController {
    static let shared = SettingsController()
    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 700), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "qlm Settings"; window.isReleasedWhenClosed = false
        super.init(window: window)
        window.contentViewController = NSHostingController(rootView: SettingsView())
        window.center()
    }
    required init?(coder: NSCoder) { fatalError() }
    func open() { window?.appearance = NSAppearance(named: UserDefaults.standard.string(forKey: "appearance") == "dark" ? .darkAqua : .aqua); window?.contentViewController = NSHostingController(rootView: SettingsView()); showWindow(nil); window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
}

struct SettingsView: View {
    @State private var endpoint = AIConfiguration().endpoint
    @State private var model = AIConfiguration().model
    @State private var format = AIConfiguration().apiFormat
    @State private var prompt = AIConfiguration().rewrite
    @State private var key = ""
    @State private var keyStatus = ""
    @State private var savedSummary = FileManager.default.fileExists(atPath: APISettingsFile.url.path) ? "Saved setup: " + AIConfiguration().summary : "No API setup saved yet."
    @State private var message = ""
    @State private var provider = APIProvider.matching(endpoint: AIConfiguration().endpoint, format: AIConfiguration().apiFormat)
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("qlm").font(.system(size: 18, weight: .black))
            Text("Rewrite & translation").font(.custom("Helvetica", size: 12)).bold()
            Text("Only the selected text is sent when you request a rewrite or translation. Usage limits and charges depend on your provider.").foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Text("Provider").frame(width: 90, alignment: .leading)
                Picker("Provider", selection: $provider) {
                    ForEach(APIProvider.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.labelsHidden().onChange(of: provider) { _, selected in
                    guard selected != .custom else { return }
                    var config = AIConfiguration()
                    selected.apply(to: &config)
                    endpoint = config.endpoint; model = config.model; format = config.apiFormat
                    key = ""; keyStatus = APIKeyStore.status(config.endpoint); message = ""
                }
            }
            if provider == .virginiaTechARC {
                HStack(alignment: .top) {
                    Text("Use your personal ARC key. Create it in Profile → Settings → Account → API keys.")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Link("Get ARC key", destination: URL(string: "https://llm.arc.vt.edu")!)
                }
            }
            HStack { Text("API format").frame(width: 90, alignment: .leading); Picker("API format", selection: $format) { Text("OpenAI Responses").tag("Responses"); Text("Chat Completions").tag("Chat Completions") }.labelsHidden().onChange(of: format) { updateProvider() } }
            HStack { Text("Endpoint").frame(width: 90, alignment: .leading); TextField("https://api.openai.com/v1/responses", text: $endpoint).textFieldStyle(.roundedBorder).onChange(of: endpoint) { key = ""; keyStatus = APIKeyStore.status(endpoint.trimmingCharacters(in: .whitespacesAndNewlines)); message = ""; updateProvider() } }
            HStack { Text("Model").frame(width: 90, alignment: .leading); TextField("gpt-6-luna", text: $model).textFieldStyle(.roundedBorder) }
            HStack { Text("API key").frame(width: 90, alignment: .leading); SecureField("Leave blank to keep an existing key", text: $key).textFieldStyle(.roundedBorder) }
            Text(keyStatus).foregroundStyle(.secondary).accessibilityLabel("Saved API key status")
            Text("Saved in ~/.qlm-api.json (read/write for your account only). Leave the key blank to keep the saved key.").foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("Rewrite instructions").bold()
            TextEditor(text: $prompt).font(.custom("Helvetica", size: 12)).frame(height: 96).overlay(Rectangle().stroke(Color.secondary.opacity(0.25)))
            HStack {
                Button("Restore default instructions") { prompt = AIConfiguration.defaultRewrite }
                Spacer()
                Button("Remove saved key") {
                    do { try APIKeyStore.write("", endpoint: endpoint.trimmingCharacters(in: .whitespacesAndNewlines)); key = ""; keyStatus = APIKeyStore.status(endpoint.trimmingCharacters(in: .whitespacesAndNewlines)); message = "Key removed." } catch { message = error.localizedDescription }
                }
            }
            Text(savedSummary).foregroundStyle(.secondary).lineLimit(2)
            HStack {
                Text(message).foregroundStyle(.secondary).lineLimit(3)
                Spacer()
                Button("Save API Setup") {
                    var config = AIConfiguration()
                    config.endpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines); config.model = model.trimmingCharacters(in: .whitespacesAndNewlines); config.apiFormat = format; config.rewrite = prompt
                    do {
                        try config.saveSetup(newKey: key)
                        key = ""
                        keyStatus = APIKeyStore.status(config.endpoint)
                        savedSummary = "Saved setup: " + config.summary
                        message = "API setup saved. It will be restored when you reopen qlm."
                    } catch { message = error.localizedDescription }
                }.keyboardShortcut(.defaultAction)
            }
            Text("⌘R  Rewrite selection     ⌘T  Translate selection").foregroundStyle(.secondary)
        }.font(.custom("Helvetica", size: 12)).padding(26).frame(width: 580, height: 700)
        .onAppear { keyStatus = APIKeyStore.status(endpoint.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }
    private func updateProvider() {
        let detected = APIProvider.matching(endpoint: endpoint.trimmingCharacters(in: .whitespacesAndNewlines), format: format)
        if provider != detected { provider = detected }
    }
}
