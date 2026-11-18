import AppKit
import WebKit

final class WritingScrollView: NSScrollView {
    var onZoom: ((CGFloat) -> Void)?
    static let mouseWheelZoomKey = "mouseWheelZoomEnabled"
    static var mouseWheelZoomEnabled: Bool { UserDefaults.standard.object(forKey: mouseWheelZoomKey) as? Bool ?? true }
    static func zoomDelta(delta: CGFloat, precise: Bool, modifiers: NSEvent.ModifierFlags, enabled: Bool = true) -> CGFloat? {
        guard enabled, delta != 0, !modifiers.contains(.option), (!precise || modifiers.contains(.command)) else { return nil }
        return precise ? max(-0.1, min(0.1, delta * 0.005)) : (delta > 0 ? 0.1 : -0.1)
    }
    override func scrollWheel(with event: NSEvent) {
        let delta = event.isDirectionInvertedFromDevice ? -event.scrollingDeltaY : event.scrollingDeltaY
        if let amount = Self.zoomDelta(delta: delta, precise: event.hasPreciseScrollingDeltas, modifiers: event.modifierFlags, enabled: Self.mouseWheelZoomEnabled), let onZoom {
            onZoom(amount)
        } else { super.scrollWheel(with: event) }
    }
    override func magnify(with event: NSEvent) { onZoom?(event.magnification) }
}

final class WritingView: NSTextView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        for web in subviews.compactMap({ $0 as? HTMLWebView }) where !web.isHidden && web.frame.contains(local) {
            return web.hitTest(local) ?? web
        }
        return super.hitTest(point)
    }
    override func accessibilityChildren() -> [Any]? {
        (super.accessibilityChildren() ?? []) + subviews.compactMap { $0 as? HTMLWebView }
    }
    var sourceUndoManager: UndoManager?
    override var undoManager: UndoManager? { sourceUndoManager ?? super.undoManager }
    var pasteHTML: ((NSPasteboard) -> Bool)?
    var pasteImages: ((NSPasteboard) -> Bool)?
    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] { [.png, .tiff, .fileURL] + super.readablePasteboardTypes }
    static func clipboardTextOverImage(_ pasteboard: NSPasteboard) -> String? {
        guard HTMLImages.hasImages(pasteboard), HTMLImages.fileImages(pasteboard).isEmpty else { return nil }
        var value = pasteboard.string(forType: .string)
        if value == nil {
            for (type, format) in [(NSPasteboard.PasteboardType.rtf, NSAttributedString.DocumentType.rtf), (.html, .html)] {
                if let bytes = pasteboard.data(forType: type), let imported = try? NSAttributedString(data: bytes, options: [.documentType: format], documentAttributes: nil) {
                    value = imported.string; break
                }
            }
        }
        guard let source = value else { return nil }
        let words = source.replacingOccurrences(of: "\u{FFFC}", with: "")
        let trimmed = words.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // Image copies can carry their source URL; image file copies remain images.
        if !trimmed.contains(where: { $0.isWhitespace }), let url = URL(string: trimmed), ["http", "https", "file", "data"].contains(url.scheme?.lowercased() ?? "") { return nil }
        return words
    }
    override func paste(_ sender: Any?) {
        if pasteHTML?(NSPasteboard.general) == true { return }
        if let words = Self.clipboardTextOverImage(NSPasteboard.general) {
            insertText(words, replacementRange: selectedRange()); return
        }
        if pasteImages?(NSPasteboard.general) == true { return }
        super.paste(sender)
    }
    override func readSelection(from pasteboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        if pasteHTML?(pasteboard) == true { return true }
        if let words = Self.clipboardTextOverImage(pasteboard) {
            insertText(words, replacementRange: selectedRange()); return true
        }
        if pasteImages?(pasteboard) == true { return true }
        return super.readSelection(from: pasteboard, type: type)
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        HTMLImages.hasImages(sender.draggingPasteboard) ? .copy : super.draggingEntered(sender)
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        HTMLImages.hasImages(sender.draggingPasteboard) ? .copy : super.draggingUpdated(sender)
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if HTMLImages.hasImages(sender.draggingPasteboard) {
            let index = characterIndexForInsertion(at: convert(sender.draggingLocation, from: nil))
            setSelectedRange(NSRange(location: min(index, (string as NSString).length), length: 0))
            return pasteImages?(sender.draggingPasteboard) ?? false
        }
        return super.performDragOperation(sender)
    }
    var zoomIn: (() -> Void)?
    var zoomOut: (() -> Void)?
    override func complete(_ sender: Any?) {} // Deliberately no completion UI.
    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command) {
            if ["+", "="].contains(event.charactersIgnoringModifiers ?? "") { zoomIn?(); return }
            if event.charactersIgnoringModifiers == "-" { zoomOut?(); return }
        }
        super.keyDown(with: event)
    }
}

final class EditorController: NSWindowController, NSTextViewDelegate, NSMenuItemValidation {
    let text = WritingView(frame: .zero)
    let scroll = WritingScrollView()
    let header = NSView()
    let wordmark = NSTextField(labelWithString: "qlm")
    var operationStatus = "" { didSet { text.setAccessibilityHelp(operationStatus.isEmpty ? nil : operationStatus) } }
    let appearancePicker = NSSegmentedControl(labels: ["Light", "Dark"], trackingMode: .selectOne, target: nil, action: nil)
    var aiTask: Task<Void, Never>?
    var aiBusy = false
    var exportingLaTeX = false
    var wrap = false
    var zoom: CGFloat = 1
    var htmlSourceView = false
    var richHTMLSnapshot: NSAttributedString?
    var richHTMLSource: String?
    var htmlSourceProjection: HTMLSourceProjection?
    var richUndoManager: UndoManager?
    var htmlPreview: HTMLWebView?
    var previewSource: String?
    var embedViews: [ObjectIdentifier: HTMLWebView] = [:]
    var baseRichContent: NSAttributedString?
    var loading = false
    var updatingContainer = false
    var light: Bool { UserDefaults.standard.string(forKey: "appearance") != "dark" }
    var doc: QLMDocument { document as! QLMDocument }
    var writingFont = NSFont(name: "Helvetica", size: 12)!
    var writingColor = NSColor.black
    var writingUnderline = 0
    var fontPicker: FontPickerController?
    var baseFont: NSFont { writingFont }
    var pageWidth: CGFloat { ("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789" as NSString).size(withAttributes: [.font: baseFont]).width / 62 * 120 }

    init(document: QLMDocument) {
        let font = NSFont(name: "Helvetica", size: 12)!
        let width = ("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789" as NSString).size(withAttributes: [.font: font]).width / 62 * 120 + 96
        let lineHeight = NSLayoutManager().defaultLineHeight(for: font)
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 1000)
        let size = NSSize(width: min(width, visible.width - 40), height: min(lineHeight * 40 + 140, visible.height - 36))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.minSize = NSSize(width: 580, height: 380)
        window.title = "qlm"
        window.titleVisibility = .hidden
        window.tabbingMode = .disallowed
        window.isRestorable = false
        window.center()
        super.init(window: window)
        build()
        NotificationCenter.default.addObserver(self, selector: #selector(editorWindowClosed(_:)), name: NSWindow.willCloseNotification, object: window)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshImageBytes), name: .qlmImageBytes, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appearanceChanged), name: .qlmAppearance, object: nil)
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { NotificationCenter.default.removeObserver(self) }

    func build() {
        guard let root = window?.contentView else { return }
        root.wantsLayer = true
        for view in [header, scroll] { view.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(view) }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: root.topAnchor), header.leadingAnchor.constraint(equalTo: root.leadingAnchor), header.trailingAnchor.constraint(equalTo: root.trailingAnchor), header.heightAnchor.constraint(equalToConstant: 48),
            scroll.topAnchor.constraint(equalTo: header.bottomAnchor), scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor), scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])
        wordmark.font = .systemFont(ofSize: 12, weight: .black)
        wordmark.setAccessibilityLabel("qlm")
        appearancePicker.controlSize = .small
        appearancePicker.target = self; appearancePicker.action = #selector(selectAppearance(_:))
        appearancePicker.setAccessibilityLabel("Appearance")
        for view in [wordmark, appearancePicker] { header.addSubview(view); view.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            wordmark.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 26), wordmark.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            appearancePicker.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -24), appearancePicker.centerYAnchor.constraint(equalTo: header.centerYAnchor), appearancePicker.widthAnchor.constraint(equalToConstant: 116)
        ])
        let rule = NSBox(); rule.boxType = .separator; rule.translatesAutoresizingMaskIntoConstraints = false; header.addSubview(rule)
        NSLayoutConstraint.activate([rule.leadingAnchor.constraint(equalTo: header.leadingAnchor), rule.trailingAnchor.constraint(equalTo: header.trailingAnchor), rule.bottomAnchor.constraint(equalTo: header.bottomAnchor)])
        scroll.onZoom = { [weak self] in self?.changeZoom($0) }
        scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true; scroll.borderType = .noBorder
        scroll.hasVerticalRuler = false; scroll.hasHorizontalRuler = false; scroll.rulersVisible = false
        text.minSize = NSSize(width: 0, height: 0)
        text.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        text.isVerticallyResizable = true; text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]
        text.textContainerInset = NSSize(width: 42, height: 28)
        text.textContainer?.lineFragmentPadding = 6
        text.allowsUndo = true; text.usesFindBar = true
        text.usesRuler = false; text.isRulerVisible = false
        text.isContinuousSpellCheckingEnabled = false; text.isGrammarCheckingEnabled = false
        text.isAutomaticSpellingCorrectionEnabled = false; text.isAutomaticTextCompletionEnabled = false
        text.isAutomaticDashSubstitutionEnabled = false; text.isAutomaticLinkDetectionEnabled = false
        text.isAutomaticTextReplacementEnabled = false; text.isAutomaticDataDetectionEnabled = false
        text.isAutomaticQuoteSubstitutionEnabled = true
        text.smartInsertDeleteEnabled = false
        text.usesAdaptiveColorMappingForDarkAppearance = false
        text.layoutManager?.allowsNonContiguousLayout = true
        text.delegate = self
        text.setAccessibilityLabel("Writing area")
        text.zoomIn = { [weak self] in self?.changeZoom(0.1) }
        text.zoomOut = { [weak self] in self?.changeZoom(-0.1) }
        text.pasteHTML = { [weak self] in self?.pasteEmbed(from: $0) ?? false }
        text.pasteImages = { [weak self] in self?.insertImages(from: $0) ?? false }
        text.registerForDraggedTypes([.png, .tiff, .fileURL])
        scroll.documentView = text
        NotificationCenter.default.addObserver(self, selector: #selector(resized), name: NSView.frameDidChangeNotification, object: scroll.contentView)
        scroll.contentView.postsFrameChangedNotifications = true
        applyAppearance()
    }
    func documentContent() -> NSAttributedString {
        // Magnification affects display only, so saved fonts remain at their original size.
        NSAttributedString(attributedString: text.textStorage ?? NSTextStorage())
    }
    func loadDocument() {
        htmlSourceView = false; richHTMLSnapshot = nil; richHTMLSource = nil; htmlSourceProjection = nil
        previewSource = nil; richUndoManager = nil; text.sourceUndoManager = nil
        loading = true
        text.textStorage?.setAttributedString(doc.content)
        if !doc.isRich { text.textStorage?.addAttribute(.font, value: baseFont, range: NSRange(location: 0, length: text.textStorage?.length ?? 0)) }
        else {
            text.textStorage?.enumerateAttribute(.font, in: NSRange(location: 0, length: text.textStorage?.length ?? 0)) { font, range, _ in
                if font == nil { text.textStorage?.addAttribute(.font, value: baseFont, range: range) }
            }
        }
        text.typingAttributes[.font] = baseFont
        loadFormatState()
        loading = false
        updateContainer()
        text.undoManager?.removeAllActions()
        updateHTMLPresentation()
        updateStatus()
    }
    func loadFormatState() {
        text.isRichText = doc.isRich
        text.importsGraphics = doc.isRich
        if !doc.isRich { applyPlainStyle() }
        text.usesRuler = false; text.isRulerVisible = false
        scroll.rulersVisible = false
        applyTextAppearance()
        updateStatus()
        updateHTMLPresentation()
    }
    func applyPlainStyle() {
        let selection = text.selectedRanges
        let paragraph = NSMutableParagraphStyle()
        paragraph.baseWritingDirection = .natural
        paragraph.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [.font: baseFont, .foregroundColor: writingColor, .underlineStyle: writingUnderline, .paragraphStyle: paragraph]
        text.textStorage?.setAttributes(attributes, range: NSRange(location: 0, length: (text.string as NSString).length))
        text.typingAttributes = attributes
        text.selectedRanges = selection
    }
    func stripFormatting() {
        let old = documentContent()
        let oldType = doc.fileType
        let oldURL = doc.fileURL
        let oldName = doc.displayName
        let oldHTMLRich = doc.htmlRich
        text.undoManager?.registerUndo(withTarget: self) { target in
            target.text.textStorage?.setAttributedString(old)
            target.doc.htmlRich = oldHTMLRich
            target.doc.fileType = oldType
            target.doc.fileURL = oldURL
            target.doc.displayName = oldName
            target.loadFormatState()
            target.doc.updateChangeCount(.changeDone)
        }
        var attachments: [NSRange] = []
        text.textStorage?.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.textStorage?.length ?? 0)) { value, range, _ in if value != nil { attachments.append(range) } }
        for range in attachments.reversed() { text.textStorage?.replaceCharacters(in: range, with: "") }
        text.isRichText = false
        applyPlainStyle()
    }
    func textDidChange(_ notification: Notification) {
        guard !loading else { return }
        if !htmlSourceView && HTMLImages.containsImages(documentContent()) { doc.becomeImageHTML() }
        updateContainer()
        applyTextAppearance()
        doc.content = documentContent()
        doc.updateChangeCount(.changeDone)
        updateStatus()
    }
    func textViewDidChangeSelection(_ notification: Notification) { updateStatus(); if fontPicker?.window?.isVisible == true { fontPicker?.refresh() } }
    func updateStatus() {
        if !aiBusy && !exportingLaTeX { operationStatus = "" }
    }
    override func synchronizeWindowTitleWithDocumentName() {
        window?.title = "qlm"
        window?.titleVisibility = .hidden
        window?.representedURL = nil
    }
    @objc func resized() { updateContainer() }
    func updateContainer() {
        guard !updatingContainer, let container = text.textContainer, let layout = text.layoutManager else { return }
        updatingContainer = true
        defer { updatingContainer = false }
        // Clip bounds are already expressed in magnified document coordinates.
        // Keep the existing 48pt side margins and 28pt top margin fixed on screen.
        let viewport = scroll.contentView.bounds.size
        let magnification = max(0.5, scroll.magnification)
        let inset = NSSize(width: 42 / magnification, height: 28 / magnification)
        text.textContainerInset = inset
        container.lineFragmentPadding = 6 / magnification
        let available = max(1, viewport.width - 2 * inset.width)
        let width = wrap ? min(pageWidth, available) : available
        text.isHorizontallyResizable = false
        container.widthTracksTextView = false
        container.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        text.setFrameSize(NSSize(width: viewport.width, height: max(text.frame.height, viewport.height)))
        if (text.textStorage?.length ?? 0) > 250_000 {
            // Let TextKit discover document height incrementally instead of typesetting
            // megabytes (including offscreen JSON) on every open, resize, and keystroke.
            let visible = NSRect(origin: scroll.contentView.bounds.origin,
                                 size: NSSize(width: width, height: max(viewport.height * 2, 1000)))
            layout.ensureLayout(forBoundingRect: visible, in: container)
        } else {
            layout.ensureLayout(for: container)
        }
        updateEmbedViews()
        let height = layout.usedRect(for: container).height + 2 * inset.height
        text.setFrameSize(NSSize(width: viewport.width, height: max(height, viewport.height)))
    }
    func changeZoom(_ delta: CGFloat) {
        zoom = min(3, max(0.5, zoom + delta))
        scroll.allowsMagnification = true; scroll.minMagnification = 0.5; scroll.maxMagnification = 3
        scroll.magnification = zoom
        htmlPreview?.pageZoom = zoom
        updateContainer(); updateStatus()
    }
    @objc func zoomIn(_ sender: Any?) { changeZoom(0.1) }
    @objc func zoomOut(_ sender: Any?) { changeZoom(-0.1) }
    @objc func actualSize(_ sender: Any?) { zoom = 1; changeZoom(0) }
    @objc func toggleDarkHTMLSave(_ sender: Any?) {
        UserDefaults.standard.set(!HTMLPage.darkSavesEnabled(), forKey: HTMLPage.darkSaveKey)
    }
    @objc func toggleMouseWheelZoom(_ sender: Any?) {
        UserDefaults.standard.set(!WritingScrollView.mouseWheelZoomEnabled, forKey: WritingScrollView.mouseWheelZoomKey)
    }
    @objc func toggleWrap(_ sender: Any?) { wrap.toggle(); updateContainer(); updateStatus() }
    @objc func selectAppearance(_ sender: NSSegmentedControl) {
        UserDefaults.standard.set(sender.selectedSegment == 1 ? "dark" : "light", forKey: "appearance")
        NotificationCenter.default.post(name: .qlmAppearance, object: nil)
    }
    @objc func appearanceChanged() { applyAppearance() }
    func applyAppearance(lightMode: Bool? = nil) {
        let isLight = lightMode ?? light
        let background: NSColor = isLight ? .white : .black
        let foreground: NSColor = isLight ? .black : .white
        window?.appearance = NSAppearance(named: isLight ? .aqua : .darkAqua)
        // The native title bar stays black as a visible window-dragging strip.
        window?.backgroundColor = .black
        window?.contentView?.layer?.backgroundColor = background.cgColor
        window?.titlebarAppearsTransparent = true
        for view in [header] {
            view.wantsLayer = true
            view.layer?.backgroundColor = background.cgColor
        }
        wordmark.textColor = foreground
        appearancePicker.selectedSegment = isLight ? 0 : 1
        text.backgroundColor = background
        scroll.backgroundColor = background
        text.insertionPointColor = foreground
        applyTextAppearance()
        text.needsDisplay = true
    }
    func applyTextAppearance() {
        guard let manager = text.layoutManager else { return }
        let range = NSRange(location: 0, length: (text.string as NSString).length)
        manager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: range)
        if window?.appearance?.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua {
            // Display-only white: switching appearance must not recolor saved RTF/DOCX text.
            text.textStorage?.enumerateAttribute(.foregroundColor, in: range) { value, span, _ in
                let color = (value as? NSColor)?.usingColorSpace(.sRGB)
                if color == nil || (color!.redComponent < 0.01 && color!.greenComponent < 0.01 && color!.blueComponent < 0.01) {
                    manager.addTemporaryAttribute(.foregroundColor, value: NSColor.white, forCharacterRange: span)
                }
            }
        }
    }
    @objc func directionRTL(_ sender: Any?) { text.makeBaseWritingDirectionRightToLeft(sender) }
    @objc func directionLTR(_ sender: Any?) { text.makeBaseWritingDirectionLeftToRight(sender) }
    @objc func directionNatural(_ sender: Any?) { text.makeBaseWritingDirectionNatural(sender) }
    @objc func pastePlain(_ sender: Any?) { text.pasteAsPlainText(sender) }
    @objc func exportDocument(_ sender: NSMenuItem) {
        let ext = sender.representedObject as? String ?? "pdf"
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTTypeForExport(ext)]
        panel.nameFieldStringValue = ((doc.displayName as NSString).deletingPathExtension) + "." + ext
        panel.message = ext == "pdf" ? (doc.format == .tex ? "Typeset this LaTeX source with Tectonic. Missing TeX packages may be downloaded." : "Export the complete document as paginated PDF.") : "Capture the visible qlm window, including the header. Offscreen text is excluded."
        guard let window, panel.runModal() == .OK, let url = panel.url else { return }
        if ext == "pdf" && doc.format == .tex {
            guard !exportingLaTeX else { return }
            exportingLaTeX = true
            let source = text.string
            let directory = doc.fileURL?.deletingLastPathComponent()
            operationStatus = "Typesetting LaTeX…"
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                let result = Result { try LaTeXExporter.compile(source: source, directory: directory, to: url) }
                DispatchQueue.main.async {
                    self.exportingLaTeX = false
                    self.updateStatus()
                    if case .failure(let error) = result { LaTeXErrorPresentation.present(error as NSError) }
                }
            }
            return
        }
        do {
            if ext == "pdf" { try exportPDF(to: url) }
            else {
                try windowImage(ext).write(to: url, options: .atomic)
            }
        } catch { window.presentError(error) }
    }
    func windowImage(_ ext: String) throws -> Data {
        guard let view = window?.contentView?.superview,
              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw CocoaError(.fileWriteUnknown) }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let type: NSBitmapImageRep.FileType = ext == "png" ? .png : ext == "jpg" ? .jpeg : .tiff
        guard let data = bitmap.representation(using: type, properties: [.compressionFactor: 0.95]) else { throw CocoaError(.fileWriteUnknown) }
        return data
    }
    func exportPDF(to url: URL) throws {
        if doc.format == .tex {
            try LaTeXExporter.compile(source: text.string, directory: doc.fileURL?.deletingLastPathComponent(), to: url)
            return
        }
        let copy = NSTextView(frame: NSRect(x: 0, y: 0, width: 504, height: 720))
        let value = NSMutableAttributedString(attributedString: documentContent())
        value.addAttribute(.foregroundColor, value: NSColor.black, range: NSRange(location: 0, length: value.length))
        // Imported paragraphs may explicitly disable wrapping. Printing always wraps.
        value.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: value.length)) { style, range, _ in
            let paragraph = (style as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byWordWrapping
            value.addAttribute(.paragraphStyle, value: paragraph, range: range)
        }
        copy.textStorage?.setAttributedString(value)
        copy.textContainerInset = .zero
        copy.isHorizontallyResizable = false; copy.isVerticallyResizable = true
        copy.textContainer?.containerSize = NSSize(width: 504, height: CGFloat.greatestFiniteMagnitude)
        copy.textContainer?.widthTracksTextView = true
        copy.backgroundColor = .white; copy.textColor = .black
        copy.sizeToFit()
        let info = DocumentPrinting.letterInfo()
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
        let operation = NSPrintOperation(view: copy, printInfo: info)
        operation.showsPrintPanel = false; operation.showsProgressPanel = false
        guard operation.run() else { throw CocoaError(.fileWriteUnknown) }
    }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleImageBytes(_:)) { menuItem.state = Self.showImageBytes ? .on : .off; return true }
        if menuItem.action == #selector(toggleDarkHTMLSave(_:)) { menuItem.state = HTMLPage.darkSavesEnabled() ? .on : .off; return true }
        if menuItem.action == #selector(toggleMouseWheelZoom(_:)) { menuItem.state = WritingScrollView.mouseWheelZoomEnabled ? .on : .off; return true }
        if menuItem.action == #selector(toggleHTMLSource(_:)) { menuItem.state = htmlSourceView ? .on : .off; return doc.format == .html }

        if menuItem.action == #selector(cancelTextAction(_:)) { return aiTask != nil }
        if menuItem.action == #selector(rewriteSelection(_:)) || menuItem.action == #selector(translateSelection(_:)) { return !scroll.isHidden && !aiBusy && text.selectedRange().length > 0 }
        if (menuItem.action == #selector(exportDocument(_:)) || menuItem.action == #selector(printCurrentDocument(_:))), exportingLaTeX { return false }
        if menuItem.action == #selector(toggleWrap(_:)) { menuItem.state = wrap ? .on : .off }
        return true
    }
}

import UniformTypeIdentifiers
func UTTypeForExport(_ ext: String) -> UTType { ext == "pdf" ? .pdf : ext == "png" ? .png : ext == "jpg" ? .jpeg : .tiff }
extension Notification.Name { static let qlmImageBytes = Notification.Name("qlmImageBytes"); static let qlmAppearance = Notification.Name("qlmAppearance") }
