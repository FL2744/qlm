import AppKit

func runHTMLSourceTests() throws {
    let previous = UserDefaults.standard.object(forKey: EditorController.showImageBytesKey)
    defer {
        if let previous { UserDefaults.standard.set(previous, forKey: EditorController.showImageBytesKey) }
        else { UserDefaults.standard.removeObject(forKey: EditorController.showImageBytesKey) }
    }
    UserDefaults.standard.set(false, forKey: EditorController.showImageBytesKey)
    func check(_ condition: Bool, _ message: String) throws { if !condition { throw aiError("HTML source test failed: " + message) } }
    let bytes = try Data(contentsOf: Bundle.main.url(forResource: "Favicon", withExtension: "png")!)
    let url = "data:image/png;base64," + bytes.base64EncodedString()
    let html = "<!DOCTYPE html><html><head><link rel=\"icon\" href=\"\(url)\"/></head><body>العربية<img alt=\"Pen\" src=\"\(url)\"/>More words</body></html>"
    let projection = HTMLSourceProjection(html)
    try check(!projection.display.contains(bytes.base64EncodedString()) && !projection.display.contains("data:image/png"), "Raw image and favicon bytes are hidden")
    try check(projection.display.contains("<!-- qlm: Embedded image") && projection.display.contains("64 × 64 px") && projection.display.contains("page icon (favicon)"), "Comments describe the hidden images")
    try check(try projection.expanded(projection.display) == html, "Source projection restores every original byte")
    try check(try projection.expanded(projection.display.replacingOccurrences(of: "More words", with: "Changed words")).contains("Changed words"), "Surrounding source can be edited")
    do { _ = try projection.expanded(projection.display + "qlm-embedded://image-unknown"); throw NSError(domain: "test", code: 0) }
    catch let error as NSError { try check(error.domain == "qlm.AI", "Unknown shorthand blocks saving") }
    let document = QLMDocument(); document.fileType = Format.html.type; document.htmlRich = true
    let rich = NSMutableAttributedString(string: "Before\n")
    rich.append(try HTMLImages.attachment(png: bytes)); rich.append(NSAttributedString(string: "\nAfter"))
    document.content = rich; document.makeWindowControllers()
    let editor = document.editor!
    editor.toggleHTMLSource(nil)
    try check(editor.htmlSourceView && editor.text.string.contains("qlm-embedded://") && !editor.text.string.contains(bytes.base64EncodedString()), "Source toggle displays shorthand")
    let originalSource = try editor.expandedHTMLSource()
    editor.toggleImageBytes(nil)
    try check(editor.text.string == originalSource && editor.htmlSourceProjection == nil, "Option reveals original image bytes immediately")
    editor.toggleImageBytes(nil)
    try check(!editor.text.string.contains(bytes.base64EncodedString()) && (try editor.expandedHTMLSource()) == originalSource, "Hiding again preserves all HTML and image bytes")
    let saved = try document.data(ofType: Format.html.type)
    let savedSource = String(data: saved, encoding: .utf8)!
    try check(!savedSource.contains("qlm-embedded://") && savedSource.contains(url), "Saving from Source view restores full image data")
    let reopened = QLMDocument(); reopened.fileType = Format.html.type
    try reopened.read(from: saved, ofType: Format.html.type)
    try check(HTMLImages.containsImages(reopened.content) && reopened.content.string == rich.string, "Image survives save/reopen from shorthand view")
    editor.toggleHTMLSource(nil)
    try check(document.htmlRich && HTMLImages.containsImages(editor.documentContent()), "Returning to rich view preserves the image")
    editor.toggleHTMLSource(nil)
    editor.insertSourceHTML("<img alt=\"New image\" src=\"\(url)\"/>")
    try check(!editor.text.string.contains(bytes.base64EncodedString()) && (try editor.expandedHTMLSource()).contains("New image"), "New images in Source view are compacted and retained")
    editor.text.insertText("<!-- surrounding edit -->", replacementRange: NSRange(location: 0, length: 0))
    let editedSave = String(data: try document.data(ofType: Format.html.type), encoding: .utf8)!
    try check(editedSave.contains(url) && editedSave.contains("surrounding edit") && !editedSave.contains("qlm-embedded://"), "Source edits save with complete image bytes")
    editor.toggleHTMLSource(nil)
    try check(!editor.text.string.contains("qlm-embedded://"), "Rendered HTML uses expanded source")
    document.updateChangeCount(.changeCleared); editor.close()
    print("Verified compact image/favicon source, lossless expansion, edited source saves, newly inserted images, and invalid-token errors.")
}
