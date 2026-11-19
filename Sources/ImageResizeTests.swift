import AppKit
import WebKit
import PDFKit

func runImageResizeTests() throws {
    func check(_ condition: Bool, _ message: String) throws { if !condition { throw aiError("Image resize test failed: " + message) } }
    let dialog = ImageSizeDialog(size: NSSize(width: 320, height: 160))
    dialog.width.stringValue = "160"; dialog.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: dialog.width))
    try check(dialog.height.doubleValue == 80, "Width edits preserve proportions")
    dialog.height.stringValue = "120"; dialog.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: dialog.height))
    try check(dialog.width.doubleValue == 240, "Height edits preserve proportions")
    dialog.proportional.state = .off; dialog.width.stringValue = "300"; dialog.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: dialog.width))
    try check(dialog.height.doubleValue == 120, "Proportions can be unlocked")
    try check(!ImageSizeDialog.valid(NSSize(width: CGFloat.infinity, height: 100)) && !ImageSizeDialog.valid(NSSize(width: 0, height: 100)), "Invalid sizes rejected")
    let fixture = NSImage(size: NSSize(width: 64, height: 64), flipped: false) { rect in
        NSColor(srgbRed: 1, green: 0, blue: 1, alpha: 1).setFill(); rect.fill(); return true
    }
    let bytes = try HTMLImages.png(fixture)
    let document = QLMDocument(); document.fileType = Format.html.type; document.htmlRich = true
    let content = NSMutableAttributedString(string: "Before\n")
    content.append(try HTMLImages.attachment(png: bytes, size: NSSize(width: 64, height: 64)))
    content.append(NSAttributedString(string: "\nAfter")); document.content = content
    document.makeWindowControllers(); let editor = document.editor!
    let range = NSRange(location: 7, length: 1); editor.text.setSelectedRange(range)
    try check(editor.selectedImage() != nil, "Selected attachment can be resized")
    try editor.resizeNativeImage(at: range, to: NSSize(width: 160, height: 80))
    func attachment() -> NSTextAttachment { editor.documentContent().attribute(.attachment, at: 7, effectiveRange: nil) as! NSTextAttachment }
    try check(attachment().bounds.size == NSSize(width: 160, height: 80) && attachment().contents == bytes, "Native resizing preserves original image bytes")
    try check(attachment().fileType == "public.png" && attachment().image(forBounds: attachment().bounds, textContainer: editor.text.textContainer, characterIndex: 7) != nil, "Resize retains an image type and renderable picture instead of a generic file attachment")
    let renderedImage = attachment().image(forBounds: attachment().bounds, textContainer: editor.text.textContainer, characterIndex: 7)!
    let bitmap = NSBitmapImageRep(data: renderedImage.tiffRepresentation!)!
    var magenta = 0
    for y in 0..<bitmap.pixelsHigh {
        for x in 0..<bitmap.pixelsWide {
            if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), color.redComponent > 0.8 && color.blueComponent > 0.8 && color.greenComponent < 0.6 { magenta += 1 }
        }
    }
    try check(magenta > 1000, "TextKit renders the picture pixels rather than a generic file icon")
    let saved = try document.data(ofType: Format.html.type)
    let loaded = QLMDocument(); try loaded.read(from: saved, ofType: Format.html.type)
    let reloaded = loaded.content.attribute(.attachment, at: 7, effectiveRange: nil) as! NSTextAttachment
    try check(reloaded.bounds.size == NSSize(width: 160, height: 80) && loaded.content.string == content.string, "Resized HTML reopens with dimensions and surrounding text intact")
    editor.text.undoManager?.undo()
    try check(attachment().bounds.size == NSSize(width: 64, height: 64), "Undo restores old dimensions")
    editor.text.undoManager?.redo()
    try check(attachment().bounds.size == NSSize(width: 160, height: 80), "Redo restores resized dimensions")
    // Repair an attachment created by the old resize path, which lost its type.
    let untyped = NSTextAttachment(data: bytes, ofType: nil)
    untyped.bounds = NSRect(x: 0, y: 0, width: 160, height: 80)
    editor.text.insertText(NSAttributedString(attachment: untyped), replacementRange: range)
    try editor.resizeNativeImage(at: range, to: NSSize(width: 120, height: 60))
    try check(attachment().fileType == "public.png" && attachment().image(forBounds: attachment().bounds, textContainer: editor.text.textContainer, characterIndex: 7) != nil && attachment().contents == bytes, "Resizing repairs an older untyped attachment without losing its image")
    document.updateChangeCount(.changeCleared); editor.close()
    let page = QLMDocument(); page.fileType = Format.html.type
    let source = "<!DOCTYPE html><html><body><p>Before</p><img alt=\"Keep alt\" style=\"width:64px;height:64px\" src=\"data:image/png;base64,\(bytes.base64EncodedString())\"/><p>After</p></body></html>"
    try page.read(from: Data(source.utf8), ofType: Format.html.type); page.makeWindowControllers()
    let web = page.editor!.htmlPreview!
    let deadline = Date().addingTimeInterval(10)
    while !web.editingReady && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
    try check(web.editingReady, "Rendered page ready")
    func javascript(_ script: String) throws -> Any {
        var result: Result<Any, Error>?
        web.evaluateJavaScript(script, in: nil, in: .defaultClient) { result = $0 }
        let deadline = Date().addingTimeInterval(5)
        while result == nil && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.005)) }
        guard let result else { throw aiError("Image script timed out") }; return try result.get()
    }
    _ = try javascript("document.querySelector('img').dispatchEvent(new MouseEvent('mousedown',{bubbles:true}));true")
    try check(try javascript(EditorController.captureImageSelection) is [String: Double], "Clicked rendered image is captured")
    page.editor!.resizeWebImage(NSSize(width: 160, height: 80), web: web, generation: web.editingGeneration)
    try check(try javascript("const img=document.querySelector('img');img.getBoundingClientRect().width===160 && img.getBoundingClientRect().height===80") as? Bool == true, "Rendered image changes dimensions")
    let output = String(data: try page.data(ofType: Format.html.type), encoding: .utf8)!
    try check(output.contains(bytes.base64EncodedString()) && output.contains("width=\"160.0\"") && output.contains("Keep alt") && output.contains("After"), "Rendered resize saves image bytes, attributes, and surrounding text")
    _ = try javascript("document.execCommand('undo');document.body.dispatchEvent(new Event('input',{bubbles:true}));true")
    try check(try javascript("document.querySelector('img').getBoundingClientRect().width===64") as? Bool == true, "Rendered resize supports undo")
    page.updateChangeCount(.changeCleared); page.editor?.close()
    print("Verified proportional image resizing, bounds, preserved bytes, HTML persistence, native undo/redo, and rendered HTML undo.")
}
