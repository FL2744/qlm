import AppKit

/// A reversible display projection. Shorthand is never written to the HTML file.
struct HTMLSourceProjection {
    let display: String
    private var images: [String: String]
    private var comments: [String]

    init(_ source: String) {
        let pattern = try! NSRegularExpression(pattern: "data:image/([a-z0-9.+-]+);base64,([a-z0-9+/=\\r\\n]+)", options: [.caseInsensitive])
        let ns = source as NSString
        var output = source, stored: [String: String] = [:], descriptions: [String: String] = [:]
        let matches = pattern.matches(in: source, range: NSRange(location: 0, length: ns.length))
        for (index, match) in matches.enumerated().reversed() {
            let token = "qlm-embedded://image-\(index + 1)-" + UUID().uuidString.lowercased().prefix(8)
            let original = ns.substring(with: match.range)
            let type = ns.substring(with: match.range(at: 1)).uppercased()
            let data = Data(base64Encoded: ns.substring(with: match.range(at: 2)), options: .ignoreUnknownCharacters)
            let bitmap = data.flatMap(NSBitmapImageRep.init(data:))
            let dimensions = bitmap.map { ", \($0.pixelsWide) × \($0.pixelsHigh) px" } ?? ""
            let size = data.map { ", " + ByteCountFormatter.string(fromByteCount: Int64($0.count), countStyle: .file) } ?? ""
            stored[token] = original
            descriptions[token] = "Embedded image \(index + 1): \(type)\(dimensions)\(size). Image bytes hidden in qlm; retained when saved."
            output = (output as NSString).replacingCharacters(in: match.range, with: token)
        }
        // Place comments around image/link markup, never inside an attribute value.
        let tags = try! NSRegularExpression(pattern: "<(?:img|link)\\b[^>]*>|<style\\b[^>]*>.*?</style\\s*>", options: [.caseInsensitive, .dotMatchesLineSeparators])
        let compact = output as NSString
        var notes: [String] = []
        for match in tags.matches(in: output, range: NSRange(location: 0, length: compact.length)).reversed() {
            let tag = compact.substring(with: match.range)
            let included = stored.keys.filter { tag.contains($0) }.sorted()
            guard !included.isEmpty else { continue }
            let description = included.compactMap { descriptions[$0] }.joined(separator: " ")
            let opening = "<!-- qlm: " + description + (tag.lowercased().hasPrefix("<link") ? " This image is the page icon (favicon)." : "") + " -->\n"
            let closing = "\n<!-- qlm: End embedded image. -->"
            output = (output as NSString).replacingCharacters(in: match.range, with: opening + tag + closing)
            notes.append(opening); notes.append(closing)
        }
        display = output; images = stored; comments = notes
    }
    mutating func compactAdditional(_ source: String) -> String {
        let additional = HTMLSourceProjection(source)
        images.merge(additional.images) { _, new in new }
        comments.append(contentsOf: additional.comments)
        return additional.display
    }
    func expanded(_ edited: String) throws -> String {
        var source = edited
        for note in comments { source = source.replacingOccurrences(of: note, with: "") }
        for (token, original) in images { source = source.replacingOccurrences(of: token, with: original) }
        if source.range(of: "qlm-embedded://image-", options: .caseInsensitive) != nil {
            throw aiError("An embedded image shorthand was changed or copied from another document. Undo that change or insert the image again before saving.")
        }
        return source
    }
}
