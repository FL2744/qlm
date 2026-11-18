import AppKit
import Foundation
import UniformTypeIdentifiers

enum HTMLImages {
    static let marker = "<meta name=\"qlm-document\" content=\"embedded-images-v1\"/>"
    static func containsImages(_ value: NSAttributedString) -> Bool {
        var found = false
        value.enumerateAttribute(.attachment, in: NSRange(location: 0, length: value.length)) { value, _, stop in
            if value is NSTextAttachment { found = true; stop.pointee = true }
        }
        return found
    }
    static func fileImages(_ pasteboard: NSPasteboard) -> [URL] {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return urls.filter { (try? $0.resourceValues(forKeys: [.contentTypeKey]).contentType?.conforms(to: .image)) == true }
    }
    static func hasImages(_ pasteboard: NSPasteboard) -> Bool {
        pasteboard.availableType(from: [.png, .tiff]) != nil || !fileImages(pasteboard).isEmpty
    }
    static func attachment(png: Data, size: NSSize? = nil) throws -> NSAttributedString {
        guard let image = NSImage(data: png), image.size.width > 0, image.size.height > 0 else { throw aiError("This image could not be opened.") }
        let factor = min(1, min(480 / image.size.width, 480 / image.size.height))
        let display = size ?? NSSize(width: image.size.width * factor, height: image.size.height * factor)
        let attachment = NSTextAttachment(data: png, ofType: UTType.png.identifier)
        attachment.bounds = NSRect(origin: .zero, size: display)
        return NSAttributedString(attachment: attachment)
    }
    static func png(_ image: NSImage) throws -> Data {
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let bytes = bitmap.representation(using: .png, properties: [:]) else { throw aiError("This image could not be converted to PNG.") }
        return bytes
    }
    static func escaped(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
    static func encode(_ value: NSAttributedString, title: String = "qlm document", dark: Bool = false) throws -> Data {
        var body = ""
        var fonts: [NSFont] = []
        var failure: Error?
        value.enumerateAttributes(in: NSRange(location: 0, length: value.length)) { attributes, range, _ in
            if let embed = attributes[.attachment] as? HTMLEmbedAttachment {
                let code = Data(embed.html.utf8).base64EncodedString()
                let wrapper = HTMLWebView.wrapper(embed.html, dark: dark)
                body += "<iframe data-qlm-embed=\"\(code)\" srcdoc=\"\(escaped(wrapper))\" width=\"560\" height=\"315\" style=\"display:block;max-width:100%;border:0\" allow=\"accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share\" allowfullscreen=\"allowfullscreen\"></iframe>"
            } else if let image = attributes[.attachment] as? NSTextAttachment {
                do {
                    let data: Data
                    if let bytes = image.contents, let picture = NSImage(data: bytes) { data = try png(picture) }
                    else if let bytes = image.fileWrapper?.regularFileContents, let picture = NSImage(data: bytes) { data = try png(picture) }
                    else if let picture = image.image { data = try png(picture) }
                    else { throw aiError("An attachment could not be embedded as an image.") }
                    var size = image.bounds.size
                    if size.width <= 0 || size.height <= 0 {
                        size = NSImage(data: data)?.size ?? NSSize(width: 540, height: 540)
                        let factor = min(1, min(480 / max(1, size.width), 480 / max(1, size.height)))
                        size = NSSize(width: size.width * factor, height: size.height * factor)
                    }
                    body += "<img alt=\"Image\" width=\"\(max(1, Int(size.width)))\" height=\"\(max(1, Int(size.height)))\" src=\"data:image/png;base64,\(data.base64EncodedString())\"/>"
                } catch { failure = error }
            } else {
                let font = attributes[.font] as? NSFont ?? NSFont(name: "Helvetica", size: 12)!
                fonts.append(font)
                let family = HTMLFonts.standard.contains((font.familyName ?? font.fontName).lowercased()) ? (font.familyName ?? font.fontName) : font.fontName
                let selectedColor = attributes[.foregroundColor] as? NSColor ?? .black
                let color = (selectedColor == .textColor ? NSColor.black : selectedColor).usingColorSpace(.sRGB) ?? .black
                let hex = String(format: "#%02X%02X%02X", Int(round(color.redComponent * 255)), Int(round(color.greenComponent * 255)), Int(round(color.blueComponent * 255)))
                let underline = (attributes[.underlineStyle] as? Int ?? 0) != 0
                let traits = NSFontManager.shared.traits(of: font)
                let decoration = ";color:" + hex + ";text-decoration:" + (underline ? "underline" : "none") + ";font-weight:" + (traits.contains(.boldFontMask) ? "700" : "400") + ";font-style:" + (traits.contains(.italicFontMask) ? "italic" : "normal")
                let style = "font-family:" + HTMLFonts.cssString(family) + ",sans-serif;font-size:\(font.pointSize)pt" + decoration
                let link = (attributes[.link] as? URL)?.absoluteString ?? attributes[.link] as? String ?? ""
                let span = "<span data-qlm-font=\"\(escaped(font.fontName))\" data-qlm-link=\"\(escaped(link))\" data-qlm-size=\"\(font.pointSize)\" data-qlm-color=\"\(hex)\" data-qlm-underline=\"\(underline ? "1" : "0")\" style=\"\(escaped(style))\">" + escaped(value.attributedSubstring(from: range).string) + "</span>"
                body += link.isEmpty ? span : "<a href=\"\(escaped(link))\">" + span + "</a>"
            }
        }
        if let failure { throw failure }
        let fontCSS = try HTMLFonts.rules(for: fonts, exactFaces: true)
        let html = """
        <!DOCTYPE html>
        <html xmlns="http://www.w3.org/1999/xhtml"><head><meta charset="utf-8"/>\(marker)<title>\(escaped(title))</title><style id="qlm-embedded-fonts">\(fontCSS)</style><style>body{font:12pt Helvetica,Arial,sans-serif;margin:2em;background:white;color:black}#qlm-content{white-space:pre-wrap;overflow-wrap:anywhere;unicode-bidi:plaintext}img{max-width:100%;height:auto;vertical-align:middle}</style></head><body><div id="qlm-content" dir="auto">\(body)</div></body></html>
        """
        return Data(try HTMLPage.withFavicon(in: HTMLPage.withSavedAppearance(in: html, dark: dark)).utf8)
    }
    static func decode(_ data: Data) throws -> NSAttributedString {
        let delegate = EmbeddedHTMLReader()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse(), delegate.failure == nil, delegate.sawContent else { throw delegate.failure ?? parser.parserError ?? aiError("The embedded HTML document could not be read.") }
        return try delegate.content()
    }
}
private final class EmbeddedHTMLReader: NSObject, XMLParserDelegate {
    var records: [(text: String?, image: Data?, size: NSSize?, attributes: [NSAttributedString.Key: Any])] = []
    var embeds: [Int: String] = [:]
    var currentAttributes: [NSAttributedString.Key: Any] = [:]
    func content() throws -> NSAttributedString {
        let output = NSMutableAttributedString(string: "")
        for (index, record) in records.enumerated() {
            if let html = embeds[index] { output.append(NSAttributedString(attachment: HTMLEmbedAttachment(html: html))); continue }
            if let text = record.text { output.append(NSAttributedString(string: text, attributes: record.attributes)) }
            if let image = record.image { output.append(try HTMLImages.attachment(png: image, size: record.size)) }
        }
        return output
    }
    var inside = false, sawContent = false
    var failure: Error?
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        if name == "div", attributes["id"] == "qlm-content" { inside = true; sawContent = true; return }
        if inside, name == "iframe", let encoded = attributes["data-qlm-embed"], let bytes = Data(base64Encoded: encoded), let code = String(data: bytes, encoding: .utf8) {
            embeds[records.count] = code; records.append((nil, nil, nil, [:]))
        }
        if inside, name == "span", let fontName = attributes["data-qlm-font"] {
            currentAttributes = [:]
            if let link = attributes["data-qlm-link"], !link.isEmpty, let url = URL(string: link) { currentAttributes[.link] = url }
            currentAttributes[.font] = NSFont(name: fontName, size: CGFloat(min(1000, max(1, Double(attributes["data-qlm-size"] ?? "12") ?? 12))))
            if let hex = attributes["data-qlm-color"], hex.count == 7, hex.hasPrefix("#"), let rgb = UInt32(hex.dropFirst(), radix: 16) {
                currentAttributes[.foregroundColor] = NSColor(srgbRed: CGFloat((rgb >> 16) & 255) / 255, green: CGFloat((rgb >> 8) & 255) / 255, blue: CGFloat(rgb & 255) / 255, alpha: 1)
            }
            if attributes["data-qlm-underline"] == "1" { currentAttributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        }
        if inside, name == "img" {
            do {
                guard let source = attributes["src"], source.hasPrefix("data:image/png;base64,"), let bytes = Data(base64Encoded: String(source.dropFirst("data:image/png;base64,".count))) else { throw aiError("This HTML contains an unsupported image reference.") }
                let size = NSSize(width: min(10000, max(1, Double(attributes["width"] ?? "540") ?? 540)), height: min(10000, max(1, Double(attributes["height"] ?? "540") ?? 540)))
                records.append((nil, bytes, size, [:]))
            } catch { failure = error; parser.abortParsing() }
        }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { if inside { records.append((string, nil, nil, currentAttributes)) } }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) { if name == "span" { currentAttributes = [:] }; if name == "div" { inside = false } }
}

extension EditorController {
    @objc func insertImage(_ sender: Any?) {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.image]; panel.allowsMultipleSelection = true
        panel.message = "Images are embedded in an HTML document."
        guard panel.runModal() == .OK else { return }
        insertImageFiles(panel.urls)
    }
    func insertImageFiles(_ urls: [URL]) {
        do {
            let images = try urls.map { url -> Data in
                guard let image = NSImage(contentsOf: url) else { throw aiError("Could not open \(url.lastPathComponent) as an image.") }
                return try HTMLImages.png(image)
            }
            try insertImageData(images)
        } catch { window?.presentError(error) }
    }
    func insertImageData(_ images: [Data]) throws {
        guard !images.isEmpty else { return }
        if htmlSourceView || (doc.format == .html && !doc.htmlRich) {
            insertSourceHTML(images.map { "<img alt=\"Image\" src=\"data:image/png;base64," + $0.base64EncodedString() + "\"/>" }.joined(separator: "\n"))
            return
        }
        let content = NSMutableAttributedString(string: "")
        for (index, data) in images.enumerated() {
            if index > 0 { content.append(NSAttributedString(string: "\n")) }
            content.append(try HTMLImages.attachment(png: data))
        }
        doc.becomeImageHTML()
        text.insertText(content, replacementRange: text.selectedRange())
        text.undoManager?.setActionName("Insert Image")
    }
    func insertImages(from pasteboard: NSPasteboard) -> Bool {
        let images = HTMLImages.fileImages(pasteboard)
        if !images.isEmpty { insertImageFiles(images); return true }
        for type in [NSPasteboard.PasteboardType.png, .tiff] {
            if let bytes = pasteboard.data(forType: type), let image = NSImage(data: bytes) {
                do { try insertImageData([HTMLImages.png(image)]) } catch { window?.presentError(error) }
                return true
            }
        }
        return false
    }
}
