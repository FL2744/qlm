import AppKit

extension EditorController {
    static func isHTMLSource(_ value: String) -> Bool {
        let source = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if source.range(of: "^<!doctype\\s+html\\b|^<(html|head|body)\\b", options: [.regularExpression, .caseInsensitive]) != nil { return true }
        // Require actual HTML markup, rather than comparisons, URLs or prose in brackets.
        return source.range(of: "(?s)^(?:<!--.*?-->\\s*)*<(?:a|abbr|article|aside|b|blockquote|button|caption|code|dd|details|div|dl|dt|em|fieldset|figcaption|figure|footer|form|h[1-6]|header|hr|i|img|input|label|li|link|main|meta|nav|ol|p|pre|section|select|small|span|strong|style|script|summary|table|tbody|td|textarea|th|thead|title|tr|ul|br)\\b(?:[^>\"']|\"[^\"]*\"|'[^']*')*>", options: [.regularExpression, .caseInsensitive]) != nil
    }
    func pasteHTMLContent(from pasteboard: NSPasteboard) -> Bool {
        // Keep the existing rendered-player behavior for standalone embed codes.
        if pasteEmbed(from: pasteboard) { return true }
        guard doc.format == .txt, !htmlSourceView,
              let source = pasteboard.string(forType: .string), Self.isHTMLSource(source) else { return false }
        let selection = text.selectedRange()
        let oldName = doc.displayName ?? "Untitled"
        doc.fileType = Format.html.type
        doc.fileURL = nil
        doc.displayName = (oldName as NSString).deletingPathExtension + ".html"
        doc.htmlRich = false
        htmlSourceView = true
        richHTMLSnapshot = nil
        richHTMLSource = nil
        htmlSourceProjection = nil
        loadFormatState()
        text.isAutomaticQuoteSubstitutionEnabled = false
        text.insertText(source, replacementRange: selection)
        text.undoManager?.setActionName("Paste HTML Source")
        doc.content = documentContent()
        htmlSourceView = false
        text.isAutomaticQuoteSubstitutionEnabled = true
        loadFormatState()
        updateContainer(); updateHTMLPresentation()
        return true
    }
}

func runHTMLPasteTests() throws {
    func check(_ condition: Bool, _ message: String) throws { if !condition { throw aiError("HTML paste test failed: " + message) } }
    for source in ["<!DOCTYPE html><html><body>Hello</body></html>", "  <div class='a>b'>العربية 🌿</div>", "<!-- note -->\n<script>window.example=1;</script>", "<img src='data:image/png;base64,YWJj'>"] {
        try check(EditorController.isHTMLSource(source), "Recognize document and fragment HTML")
    }
    for source in ["Ordinary words", "a < b && c > d", "<name>", "https://example.test", "const template = '<div>Hello</div>';"] {
        try check(!EditorController.isHTMLSource(source), "Leave ordinary text and code alone")
    }
    let board = NSPasteboard.withUniqueName(); defer { board.releaseGlobally() }
    let html = "<!DOCTYPE html><html><body><p>العربية 🌿</p><script>window.example=1;</script></body></html>"
    board.setString(html, forType: .string)
    let doc = QLMDocument(); doc.fileType = Format.txt.type
    doc.fileURL = URL(fileURLWithPath: "/tmp/qlm-original-html-paste-test.txt")
    doc.content = NSAttributedString(string: "Before\nReplace\nAfter")
    doc.makeWindowControllers(); let editor = doc.editor!
    editor.text.setSelectedRange((editor.text.string as NSString).range(of: "Replace"))
    try check(editor.text.readSelection(from: board, type: .string), "Clipboard hook handles HTML source")
    try check(doc.format == .html && doc.fileURL == nil && !doc.htmlRich && !editor.htmlSourceView && editor.scroll.isHidden && editor.htmlPreview != nil, "Saved TXT becomes a detached HTML draft shown as a rendered page")
    try check(try editor.expandedHTMLSource() == "Before\n" + html + "\nAfter", "Selected text replaced with literal HTML; surrounding text preserved")
    let readyDeadline = Date().addingTimeInterval(10)
    while editor.htmlPreview?.editingReady != true && Date() < readyDeadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
    try check(editor.htmlPreview?.editingReady == true, "Pasted HTML finishes rendering")
    let saved = String(data: try doc.data(ofType: Format.html.type), encoding: .utf8)!
    try check(saved.contains("window.example=1;") && saved.contains("العربية 🌿") && !saved.contains("&lt;script"), "HTML saves as markup, not escaped plain text")
    editor.text.undoManager?.undo()
    try check(editor.text.string == "Before\nReplace\nAfter", "Paste supports undo")
    editor.text.undoManager?.redo()
    editor.toggleHTMLSource(nil)
    try check(editor.htmlSourceView && !editor.scroll.isHidden && (try editor.expandedHTMLSource()).contains("<p>العربية 🌿</p>"), "View HTML Source reveals pasted markup on request")
    editor.toggleHTMLSource(nil)
    try check(!editor.htmlSourceView && editor.scroll.isHidden, "Source toggle returns to rendered page")
    doc.updateChangeCount(.changeCleared); editor.close()
    let js = QLMDocument(); js.fileType = Format.js.type; js.makeWindowControllers()
    try check(!js.editor!.pasteHTMLContent(from: board) && js.format == .js, "Explicit code formats are not converted")
    js.updateChangeCount(.changeCleared); js.editor?.close()
    print("Verified HTML source paste detection, automatic HTML draft conversion, literal source preservation, save and undo.")
}
