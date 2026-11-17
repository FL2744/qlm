import Foundation

enum HTMLPage {
    static let darkSaveKey = "htmlSaveDarkAppearance"
    static func darkSavesEnabled(in defaults: UserDefaults = .standard) -> Bool { defaults.object(forKey: darkSaveKey) as? Bool ?? true }
    static func withSavedAppearance(in source: String, dark: Bool) -> String {
        let pattern = try! NSRegularExpression(pattern: "<style\\b[^>]*\\bid=[\"']qlm-saved-appearance[\"'][^>]*>.*?</style\\s*>", options: [.caseInsensitive, .dotMatchesLineSeparators])
        let clean = pattern.stringByReplacingMatches(in: source, range: NSRange(source.startIndex..., in: source), withTemplate: "")
        guard dark else { return clean }
        let style = "<style id=\"qlm-saved-appearance\">html,body{background:#000!important;color:#fff!important;color-scheme:dark}body *{color:#fff!important;background-color:transparent!important}</style>"
        if let end = clean.range(of: "</head>", options: .caseInsensitive) { var result = clean; result.insert(contentsOf: style, at: end.lowerBound); return result }
        let placeholder = "qlm-appearance-placeholder-76e1"
        return withTitle(placeholder, in: clean).replacingOccurrences(of: "<title>" + placeholder + "</title>", with: style)
    }

    static func withFavicon(in source: String) throws -> String {
        guard let url = Bundle.main.url(forResource: "Favicon", withExtension: "png") else { throw aiError("The HTML favicon is missing from qlm. Rebuild or reinstall the app.") }
        let bytes = try Data(contentsOf: url)
        let link = "<link id=\"qlm-favicon\" rel=\"icon\" type=\"image/png\" sizes=\"64x64\" href=\"data:image/png;base64,\(bytes.base64EncodedString())\"/>"
        let head = try NSRegularExpression(pattern: "<head\\b[^>]*>(.*?)</head\\s*>", options: [.caseInsensitive, .dotMatchesLineSeparators])
        let icons = try NSRegularExpression(pattern: "<link\\b(?=[^>]*\\brel\\s*=\\s*[\"'](?:shortcut\\s+)?icon[\"'])[^>]*>", options: [.caseInsensitive])
        let ns = source as NSString
        if let match = head.firstMatch(in: source, range: NSRange(location: 0, length: ns.length)) {
            let contents = ns.substring(with: match.range(at: 1))
            let clean = icons.stringByReplacingMatches(in: contents, range: NSRange(contents.startIndex..., in: contents), withTemplate: "")
            return ns.replacingCharacters(in: match.range(at: 1), with: clean + link)
        }
        // Reuse the title helper's head construction for HTML fragments.
        let placeholder = "qlm-favicon-placeholder-83db36"
        return withTitle(placeholder, in: source).replacingOccurrences(of: "<title>" + placeholder + "</title>", with: link)
    }

    static func withTitle(_ title: String, in source: String) -> String {
        let element = "<title>" + HTMLImages.escaped(title) + "</title>"
        // Only update document metadata, leaving scripts and body content untouched.
        let head = try! NSRegularExpression(pattern: "<head\\b[^>]*>(.*?)</head\\s*>", options: [.caseInsensitive, .dotMatchesLineSeparators])
        let titlePattern = try! NSRegularExpression(pattern: "<title\\b[^>]*>.*?</title\\s*>", options: [.caseInsensitive, .dotMatchesLineSeparators])
        let ns = source as NSString
        if let match = head.firstMatch(in: source, range: NSRange(location: 0, length: ns.length)) {
            let contents = ns.substring(with: match.range(at: 1))
            let withoutTitles = titlePattern.stringByReplacingMatches(in: contents, range: NSRange(contents.startIndex..., in: contents), withTemplate: "")
            return ns.replacingCharacters(in: match.range(at: 1), with: element + withoutTitles)
        }
        let html = try! NSRegularExpression(pattern: "<html\\b[^>]*>", options: [.caseInsensitive])
        if let match = html.firstMatch(in: source, range: NSRange(location: 0, length: ns.length)) {
            return ns.replacingCharacters(in: NSRange(location: NSMaxRange(match.range), length: 0), with: "<head>" + element + "</head>")
        }
        let doctype = try! NSRegularExpression(pattern: "^\\s*<!doctype\\b[^>]*>", options: [.caseInsensitive])
        let offset = doctype.firstMatch(in: source, range: NSRange(location: 0, length: ns.length)).map { NSMaxRange($0.range) } ?? 0
        return ns.replacingCharacters(in: NSRange(location: offset, length: 0), with: element)
    }
}
