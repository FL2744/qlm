import AppKit
import WebKit

enum HTMLEmbeds {
    static func contains(_ value: NSAttributedString) -> Bool {
        var found = false
        value.enumerateAttribute(.attachment, in: NSRange(location: 0, length: value.length)) { attachment, _, stop in
            if attachment is HTMLEmbedAttachment { found = true; stop.pointee = true }
        }
        return found
    }
}

final class HTMLEmbedAttachment: NSTextAttachment {
    let html: String
    init(html: String) {
        self.html = html
        super.init(data: nil, ofType: nil)
        bounds = NSRect(x: 0, y: 0, width: 480, height: 270)
        let placeholder = NSImage(size: bounds.size, flipped: false) { rect in
            NSColor.black.setFill(); rect.fill()
            ("HTML embed" as NSString).draw(at: NSPoint(x: 18, y: 18), withAttributes: [.font: NSFont(name: "Helvetica", size: 12)!, .foregroundColor: NSColor.white])
            return true
        }
        image = placeholder
    }
    required init?(coder: NSCoder) { return nil }
}

final class HTMLWebView: WKWebView, WKNavigationDelegate, WKUIDelegate {
    var editingGeneration = ""
    var editingReady = false
    var documentWasEdited = false
    var onDocumentEdit: ((String?) -> Void)?
    static let origin = URL(string: "https://" + (Bundle.main.bundleIdentifier ?? "com.willtaggart.qlm").lowercased() + "/")!
    init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        super.init(frame: .zero, configuration: configuration)
        navigationDelegate = self; uiDelegate = self
        setAccessibilityLabel("Rendered HTML")
    }
    required init?(coder: NSCoder) { fatalError() }
    func render(_ html: String) { editingReady = false; documentWasEdited = false; if onDocumentEdit != nil { prepareDocumentEditingScript() }; loadHTMLString(html, baseURL: Self.origin) }
    static func wrapper(_ html: String, dark: Bool) -> String {
        "<!DOCTYPE html><html><head><meta charset=\"utf-8\"><meta name=\"referrer\" content=\"strict-origin-when-cross-origin\"><style>html,body{margin:0;background:\(dark ? "black" : "white");color:\(dark ? "white" : "black");font:12pt Helvetica}iframe,video,object,embed{width:100%;height:100vh;display:block;border:0;box-sizing:border-box}img{max-width:100%}</style></head><body>" + html + "</body></html>"
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let url = navigationAction.request.url
        let scheme = url?.scheme?.lowercased() ?? ""
        let allowed = ["https", "http", "about", "data", "blob"].contains(scheme)
        // Keep the document in place. Embedded frames may navigate within their player.
        if navigationAction.targetFrame?.isMainFrame == true && navigationAction.navigationType == .linkActivated { decisionHandler(.cancel); return }
        decisionHandler(allowed ? .allow : .cancel)
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? { nil }
}

extension EditorController {
    @objc func insertHTMLEmbed(_ sender: Any?) {
        let alert = NSAlert(); alert.messageText = "Insert HTML embed"
        alert.informativeText = "Paste YouTube’s Share → Embed code, or another HTML embed. Online embeds connect to their host when displayed."
        alert.addButton(withTitle: "Insert"); alert.addButton(withTitle: "Cancel")
        let area = NSScrollView(frame: NSRect(x: 0, y: 0, width: 510, height: 180))
        let input = NSTextView(frame: area.bounds)
        input.font = NSFont(name: "Helvetica", size: 12); input.isRichText = false
        input.isAutomaticQuoteSubstitutionEnabled = false; input.isAutomaticDashSubstitutionEnabled = false
        input.isContinuousSpellCheckingEnabled = false; input.isGrammarCheckingEnabled = false
        area.documentView = input; area.hasVerticalScroller = true; alert.accessoryView = area
        alert.window.initialFirstResponder = input
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let html = input.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !html.isEmpty else { return }
        insertEmbedHTML(html)
    }
    func insertSourceHTML(_ html: String) {
        do { try synchronizeHTMLPreview() } catch { window?.presentError(error); return }
        let source = text.string as NSString
        let closingBody = source.range(of: "</body>", options: .caseInsensitive)
        let range = htmlSourceView ? text.selectedRange() : NSRange(location: closingBody.location == NSNotFound ? source.length : closingBody.location, length: 0)
        let display = htmlSourceView ? (htmlSourceProjection?.compactAdditional(html) ?? html) : html
        text.insertText(display, replacementRange: range)
        updateHTMLPresentation()
    }
    func insertEmbedHTML(_ html: String) {
        if htmlSourceView || (doc.format == .html && !doc.htmlRich) {
            insertSourceHTML(html)
            return
        }
        doc.becomeImageHTML()
        let block = NSMutableAttributedString(string: "\n")
        block.append(NSAttributedString(attachment: HTMLEmbedAttachment(html: html)))
        block.append(NSAttributedString(string: "\n"))
        text.insertText(block, replacementRange: text.selectedRange())
        text.undoManager?.setActionName("Insert HTML Embed")
        updateContainer()
    }
    func pasteEmbed(from pasteboard: NSPasteboard) -> Bool {
        guard !htmlSourceView, let code = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              code.range(of: "^<(iframe|video|audio|object|embed)\\b", options: [.regularExpression, .caseInsensitive]) != nil else { return false }
        insertEmbedHTML(code); return true
    }
    func updateEmbedViews() {
        guard let document = document as? QLMDocument, !htmlSourceView, document.htmlRich, let storage = text.textStorage, let layout = text.layoutManager, let container = text.textContainer else {
            embedViews.values.forEach { $0.removeFromSuperview(); $0.stopLoading() }; embedViews.removeAll(); return
        }
        var live = Set<ObjectIdentifier>()
        var placements: [(HTMLEmbedAttachment, NSRange)] = []
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { attachment, range, _ in
            if let embed = attachment as? HTMLEmbedAttachment { placements.append((embed, range)) }
        }
        let width = max(100, min(560, container.containerSize.width - 2 * container.lineFragmentPadding))
        for (embed, range) in placements {
            let id = ObjectIdentifier(embed); live.insert(id)
            let size = NSSize(width: width, height: width * 9 / 16)
            if embed.bounds.size != size {
                embed.bounds.size = size
                layout.invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
            }
        }
        layout.ensureLayout(for: container)
        for (embed, range) in placements {
            let id = ObjectIdentifier(embed)
            let web: HTMLWebView
            if let existing = embedViews[id] { web = existing }
            else {
                web = HTMLWebView(); embedViews[id] = web; text.addSubview(web)
                web.render(HTMLWebView.wrapper(embed.html, dark: !light))
            }
            let glyphs = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let rect = layout.boundingRect(forGlyphRange: glyphs, in: container)
            web.frame = NSRect(x: rect.minX + text.textContainerOrigin.x, y: rect.minY + text.textContainerOrigin.y, width: embed.bounds.width, height: embed.bounds.height)
        }
        for id in Array(embedViews.keys) where !live.contains(id) { embedViews.removeValue(forKey: id)?.removeFromSuperview() }
    }
    static let showImageBytesKey = "showHTMLImageBytes"
    static var showImageBytes: Bool { UserDefaults.standard.bool(forKey: showImageBytesKey) }
    @objc func toggleImageBytes(_ sender: Any?) {
        UserDefaults.standard.set(!Self.showImageBytes, forKey: Self.showImageBytesKey)
        NotificationCenter.default.post(name: .qlmImageBytes, object: nil)
    }
    @objc func refreshImageBytes() {
        guard htmlSourceView else { return }
        do {
            let unchanged = text.string == richHTMLSource
            let source = try expandedHTMLSource()
            let projection = sourceProjection(source)
            let display = projection?.display ?? source
            loading = true
            text.string = display
            htmlSourceProjection = projection
            if unchanged { richHTMLSource = display }
            text.sourceUndoManager?.removeAllActions()
            loading = false
            applyPlainStyle(); applyTextAppearance(); updateContainer()
        } catch { window?.presentError(error) }
    }
    func expandedHTMLSource() throws -> String {
        try htmlSourceProjection?.expanded(text.string) ?? text.string
    }
    @objc func toggleHTMLSource(_ sender: Any?) {
        guard doc.format == .html else { return }
        do {
            if !htmlSourceView {
                try synchronizeHTMLPreview()
                let source: String
                if doc.htmlRich {
                    richHTMLSnapshot = documentContent()
                    let bytes = try HTMLImages.encode(richHTMLSnapshot!, title: (doc.displayName as NSString).deletingPathExtension, dark: doc.savesDarkHTML)
                    source = String(data: bytes, encoding: .utf8)!
                } else { source = text.string }
                let projection = sourceProjection(source)
                let display = projection?.display ?? source
                richUndoManager = text.undoManager
                text.sourceUndoManager = UndoManager()
                htmlSourceProjection = projection
                richHTMLSource = display
                loading = true; text.string = display; doc.htmlRich = false; loading = false
                htmlSourceView = true; loadFormatState()
                text.isAutomaticQuoteSubstitutionEnabled = false
            } else {
                let expanded = try expandedHTMLSource()
                if let snapshot = richHTMLSnapshot, text.string == richHTMLSource {
                    loading = true; text.textStorage?.setAttributedString(snapshot); doc.htmlRich = true
                    text.sourceUndoManager = richUndoManager; loading = false
                } else {
                    doc.htmlRich = false
                    loading = true
                    text.string = richHTMLSnapshot != nil ? expanded.replacingOccurrences(of: HTMLImages.marker, with: "") : expanded
                    doc.content = NSAttributedString(string: text.string)
                    loading = false
                    text.undoManager?.removeAllActions()
                }
                htmlSourceView = false; richHTMLSnapshot = nil; richHTMLSource = nil; htmlSourceProjection = nil
                text.isAutomaticQuoteSubstitutionEnabled = true
                loadFormatState()
            }
            updateContainer(); updateHTMLPresentation()
        } catch { window?.presentError(error) }
    }
    func updateHTMLPresentation() {
        guard document is QLMDocument else { return }
        let showPage = doc.format == .html && !doc.htmlRich && !htmlSourceView
        scroll.isHidden = showPage
        if showPage {
            if htmlPreview == nil, let root = window?.contentView {
                let web = HTMLWebView(); htmlPreview = web
                web.enableDocumentEditing { [weak self, weak web] source in
                    if source == nil { web?.documentWasEdited = true }
                    self?.receiveHTMLPreviewEdit(source)
                }
                web.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(web)
                NSLayoutConstraint.activate([web.topAnchor.constraint(equalTo: header.bottomAnchor), web.leadingAnchor.constraint(equalTo: root.leadingAnchor), web.trailingAnchor.constraint(equalTo: root.trailingAnchor), web.bottomAnchor.constraint(equalTo: root.bottomAnchor)])
            }
            htmlPreview?.isHidden = false
            if previewSource != text.string { previewSource = text.string; htmlPreview?.render(text.string) }
            htmlPreview?.pageZoom = zoom
        } else { htmlPreview?.isHidden = true }
        updateEmbedViews()
        if showPage { window?.makeFirstResponder(htmlPreview) }
        else { text.isEditable = true; text.isSelectable = true; window?.makeFirstResponder(text) }
    }
}
