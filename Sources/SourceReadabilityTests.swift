import AppKit

func runSourceReadabilityTests() throws {
    func check(_ condition: Bool, _ message: String) throws { if !condition { throw aiError("Source readability test failed: " + message) } }
    let options = NSApp.mainMenu?.item(withTitle: "Format")?.submenu?.item(withTitle: "Options")?.submenu
    let titles = options?.items.map(\.title) ?? []
    guard let image = titles.firstIndex(of: "Don't Hide Image Bytes in HTML") else { throw aiError("Missing source options") }
    try check(titles.dropFirst(image + 1).first == "Pretty-print Source…" && !titles.contains("Collapse Scripts and Styles"), "Source tools appear immediately after image-byte preference")
    var result: Result<[String], Error>?
    Task { @MainActor in
        do {
            let html = try await SourceFormatter().format("<html><head><style>body{color:red}</style></head><body><div><p>Hello</p></div><script>function f(x){return {answer:x+1};}</script></body></html>", parser: "html")
            let js = try await SourceFormatter().format("function f(x){const regex=/[{};]/g;return {answer:x+1,text:`hello ${x}`};}globalThis.neverExecute=true;", parser: "babel")
            let json = try await SourceFormatter().format("{\"nested\":{\"array\":[1,2,3]},\"arabic\":\"مرحبا\"}", parser: "json")
            result = .success([html, js, json])
        } catch { result = .failure(error) }
    }
    let deadline = Date().addingTimeInterval(40)
    while result == nil && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
    guard let result else { throw aiError("Source formatter test timed out") }
    let output = try result.get()
    try check(output[0].contains("\n") && output[0].contains("return { answer: x + 1 }"), "HTML preview formats embedded JavaScript and CSS offline")
    try check(output[1].contains("\n") && output[1].contains("/[{};]/g") && output[1].contains("`hello ${x}`"), "JavaScript parser preserves regex and template literals")
    try check(output[2].contains("مرحبا") && output[2].contains("\n"), "JSON formatting preserves Unicode")
    print("Verified offline HTML/JS/JSON formatting and source menu placement.")
}
