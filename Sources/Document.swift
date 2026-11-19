import AppKit

@objc(QLMDocument) final class QLMDocument: NSDocument {
    override var fileType: String? { didSet { editor?.updateDocumentType() } }
    var content = NSAttributedString(string: "")
    var codec = PlainCodec()
    var htmlRich = false
    private var htmlSaveURL: URL?
    private var htmlTitle: String { (htmlSaveURL ?? fileURL)?.deletingPathExtension().lastPathComponent ?? (displayName as NSString).deletingPathExtension }
    var savesDarkHTML: Bool { HTMLPage.darkSavesEnabled() && !(editor?.light ?? (UserDefaults.standard.string(forKey: "appearance") != "dark")) }
    var isRich: Bool { format.rich || (format == .html && htmlRich) }
    var format: Format { Format(type: fileType ?? Format.txt.type) }
    var editor: EditorController? { windowControllers.first as? EditorController }
    override class var autosavesInPlace: Bool { false }
    override class var writableTypes: [String] { Format.allCases.map(\.type) }

    override func makeWindowControllers() {
        let controller = EditorController(document: self)
        addWindowController(controller)
        controller.loadDocument()
    }
    static let maximumEditableBytes = 32 * 1024 * 1024
    static func validateEditableSize(_ count: Int) throws {
        guard count <= maximumEditableBytes else {
            throw NSError(domain: "qlm", code: 413, userInfo: [NSLocalizedDescriptionKey: "This file is too large to edit in qlm.", NSLocalizedRecoverySuggestionErrorKey: "qlm currently supports files up to 32 MB. Open a smaller extract or split this file into smaller files."])
        }
    }
    override func read(from url: URL, ofType typeName: String) throws {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        try Self.validateEditableSize(size)
        try super.read(from: url, ofType: typeName)
    }
    override func read(from data: Data, ofType typeName: String) throws {
        try Self.validateEditableSize(data.count)
        let kind = Format(type: typeName)
        htmlRich = kind == .html && String(data: data, encoding: .utf8)?.contains(HTMLImages.marker) == true
        if htmlRich { content = try HTMLImages.decode(data) }
        else if kind.rich {
            content = try NSAttributedString(data: data, options: [.documentType: kind.attributedType], documentAttributes: nil)
        } else { content = NSAttributedString(string: try codec.decode(data)) }
        editor?.loadDocument()
    }
    override func data(ofType typeName: String) throws -> Data {
        try editor?.synchronizeHTMLPreview()
        let value: NSAttributedString
        if let editor, editor.htmlSourceView { value = NSAttributedString(string: try editor.expandedHTMLSource()) }
        else { value = editor?.documentContent() ?? content }
        let destination = Format(type: typeName)
        if destination == .html && (htmlRich || format.rich || HTMLImages.containsImages(value)) { return try HTMLImages.encode(value, title: htmlTitle, dark: savesDarkHTML) }
        if destination != .html && HTMLEmbeds.contains(value) { throw aiError("Save as HTML to keep interactive embeds, or use Make Plain Text to remove them.") }
        if HTMLImages.containsImages(value) && !destination.rich { throw aiError("Save as HTML to retain embedded images, or use Make Plain Text to remove them first.") }
        if destination.rich {
            return try value.data(from: NSRange(location: 0, length: value.length), documentAttributes: [.documentType: destination.attributedType])
        }
        if destination == .html {
            var sourceValue = value.string
            if let editor, editor.htmlSourceView, editor.richHTMLSnapshot != nil, editor.text.string != editor.richHTMLSource { sourceValue = sourceValue.replacingOccurrences(of: HTMLImages.marker, with: "") }
            let embedded = try HTMLFonts.embedSource(sourceValue)
            let source = (editor != nil || htmlSaveURL != nil || fileURL != nil) ? HTMLPage.withSavedAppearance(in: embedded, dark: savesDarkHTML) : embedded
            if (htmlSaveURL ?? fileURL) == nil { return try codec.encode(source) }
            return try codec.encode(HTMLPage.withFavicon(in: HTMLPage.withTitle(htmlTitle, in: source)))
        }
        return try codec.encode(value.string)
    }
    override func save(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType, completionHandler: @escaping (Error?) -> Void) {
        htmlSaveURL = url
        let savesRichHTML = Format(type: typeName) == .html && (htmlRich || format.rich || HTMLImages.containsImages(editor?.documentContent() ?? content))
        super.save(to: url, ofType: typeName, for: saveOperation) { error in
            self.htmlSaveURL = nil
            if error == nil { DispatchQueue.main.async { self.htmlRich = savesRichHTML; self.editor?.loadFormatState() } }
            completionHandler(error)
        }
    }
    @objc func makeHTML(_ sender: Any?) {
        content = editor?.documentContent() ?? content
        becomeImageHTML()
        updateChangeCount(.changeDone)
    }
    func becomeImageHTML() {
        if format != .html || !htmlRich {
            let name = (displayName as NSString).deletingPathExtension + ".html"
            fileType = Format.html.type
            fileURL = nil
            displayName = name
        }
        htmlRich = true
        editor?.loadFormatState()
    }
    @objc func makePlainText(_ sender: Any?) {
        guard isRich else { return }
        let alert = NSAlert()
        alert.messageText = "Make plain text?"
        alert.informativeText = "This removes fonts, styles, images, and other formatting. Save As will let you keep the original formatted file."
        alert.addButton(withTitle: "Make Plain Text"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        editor?.stripFormatting()
        content = editor?.documentContent() ?? NSAttributedString(string: content.string)
        let plainName = (displayName as NSString).deletingPathExtension + ".txt"
        htmlRich = false
        fileType = Format.txt.type
        fileURL = nil
        displayName = plainName
        updateChangeCount(.changeDone)
        editor?.loadFormatState()
    }
}

import UniformTypeIdentifiers
func UTTypeFor(_ kind: Format) -> UTType { UTType(kind.type) ?? UTType(filenameExtension: kind.rawValue) ?? .plainText }
