import AppKit

final class FontPickerController: NSWindowController {
    weak var editor: EditorController?
    let family = NSComboBox()
    let face = NSPopUpButton()
    var faceFamily = ""
    let size = NSTextField(string: "12")
    let bold = NSButton(checkboxWithTitle: "Bold", target: nil, action: nil)
    let italic = NSButton(checkboxWithTitle: "Italic", target: nil, action: nil)
    let underline = NSButton(checkboxWithTitle: "Underline", target: nil, action: nil)
    let colorButton = NSButton(title: "Text Color…", target: nil, action: nil)
    let applyButton = NSButton(title: "Apply", target: nil, action: nil)
    let swatch = NSButton(title: "", target: nil, action: nil)
    let status = NSTextField(wrappingLabelWithString: "")
    var selectedColor = NSColor.black
    init(editor: EditorController) {
        self.editor = editor
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 460, height: 365), styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
        panel.title = "Font"; panel.isReleasedWhenClosed = false; panel.hidesOnDeactivate = true
        super.init(window: panel)
        family.addItems(withObjectValues: NSFontManager.shared.availableFontFamilies.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
        family.completes = false; family.numberOfVisibleItems = 14
        family.target = self; family.action = #selector(changeFont(_:)); family.setAccessibilityLabel("Font family")
        size.target = self; size.action = #selector(changeFont(_:)); size.setAccessibilityLabel("Font size")
        size.widthAnchor.constraint(equalToConstant: 64).isActive = true
        family.widthAnchor.constraint(equalToConstant: 250).isActive = true
        func label(_ title: String) -> NSTextField { let value = NSTextField(labelWithString: title); value.widthAnchor.constraint(equalToConstant: 60).isActive = true; return value }
        let familyRow = NSStackView(views: [label("Family"), family]); familyRow.spacing = 14
        face.target = self; face.action = #selector(changeFont(_:)); face.setAccessibilityLabel("Font style")
        face.widthAnchor.constraint(equalToConstant: 250).isActive = true
        let faceRow = NSStackView(views: [label("Style"), face]); faceRow.spacing = 14
        let sizeRow = NSStackView(views: [label("Size"), size, NSTextField(labelWithString: "pt")]); sizeRow.spacing = 14
        for button in [bold, italic, underline] { button.target = self; button.action = button === underline ? #selector(changeUnderline(_:)) : #selector(changeFont(_:)); button.widthAnchor.constraint(equalToConstant: 110).isActive = true }
        let styles = NSStackView(views: [bold, italic, underline]); styles.spacing = 20; styles.distribution = .fillEqually
        swatch.isBordered = false; swatch.target = self; swatch.action = #selector(openColor(_:)); swatch.toolTip = "Choose text color"
        swatch.wantsLayer = true; swatch.layer?.cornerRadius = 4; swatch.layer?.borderWidth = 1; swatch.layer?.borderColor = NSColor.separatorColor.cgColor
        swatch.widthAnchor.constraint(equalToConstant: 36).isActive = true; swatch.heightAnchor.constraint(equalToConstant: 24).isActive = true
        swatch.setAccessibilityLabel("Current text color")
        colorButton.target = self; colorButton.action = #selector(openColor(_:)); colorButton.bezelStyle = .rounded
        let colors = NSStackView(views: [swatch, colorButton]); colors.spacing = 14
        status.textColor = .secondaryLabelColor
        applyButton.target = self; applyButton.action = #selector(changeFont(_:))
        applyButton.bezelStyle = .rounded; applyButton.keyEquivalent = "\r"
        applyButton.font = NSFont(name: "Helvetica", size: 12)
        applyButton.widthAnchor.constraint(equalToConstant: 84).isActive = true
        let actions = NSStackView(views: [NSView(), applyButton]); actions.spacing = 14
        let stack = NSStackView(views: [familyRow, faceRow, sizeRow, styles, colors, status, actions]); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 18
        actions.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: panel.contentView!.leadingAnchor, constant: 24), stack.trailingAnchor.constraint(equalTo: panel.contentView!.trailingAnchor, constant: -24), stack.topAnchor.constraint(equalTo: panel.contentView!.topAnchor, constant: 24)])
        for row in [familyRow, faceRow, sizeRow, styles, colors] { for control in row.views.compactMap({ $0 as? NSControl }) { control.font = NSFont(name: "Helvetica", size: 12) } }
        status.font = NSFont(name: "Helvetica", size: 12)
        panel.center()
    }
    required init?(coder: NSCoder) { fatalError() }
    func open() { refresh(); window?.appearance = editor?.window?.appearance; showWindow(nil); window?.makeKeyAndOrderFront(nil) }
    func refresh() {
        guard let editor, editor.document is QLMDocument else { return }
        let range = editor.text.selectedRange()
        let attributes = range.length > 0 && range.location < editor.text.textStorage!.length ? editor.text.textStorage!.attributes(at: range.location, effectiveRange: nil) : editor.text.typingAttributes
        let font = attributes[.font] as? NSFont ?? editor.baseFont
        family.stringValue = font.familyName ?? font.fontName; size.doubleValue = Double(font.pointSize)
        populateFaces(family: family.stringValue, selected: font.fontName)
        let traits = NSFontManager.shared.traits(of: font)
        bold.state = traits.contains(.boldFontMask) ? .on : .off
        italic.state = traits.contains(.italicFontMask) ? .on : .off
        underline.state = (attributes[.underlineStyle] as? Int ?? 0) != 0 ? .on : .off
        selectedColor = attributes[.foregroundColor] as? NSColor ?? .black
        if selectedColor == .textColor { selectedColor = .black }
        let image = NSImage(size: NSSize(width: 32, height: 20))
        image.lockFocus()
        selectedColor.setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: 32, height: 20), xRadius: 3, yRadius: 3).fill()
        image.unlockFocus()
        swatch.image = image
        swatch.imagePosition = .imageOnly
        status.stringValue = editor.doc.isRich ? "Applies to the selection or the text you type next." : "Applies to the selection. Save as HTML or RTF to keep formatting."
    }
    func populateFaces(family: String, selected: String?) {
        faceFamily = family
        face.removeAllItems()
        let members = NSFontManager.shared.availableMembers(ofFontFamily: family) ?? []
        for member in members {
            guard member.count >= 2, let name = member[0] as? String, let style = member[1] as? String else { continue }
            face.addItem(withTitle: style)
            face.lastItem?.representedObject = name
        }
        if let selected, let item = face.itemArray.first(where: { $0.representedObject as? String == selected }) {
            face.select(item)
        } else if let regular = face.itemArray.first(where: { ["regular", "normal", "roman", "book"].contains($0.title.lowercased()) }) {
            face.select(regular)
        }
    }
    @objc func changeFont(_ sender: Any?) {
        guard let editor, let pointSize = Double(size.stringValue), pointSize >= 1, pointSize <= 1000 else { status.stringValue = "Enter a font size between 1 and 1000 points."; return }
        let changedFamily = faceFamily != family.stringValue
        if changedFamily { populateFaces(family: family.stringValue, selected: nil) }
        guard let name = face.selectedItem?.representedObject as? String,
              var font = NSFont(name: name, size: CGFloat(pointSize)) else { status.stringValue = "Choose an installed font family and style."; return }
        if let button = sender as? NSButton, button === bold || button === italic {
            let trait: NSFontTraitMask = button === bold ? .boldFontMask : .italicFontMask
            font = button.state == .on ? NSFontManager.shared.convert(font, toHaveTrait: trait) : NSFontManager.shared.convert(font, toNotHaveTrait: trait)
        }
        editor.applyFontAttributes([.font: font]); refresh()
    }
    @objc func changeUnderline(_ sender: Any?) { editor?.applyFontAttributes([.underlineStyle: underline.state == .on ? NSUnderlineStyle.single.rawValue : 0]); refresh() }
    @objc func openColor(_ sender: Any?) {
        let panel = NSColorPanel.shared
        panel.color = selectedColor; panel.showsAlpha = false; panel.isContinuous = true
        panel.setTarget(self); panel.setAction(#selector(changeColor(_:)))
        panel.level = .floating; panel.makeKeyAndOrderFront(nil)
    }
    @objc func changeColor(_ sender: NSColorPanel) { selectedColor = sender.color; editor?.applyFontAttributes([.foregroundColor: selectedColor]); refresh() }
}

extension EditorController {
    @objc func showFontPicker(_ sender: Any?) {
        guard !scroll.isHidden, !htmlSourceView else { window?.presentError(aiError("Use the HTML source to change the styling of this HTML page.")); return }
        NSFontPanel.shared.orderOut(nil)
        if fontPicker == nil { fontPicker = FontPickerController(editor: self) }
        fontPicker?.open()
    }
    func applyFontAttributes(_ attributes: [NSAttributedString.Key: Any]) {
        guard document is QLMDocument else { return }
        let range = text.selectedRange()
        guard range.length > 0 else { var typing = text.typingAttributes; typing.merge(attributes) { _, new in new }; text.typingAttributes = typing; return }
        guard NSMaxRange(range) <= (text.textStorage?.length ?? 0), text.shouldChangeText(in: range, replacementString: nil) else { return }
        let previous = text.textStorage!.attributedSubstring(from: range)
        text.undoManager?.registerUndo(withTarget: self) { target in target.restoreFontAttributes(previous, range: range) }
        text.textStorage?.addAttributes(attributes, range: range)
        text.didChangeText(); text.undoManager?.setActionName("Change Text Formatting")
        applyTextAppearance(); updateContainer()
    }
    func restoreFontAttributes(_ previous: NSAttributedString, range: NSRange) {
        guard NSMaxRange(range) <= (text.textStorage?.length ?? 0) else { return }
        let current = text.textStorage!.attributedSubstring(from: range)
        text.undoManager?.registerUndo(withTarget: self) { $0.restoreFontAttributes(current, range: range) }
        text.textStorage?.replaceCharacters(in: range, with: previous)
        text.didChangeText(); applyTextAppearance(); updateContainer(); fontPicker?.refresh()
    }
}
