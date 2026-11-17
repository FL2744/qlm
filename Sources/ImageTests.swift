import AppKit

func runImageTests() throws {
    func check(_ value: Bool, _ message: String) throws { if !value { throw aiError("Image test failed: " + message) } }
    guard let inter = NSFont(name: "Inter-Regular", size: 18), let bold = NSFont(name: "Inter-Bold", size: 18) else { throw aiError("Install Inter Regular and Bold for HTML font integration tests.") }
    let styled = NSMutableAttributedString(string: "Inter offline & العربية\n", attributes: [.font: inter])
    styled.append(NSAttributedString(string: "Bold text", attributes: [.font: bold]))
    let fontHTML = try HTMLImages.encode(styled)
    let fontSource = String(data: fontHTML, encoding: .utf8)!
    try check(fontSource.contains("@font-face") && fontSource.contains("data:font/otf;base64,") && !fontSource.contains("https://"), "HTML embeds font bytes without remote dependencies")
    let restored = try HTMLImages.decode(fontHTML)
    try check(restored.string == styled.string && (restored.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.fontName == inter.fontName && (restored.attribute(.font, at: restored.length - 1, effectiveRange: nil) as? NSFont)?.fontName == bold.fontName, "HTML font faces, sizes, and Unicode round-trip")
    try check((restored.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize == 18, "HTML preserves point size")
    let sourceHTML = "<!DOCTYPE html><html><head><style>body{font-family:'Inter',Helvetica,sans-serif}</style></head><body>Offline Inter</body></html>"
    let embeddedSource = try HTMLFonts.embedSource(sourceHTML)
    try check(embeddedSource.contains("@font-face") && embeddedSource.hasPrefix("<!DOCTYPE html>"), "Source HTML embeds declared font families and preserves doctype")
    try check(try HTMLFonts.embedSource(embeddedSource) == embeddedSource, "Repeat saves do not duplicate embedded fonts")
    let standardHTML = "<p style=\"font-family:Helvetica,Arial,sans-serif\">Standard</p>"
    try check(try HTMLFonts.embedSource(standardHTML) == standardHTML, "Standard fonts retain fallback list without embedding")
    do { _ = try HTMLFonts.embedSource("<p style=\"font-family:QLM-Missing-Font-83729\">Missing</p>"); throw NSError(domain: "test", code: 0) }
    catch let error as NSError { try check(error.domain == "qlm.AI", "Missing font produces actionable save error") }
    let fontFixture = URL(fileURLWithPath: ProcessInfo.processInfo.environment["QLM_TEST_OUTPUT"] ?? NSTemporaryDirectory()).appendingPathComponent("qlm-font-test.html")
    try fontHTML.write(to: fontFixture)
    let styledDoc = QLMDocument(); styledDoc.fileType = Format.rtf.type; styledDoc.content = styled
    styledDoc.makeWindowControllers()
    try check((styledDoc.editor!.text.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.fontName == inter.fontName, "Opening rich content retains chosen font")
    let exported = try styledDoc.data(ofType: Format.html.type)
    try check(String(data: exported, encoding: .utf8)!.contains("@font-face"), "RTF to HTML embeds fonts")
    styledDoc.updateChangeCount(.changeCleared); styledDoc.editor?.close()
    let titleSource = HTMLPage.withTitle("notes & <draft>", in: "<!DOCTYPE html><html><head><title>Old</title><meta charset=\"utf-8\"/></head><body>Words</body></html>")
    try check(titleSource.contains("<title>notes &amp; &lt;draft&gt;</title>") && !titleSource.contains("<title>Old</title>") && titleSource.hasPrefix("<!DOCTYPE html>"), "HTML title uses escaped filename and preserves doctype")
    try check(HTMLPage.withTitle("test", in: "<p>Words</p>").contains("<title>test</title>"), "Title added to HTML fragments")
    let titleDoc = QLMDocument(); titleDoc.fileType = Format.html.type; titleDoc.htmlRich = true
    titleDoc.content = NSAttributedString(string: "Title test")
    titleDoc.fileURL = URL(fileURLWithPath: "/tmp/old-title.html")
    let titleDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: titleDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: titleDirectory) }
    let titleURL = titleDirectory.appendingPathComponent("test.html")
    var saveDone = false; var saveError: Error?
    titleDoc.save(to: titleURL, ofType: Format.html.type, for: .saveAsOperation) { error in saveError = error; saveDone = true }
    let deadline = Date().addingTimeInterval(10)
    while !saveDone && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
    if let error = saveError { throw error }
    try check(saveDone, "Save As completes")
    try check(try String(contentsOf: titleURL, encoding: .utf8).contains("<title>test</title>"), "Save As uses new destination filename rather than previous filename")
    titleDoc.updateChangeCount(.changeCleared)
    let favicon = try HTMLPage.withFavicon(in: "<html><head><link rel=\"shortcut icon\" href=\"old.ico\"/></head><body>Words</body></html>")
    try check(favicon.contains("data:image/png;base64,") && !favicon.contains("old.ico"), "Embedded favicon replaces old favicon")
    try check(try HTMLPage.withFavicon(in: favicon) == favicon, "Repeated saves retain a single favicon")
    let savedTitleSource = try String(contentsOf: titleURL, encoding: .utf8)
    try check(savedTitleSource.contains("id=\"qlm-favicon\""), "Formatted HTML save includes favicon")
    let sourceIconDoc = QLMDocument(); sourceIconDoc.fileType = Format.html.type
    sourceIconDoc.fileURL = URL(fileURLWithPath: "/tmp/source-icon-test.html")
    sourceIconDoc.content = NSAttributedString(string: "<html><head><title>Before</title></head><body>Source</body></html>")
    let sourceIconData = try sourceIconDoc.data(ofType: Format.html.type)
    let sourceIconHTML = String(data: sourceIconData, encoding: .utf8)!
    try check(sourceIconHTML.contains("<title>source-icon-test</title>") && sourceIconHTML.contains("id=\"qlm-favicon\""), "HTML source save includes favicon and filename title")
    let faviconURL = Bundle.main.url(forResource: "Favicon", withExtension: "png")!
    let faviconImage = NSBitmapImageRep(data: try Data(contentsOf: faviconURL))!
    try check(faviconImage.pixelsWide == 64 && faviconImage.pixelsHigh == 64, "Bundled 64-pixel favicon")
    let bytes = try Data(contentsOf: Bundle.main.url(forResource: "Wordmark", withExtension: "png")!)
    let doc = QLMDocument(); doc.fileType = Format.txt.type
    doc.content = NSAttributedString(string: "Before <image> & words.\nمرحباً بالعالم\n")
    doc.fileURL = URL(fileURLWithPath: "/tmp/qlm-image-original.txt")
    doc.makeWindowControllers()
    let editor = doc.editor!
    let original = editor.text.string
    editor.text.setSelectedRange(NSRange(location: (original as NSString).length, length: 0))
    try editor.insertImageData([bytes])
    try check(doc.format == .html && doc.htmlRich && doc.fileURL == nil && doc.displayName.hasSuffix(".html"), "Automatic HTML conversion with original path detached")
    try check(HTMLImages.containsImages(editor.documentContent()) && editor.text.isRichText, "Visible image attachment")
    editor.window?.contentView?.layoutSubtreeIfNeeded()
    editor.updateContainer()
    let preview = URL(fileURLWithPath: ProcessInfo.processInfo.environment["QLM_TEST_OUTPUT"] ?? NSTemporaryDirectory()).appendingPathComponent("qlm-image-window.png")
    try editor.windowImage("png").write(to: preview)
    let html = try doc.data(ofType: Format.html.type)
    let source = String(data: html, encoding: .utf8)!
    try check(source.contains("data:image/png;base64,") && source.contains("&lt;image&gt; &amp; words."), "Self-contained image and escaped text")
    try html.write(to: URL(fileURLWithPath: ProcessInfo.processInfo.environment["QLM_TEST_OUTPUT"] ?? NSTemporaryDirectory()).appendingPathComponent("qlm-image-test.html"))
    let reloaded = QLMDocument(); reloaded.fileType = Format.html.type
    try reloaded.read(from: html, ofType: Format.html.type)
    try check(reloaded.htmlRich && reloaded.content.string == editor.text.string && HTMLImages.containsImages(reloaded.content), "HTML image/text/Unicode round-trip")
    let ordinaryHTML = QLMDocument(); ordinaryHTML.fileType = Format.html.type
    try ordinaryHTML.read(from: Data("<h1>Editable source</h1>".utf8), ofType: Format.html.type)
    try check(!ordinaryHTML.htmlRich && ordinaryHTML.content.string == "<h1>Editable source</h1>", "Existing HTML source editing")
    editor.text.undoManager?.undo()
    try check(editor.text.string == original && !HTMLImages.containsImages(editor.documentContent()), "Image insertion undo")
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    pasteboard.setData(bytes, forType: .png)
    try check(editor.text.readSelection(from: pasteboard, type: .png), "Native image paste hook")
    try check(HTMLImages.containsImages(editor.documentContent()), "Pasted image retained")
    let output = URL(fileURLWithPath: ProcessInfo.processInfo.environment["QLM_TEST_OUTPUT"] ?? NSTemporaryDirectory()).appendingPathComponent("qlm-image-test.html")
    try doc.data(ofType: Format.html.type).write(to: output)
    doc.updateChangeCount(.changeCleared)
    editor.close()
    print("Verified image insertion/paste, automatic HTML conversion, embedded PNG, Unicode round-trip, source HTML preservation, and undo.")
}
