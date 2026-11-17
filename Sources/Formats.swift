import AppKit
import UniformTypeIdentifiers

enum Format: String, CaseIterable {
    case txt, md, rtf, tex, json, html, docx, py, js
    var type: String {
        switch self {
        case .txt: return "public.plain-text"
        case .md: return "net.daringfireball.markdown"
        case .rtf: return "public.rtf"
        case .tex: return "org.tug.tex"
        case .json: return "public.json"
        case .html: return "public.html"
        case .docx: return "org.openxmlformats.wordprocessingml.document"
        case .py: return "public.python-script"
        case .js: return "com.netscape.javascript-source"
        }
    }
    var rich: Bool { self == .rtf || self == .docx }
    var title: String { self == .txt ? "Plain text" : rawValue.uppercased() }
    init(type: String) { self = Self.allCases.first { $0.type == type } ?? .txt }
    static func from(_ url: URL) -> Format { Format(rawValue: url.pathExtension.lowercased()) ?? .txt }
    var attributedType: NSAttributedString.DocumentType { self == .docx ? .officeOpenXML : .rtf }
}

struct PlainCodec {
    var encoding: String.Encoding = .utf8
    var utf8BOM = false
    var label: String { encoding == .utf8 ? "UTF-8" : encoding == .utf16LittleEndian ? "UTF-16 LE" : encoding == .utf16BigEndian ? "UTF-16 BE" : "\(String.localizedName(of: encoding))" }
    mutating func decode(_ data: Data) throws -> String {
        var content = data
        if data.starts(with: [0xEF, 0xBB, 0xBF]) { utf8BOM = true; content = data.dropFirst(3); encoding = .utf8 }
        else if data.starts(with: [0xFF, 0xFE]) { encoding = .utf16LittleEndian; content = data.dropFirst(2) }
        else if data.starts(with: [0xFE, 0xFF]) { encoding = .utf16BigEndian; content = data.dropFirst(2) }
        else { encoding = .utf8 }
        guard let string = String(data: content, encoding: encoding) else {
            throw NSError(domain: "qlm", code: 1, userInfo: [NSLocalizedDescriptionKey: "This file is not valid UTF-8 or UTF-16 text. Convert its encoding before opening it in qlm."])
        }
        return string
    }
    func encode(_ string: String) throws -> Data {
        guard var data = string.data(using: encoding, allowLossyConversion: false) else { throw CocoaError(.fileWriteInapplicableStringEncoding) }
        if encoding == .utf16LittleEndian { data = Data([0xFF,0xFE]) + data }
        if encoding == .utf16BigEndian { data = Data([0xFE,0xFF]) + data }
        if encoding == .utf8 && utf8BOM { data = Data([0xEF,0xBB,0xBF]) + data }
        return data
    }
}

enum RecentFiles {
    static let key = "qlm.recentFiles"
    static func urls(in defaults: UserDefaults = .standard) -> [URL] { (defaults.stringArray(forKey: key) ?? []).compactMap(URL.init(string:)) }
    static func record(_ url: URL, in defaults: UserDefaults = .standard) {
        let normalized = url.standardizedFileURL
        let updated = [normalized] + urls(in: defaults).filter { $0.standardizedFileURL != normalized }
        defaults.set(Array(updated.prefix(30)).map(\.absoluteString), forKey: key)
    }
}

final class QLMDocumentController: NSDocumentController {
    override init() {
        super.init()
        // Seed the standard macOS menu from qlm's own persistent list after rebuilds/relaunches.
        for url in RecentFiles.urls().reversed() { super.noteNewRecentDocumentURL(url) }
    }
    required init?(coder: NSCoder) { super.init(coder: coder) }
    override func noteNewRecentDocumentURL(_ url: URL) {
        RecentFiles.record(url)
        super.noteNewRecentDocumentURL(url)
    }
    override func clearRecentDocuments(_ sender: Any?) {
        UserDefaults.standard.removeObject(forKey: RecentFiles.key)
        super.clearRecentDocuments(sender)
    }
    override var allowsAutomaticShareMenu: Bool { false }
    override var maximumRecentDocumentCount: Int { 30 }
    override func typeForContents(of url: URL) throws -> String { Format.from(url).type }
    override var defaultType: String? { Format.txt.type }
}
