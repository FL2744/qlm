import AppKit

func runFontPickerTests() throws {
    func check(_ condition: Bool, _ message: String) throws { if !condition { throw aiError("Font picker test failed: " + message) } }
    let doc = QLMDocument(); doc.fileType = Format.rtf.type
    doc.content = NSAttributedString(string: "Selected untouched", attributes: [.font: NSFont(name: "Helvetica", size: 12)!, .foregroundColor: NSColor.black])
    doc.makeWindowControllers(); let editor = doc.editor!
    editor.text.setSelectedRange(NSRange(location: 0, length: 8))
    let font = NSFont(name: "Helvetica-BoldOblique", size: 18)!
    let red = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
    editor.applyFontAttributes([.font: font, .foregroundColor: red, .underlineStyle: NSUnderlineStyle.single.rawValue])
    let selected = editor.documentContent()
    try check((selected.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.fontName == font.fontName && (selected.attribute(.font, at: 10, effectiveRange: nil) as? NSFont)?.pointSize == 12, "Formatting only changes selected text")
    let html = try doc.data(ofType: Format.html.type)
    let source = String(data: html, encoding: .utf8)!
    try check(source.contains("color:#FF0000") && source.contains("text-decoration:underline") && source.contains("font-weight:700") && source.contains("font-style:italic"), "HTML preserves text color, underline, bold, and italic")
    let reopened = try HTMLImages.decode(html)
    let color = (reopened.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)?.usingColorSpace(.sRGB)
    try check(color?.redComponent == 1 && color?.greenComponent == 0 && reopened.attribute(.underlineStyle, at: 0, effectiveRange: nil) as? Int == NSUnderlineStyle.single.rawValue, "HTML text color and underline round-trip")
    editor.text.undoManager?.undo()
    try check((editor.documentContent().attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize == 12, "Undo restores original formatting")
    editor.text.undoManager?.redo()
    try check((editor.documentContent().attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize == 18, "Redo restores chosen formatting")
    let picker = FontPickerController(editor: editor); picker.open(); picker.window?.contentView?.layoutSubtreeIfNeeded()
    try check(picker.italic.frame.minX - picker.bold.frame.maxX >= 19 && picker.underline.frame.minX - picker.italic.frame.maxX >= 19, "Style controls have separate hit areas and 20-point gaps")
    try check(picker.colorButton.title == "Text Color…" && picker.colorButton.action != nil, "Explicit working color control")
    picker.family.stringValue = "Inter"
    picker.populateFaces(family: "Inter", selected: nil)
    let interMembers = NSFontManager.shared.availableMembers(ofFontFamily: "Inter") ?? []
    if !interMembers.isEmpty {
        try check(picker.face.numberOfItems == interMembers.count, "Every installed Inter style is offered")
        for item in picker.face.itemArray {
            editor.text.setSelectedRange(NSRange(location: 0, length: 8))
            picker.populateFaces(family: "Inter", selected: item.representedObject as? String)
            picker.size.stringValue = "24"
            picker.changeFont(picker.face)
            let chosen = editor.text.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
            try check(chosen?.fontName == item.representedObject as? String && chosen?.pointSize == 24, "Exact Inter face is applied: \(chosen?.fontName ?? "nil") expected \(item.representedObject ?? "nil")")
            picker.size.stringValue = "20"
            picker.changeFont(picker.size)
            try check((editor.text.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.fontName == item.representedObject as? String, "Resizing retains the chosen weight")
        }
    }
    picker.close(); doc.updateChangeCount(.changeCleared); editor.close()
    let plain = QLMDocument(); plain.fileType = Format.txt.type
    plain.content = NSAttributedString(string: "Selected untouched")
    plain.makeWindowControllers()
    let plainEditor = plain.editor!
    plainEditor.text.setSelectedRange(NSRange(location: 0, length: 8))
    plainEditor.applyFontAttributes([.font: font])
    try check((plainEditor.text.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize == 18 && (plainEditor.text.textStorage?.attribute(.font, at: 10, effectiveRange: nil) as? NSFont)?.pointSize == 12, "Plain text font changes affect selection only")
    let colors = FontPickerController(editor: plainEditor)
    let panel = NSColorPanel.shared
    panel.color = red
    colors.changeColor(panel)
    plainEditor.applyAppearance(lightMode: false)
    try check((plainEditor.text.textStorage?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor) == red, "Color picker applies selected color")
    try check(plainEditor.text.layoutManager?.temporaryAttribute(.foregroundColor, atCharacterIndex: 0, effectiveRange: nil) == nil, "Dark mode preserves chosen color")
    try check(try plain.data(ofType: Format.txt.type) == Data("Selected untouched".utf8), "Plain text saves no formatting markup")
    plain.updateChangeCount(.changeCleared); plainEditor.close()
    print("Verified font selection, color/underline HTML preservation, undo/redo, and spaced font controls.")
}
