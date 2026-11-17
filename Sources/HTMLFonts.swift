import AppKit
import CoreText

/// Self-contained web fonts. Standard fallback fonts remain system fonts.
enum HTMLFonts {
    static let styleID = "qlm-embedded-fonts"
    static let standard = Set(["helvetica", "helvetica neue", "arial", "times", "times new roman", "courier", "courier new", "georgia", "verdana", "tahoma", "trebuchet ms", "palatino", "sans-serif", "serif", "monospace", "system-ui", "cursive", "fantasy", "inherit", "initial"])
    static func cssString(_ value: String) -> String {
        "\"" + value.unicodeScalars.map { scalar in
            if scalar.value < 32 || [34, 60, 62, 92].contains(scalar.value) { return "\\" + String(scalar.value, radix: 16) + " " }
            return String(scalar)
        }.joined() + "\""
    }
    static func usesSystemFont(_ font: NSFont) -> Bool {
        let ctFont = CTFontCreateWithName(font.fontName as CFString, font.pointSize, nil)
        let path = (CTFontCopyAttribute(ctFont, kCTFontURLAttribute) as? URL)?.path ?? ""
        return path.hasPrefix("/System/Library/") || path.hasPrefix("/Library/Apple/System/")
    }
    static func face(_ font: NSFont, family: String) throws -> String {
        let ctFont = CTFontCreateWithName(font.fontName as CFString, font.pointSize, nil)
        guard let url = CTFontCopyAttribute(ctFont, kCTFontURLAttribute) as? URL,
              ["otf", "ttf"].contains(url.pathExtension.lowercased()) else {
            throw aiError("Cannot embed \(font.displayName ?? font.fontName). Use an installed OpenType or TrueType font, or a standard font such as Helvetica.")
        }
        // Respect embedding restrictions; no subsetting or font modification is performed.
        guard let table = CTFontCopyTable(ctFont, CTFontTableTag(0x4F532F32), CTFontTableOptions(rawValue: 0)) as Data?, table.count >= 10 else {
            throw aiError("Cannot determine embedding permission for \(font.fontName). Choose another font.")
        }
        let flags = UInt16(table[8]) << 8 | UInt16(table[9])
        guard flags & 0x000F == 0 || flags & 0x000F == 8, flags & 0x0200 == 0 else {
            throw aiError("\(font.displayName ?? font.fontName) restricts font embedding. Choose a font that permits embedding, such as Inter.")
        }
        let bytes = try Data(contentsOf: url)
        let isOTF = url.pathExtension.lowercased() == "otf"
        let weight = (CTFontCopyTraits(ctFont) as NSDictionary)[kCTFontWeightTrait] as? Double ?? 0
        let cssWeight: Int = weight >= 0.56 ? 900 : weight >= 0.4 ? 800 : weight >= 0.265 ? 700 : weight >= 0.215 ? 600 : weight >= 0.115 ? 500 : weight < -0.6 ? 100 : weight < -0.3 ? 200 : weight < -0.05 ? 300 : 400
        let italic = NSFontManager.shared.traits(of: font).contains(.italicFontMask)
        return "@font-face{font-family:\(cssString(family));font-style:\(italic ? "italic" : "normal");font-weight:\(cssWeight);src:url(data:font/\(isOTF ? "otf" : "ttf");base64,\(bytes.base64EncodedString())) format(\(cssString(isOTF ? "opentype" : "truetype")));font-display:swap;}"
    }
    static func rules(for fonts: [NSFont], exactFaces: Bool = false) throws -> String {
        var seen = Set<String>(), result = ""
        for font in fonts {
            let family = font.familyName ?? font.fontName
            if standard.contains(family.lowercased()) || usesSystemFont(font) { continue }
            let name = exactFaces ? font.fontName : family
            if !seen.insert(name).inserted { continue }
            if exactFaces { result += try face(font, family: name) }
            else {
                let members = NSFontManager.shared.availableMembers(ofFontFamily: family) ?? []
                let faces = members.compactMap { $0.first as? String }.compactMap { NSFont(name: $0, size: 12) }
                for member in faces.isEmpty ? [font] : faces { result += try face(member, family: family) }
            }
        }
        return result
    }
    static func decodedAttribute(_ value: String) -> String {
        var decoded = value
        let entities = ["&quot;": "\"", "&apos;": "'", "&lt;": "<", "&gt;": ">"]
        for (entity, character) in entities { decoded = decoded.replacingOccurrences(of: entity, with: character) }
        let numeric = try! NSRegularExpression(pattern: "&#(x[0-9a-f]+|[0-9]+);", options: .caseInsensitive)
        let ns = decoded as NSString
        for match in numeric.matches(in: decoded, range: NSRange(location: 0, length: ns.length)).reversed() {
            let code = ns.substring(with: match.range(at: 1))
            let number = code.lowercased().hasPrefix("x") ? UInt32(code.dropFirst(), radix: 16) : UInt32(code)
            if let number, let scalar = UnicodeScalar(number) { decoded = (decoded as NSString).replacingCharacters(in: match.range, with: String(scalar)) }
        }
        return decoded.replacingOccurrences(of: "&amp;", with: "&")
    }
    static func embedSource(_ html: String) throws -> String {
        // Restrict scanning to CSS in style elements and inline style attributes.
        let owned = try NSRegularExpression(pattern: "<style\\b[^>]*\\bid=[\"']qlm-embedded-fonts[\"'][^>]*>.*?</style\\s*>", options: [.caseInsensitive, .dotMatchesLineSeparators])
        let source = owned.stringByReplacingMatches(in: html, range: NSRange(html.startIndex..., in: html), withTemplate: "")
        let styles = try NSRegularExpression(pattern: "<style\\b[^>]*>(.*?)</style\\s*>|\\bstyle\\s*=\\s*\"([^\"]*)\"|\\bstyle\\s*=\\s*'([^']*)'", options: [.caseInsensitive, .dotMatchesLineSeparators])
        let declarations = try NSRegularExpression(pattern: "(?:^|[;{])\\s*font-family\\s*:\\s*([^;}]+)", options: [.caseInsensitive])
        var fonts: [NSFont] = []
        let ns = source as NSString
        for style in styles.matches(in: source, range: NSRange(location: 0, length: ns.length)) {
            for group in 1...3 where style.range(at: group).location != NSNotFound {
                let rawCSS = ns.substring(with: style.range(at: group))
                let css = group == 1 ? rawCSS : decodedAttribute(rawCSS)
                for match in declarations.matches(in: css, range: NSRange(css.startIndex..., in: css)) {
                    let list = (css as NSString).substring(with: match.range(at: 1))
                    for item in list.components(separatedBy: ",") {
                        let family = item.replacingOccurrences(of: "!important", with: "").trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'")))
                        if standard.contains(family.lowercased()) || family.hasPrefix("var(") { continue }
                        guard let font = NSFont(name: family, size: 12) else { throw aiError("Install \(family) on this Mac before embedding it in HTML, or use a standard fallback font.") }
                        fonts.append(font)
                    }
                }
            }
        }
        let css = try rules(for: fonts)
        guard !css.isEmpty else { return source }
        let style = "<style id=\"\(styleID)\">\(css)</style>"
        if let head = source.range(of: "</head>", options: .caseInsensitive) { var result = source; result.insert(contentsOf: style, at: head.lowerBound); return result }
        // A style element also works for an HTML fragment; never put markup before a doctype.
        if let body = source.range(of: "<body", options: .caseInsensitive) { var result = source; result.insert(contentsOf: style, at: body.lowerBound); return result }
        return source + style
    }
}
