import AppKit
import WebKit

func runHyperlinkTests() throws {
    func check(_ condition: Bool, _ message: String) throws { if !condition { throw aiError("Hyperlink test failed: " + message) } }
    let url = try Hyperlinks.destination("example.com/path?q=one&b=two")
    try check(url.absoluteString == "https://example.com/path?q=one&b=two", "Bare domains use HTTPS")
    for bad in ["javascript:alert(1)", "https://", "https://bad host"] {
        do { _ = try Hyperlinks.destination(bad); throw aiError("Invalid link accepted") }
        catch { try check(error.localizedDescription != "Invalid link accepted", "Invalid destinations rejected") }
    }
    let document = QLMDocument(); document.fileType = Format.txt.type
    document.content = NSAttributedString(string: "Before العربية after")
    document.fileURL = URL(fileURLWithPath: "/tmp/qlm-original.txt")
    document.makeWindowControllers()
    let editor = document.editor!
    let selection = (editor.text.string as NSString).range(of: "العربية")
    editor.applyHyperlink(url, range: selection)
    try check(document.format == .html && document.htmlRich && document.fileURL == nil, "Plain document becomes HTML without overwriting its original")
    try check(editor.text.string == "Before العربية after", "Link preserves selected Arabic words and surrounding text")
    try check(editor.documentContent().attribute(.link, at: selection.location, effectiveRange: nil) as? URL == url, "Only selected text receives the destination")
    try check(editor.documentContent().attribute(.link, at: 0, effectiveRange: nil) == nil && editor.text.typingAttributes[.link] == nil, "Surrounding and subsequent text remain unlinked")
    let data = try document.data(ofType: Format.html.type)
    let html = String(data: data, encoding: .utf8)!
    try check(html.contains("<a href=\"https://example.com/path?q=one&amp;b=two\">"), "Saved HTML contains escaped clickable anchor")
    let reloaded = QLMDocument(); try reloaded.read(from: data, ofType: Format.html.type)
    try check(reloaded.content.attribute(.link, at: selection.location, effectiveRange: nil) as? URL == url, "Link survives HTML reopen")
    editor.text.undoManager?.undo()
    try check(editor.documentContent().attribute(.link, at: selection.location, effectiveRange: nil) == nil, "Undo removes inserted link")
    editor.text.undoManager?.redo()
    try check(editor.documentContent().attribute(.link, at: selection.location, effectiveRange: nil) as? URL == url, "Redo restores link")
    document.updateChangeCount(.changeCleared); editor.close()
    let markdown = QLMDocument(); markdown.fileType = Format.md.type; markdown.content = NSAttributedString(string: "A [label]")
    markdown.makeWindowControllers()
    markdown.editor!.applyHyperlink(url, range: NSRange(location: 2, length: 7))
    try check(markdown.format == .md && markdown.editor!.text.string == "A [\\[label\\]](<https://example.com/path?q=one&b=two>)", "Markdown keeps its format with escaped link syntax")
    markdown.updateChangeCount(.changeCleared); markdown.editor?.close()
    let page = QLMDocument(); page.fileType = Format.html.type
    try page.read(from: Data("<!DOCTYPE html><html><body><p>Selected words</p><p>Keep me</p></body></html>".utf8), ofType: Format.html.type)
    page.makeWindowControllers()
    let web = page.editor!.htmlPreview!
    let deadline = Date().addingTimeInterval(10)
    while !web.editingReady && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
    try check(web.editingReady, "Rendered editor ready")
    func javascript(_ script: String) throws -> Any {
        var result: Result<Any, Error>?
        web.evaluateJavaScript(script, in: nil, in: .defaultClient) { result = $0 }
        let deadline = Date().addingTimeInterval(5)
        while result == nil && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.005)) }
        guard let result else { throw aiError("Link script timed out") }; return try result.get()
    }
    _ = try javascript("const r=document.createRange();r.selectNodeContents(document.querySelector('p'));const s=window.getSelection();s.removeAllRanges();s.addRange(r);true")
    try check(try javascript(EditorController.captureLinkSelection) is [String: String], "Rendered selection is captured before dialog focus changes")
    page.editor!.applyWebHyperlink(url, web: web, generation: web.editingGeneration)
    try check(try javascript("document.querySelector('p a')?.getAttribute('href') || ''") as? String == url.absoluteString, "Rendered selected words become a hyperlink")
    let saved = String(data: try page.data(ofType: Format.html.type), encoding: .utf8)!
    try check(saved.contains("<a href=") && saved.contains("Selected words</a>") && saved.contains("Keep me"), "Rendered link saves with surrounding content intact")
    _ = try javascript("document.execCommand('undo');document.body.dispatchEvent(new Event('input',{bubbles:true}));true")
    try check(try javascript("document.querySelector('a') === null") as? Bool == true, "Rendered link insertion supports Undo")
    page.updateChangeCount(.changeCleared); page.editor?.close()
    let items = NSApp.mainMenu?.item(withTitle: "Insert")?.submenu?.items ?? []
    try check(items.contains { $0.action == #selector(EditorController.insertHyperlink(_:)) && $0.keyEquivalent == "h" }, "Command-H inserts a link")
    print("Verified selected hyperlinks, Arabic, HTML save/reopen, Markdown, rendered links, undo/redo, and URL validation.")
}
