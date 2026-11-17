import AppKit
import WebKit

func runHTMLEmbedTests() throws {
    func check(_ condition: Bool, _ message: String) throws { if !condition { throw aiError("HTML embed test failed: " + message) } }
    let code = "<div style=\"background:#245640;color:white;padding:20px\"><h2>Rendered embed</h2><p>Words &amp; العربية</p></div>"
    let document = QLMDocument(); document.fileType = Format.txt.type
    document.content = NSAttributedString(string: "Before\nAfter")
    document.makeWindowControllers()
    let editor = document.editor!
    editor.text.setSelectedRange(NSRange(location: 7, length: 0))
    editor.insertEmbedHTML(code)
    try check(document.htmlRich && document.format == .html && HTMLEmbeds.contains(editor.documentContent()), "Inserting an embed creates formatted HTML")
    try check(editor.embedViews.count == 1 && !editor.text.string.contains("<div"), "Inline WebKit view replaces code while surrounding text remains editable")
    let bytes = try document.data(ofType: Format.html.type)
    let source = String(data: bytes, encoding: .utf8)!
    try check(source.contains("data-qlm-embed=") && source.contains("srcdoc="), "HTML contains portable embed source")
    let reloaded = QLMDocument(); reloaded.fileType = Format.html.type
    try reloaded.read(from: bytes, ofType: Format.html.type)
    var restoredCode = ""
    reloaded.content.enumerateAttribute(.attachment, in: NSRange(location: 0, length: reloaded.content.length)) { value, _, _ in
        if let embed = value as? HTMLEmbedAttachment { restoredCode = embed.html }
    }
    try check(restoredCode == code && reloaded.content.string == editor.text.string, "Embed source, Unicode, and surrounding text round-trip")
    editor.toggleHTMLSource(nil)
    try check(editor.htmlSourceView && editor.text.string.contains("srcdoc=") && editor.embedViews.isEmpty, "HTML Source reveals actual saved markup and hides players")
    editor.toggleHTMLSource(nil)
    try check(!editor.htmlSourceView && document.htmlRich && editor.embedViews.count == 1, "Returning from unchanged source restores editable document and player")
    let beforeTyping = editor.text.string
    editor.text.insertText(" Native typing works.", replacementRange: NSRange(location: (beforeTyping as NSString).length, length: 0))
    try check(editor.text.string.contains("Native typing works."), "Native rich editor remains writable after source round-trip")
    editor.toggleHTMLSource(nil)
    editor.text.insertText("<!-- Edited source -->", replacementRange: NSRange(location: 0, length: 0))
    editor.toggleHTMLSource(nil)
    try check(!document.htmlRich && editor.scroll.isHidden && editor.htmlPreview?.isHidden == false && !editor.text.string.contains(HTMLImages.marker), "Edited source stays intact in full HTML preview")
    guard let web = editor.htmlPreview else { throw aiError("Missing rendered editor") }
    let readyDeadline = Date().addingTimeInterval(10)
    while !web.editingReady && Date() < readyDeadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
    try check(web.editingReady, "Rendered HTML editor initializes")
    var editResult: Result<Any, Error>?
    web.evaluateJavaScript("document.body.appendChild(document.createTextNode(' Typed in rendered view.')); document.body.dispatchEvent(new Event('input',{bubbles:true})); document.body.isContentEditable", in: nil, in: .defaultClient) { editResult = $0 }
    let editDeadline = Date().addingTimeInterval(5)
    while editResult == nil && Date() < editDeadline { RunLoop.current.run(until: Date().addingTimeInterval(0.005)) }
    guard let editResult else { throw aiError("Rendered edit did not complete") }
    try check(try editResult.get() as? Bool == true, "Rendered document accepts typing")
    let savedAfterTyping = String(data: try document.data(ofType: Format.html.type), encoding: .utf8)!
    try check(savedAfterTyping.contains("Typed in rendered view.") && savedAfterTyping.contains("data-qlm-embed=") && !savedAfterTyping.contains("contenteditable=\"true\""), "Immediate save flushes rendered edits, retains embeds, and omits editor controls")
    editor.toggleHTMLSource(nil)
    try check(editor.htmlSourceView && !editor.scroll.isHidden && editor.text.string.contains("<!-- Edited source -->") && editor.text.string.contains("Typed in rendered view."), "Edited source can be reopened without losing rendered edits")
    document.updateChangeCount(.changeCleared); editor.close()
    let htmlDoc = QLMDocument(); htmlDoc.fileType = Format.html.type
    try htmlDoc.read(from: Data("<h1>Ordinary HTML</h1>".utf8), ofType: Format.html.type)
    htmlDoc.makeWindowControllers()
    try check(htmlDoc.editor!.scroll.isHidden && htmlDoc.editor!.htmlPreview != nil, "Ordinary HTML opens rendered by default")
    htmlDoc.updateChangeCount(.changeCleared); htmlDoc.editor?.close()
    print("Verified rendered HTML embeds, source toggle, edited-source preservation, HTML conversion, and source round-trip.")
}
