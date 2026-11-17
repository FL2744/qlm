import AppKit

func runHTMLAppearanceTests() throws {
    func check(_ condition: Bool, _ message: String) throws { if !condition { throw aiError("HTML appearance test failed: " + message) } }
    let suite = "qlm.dark-html-tests." + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    try check(HTMLPage.darkSavesEnabled(in: defaults), "Dark HTML saves enabled by default")
    defaults.set(false, forKey: HTMLPage.darkSaveKey)
    try check(!HTMLPage.darkSavesEnabled(in: defaults), "Dark HTML save preference can be disabled")
    let source = "<!DOCTYPE html><html><head><title>Example</title></head><body><span style=\"color:red\">Words</span></body></html>"
    let dark = HTMLPage.withSavedAppearance(in: source, dark: true)
    try check(dark.contains("background:#000!important;color:#fff!important") && dark.contains("body *{color:#fff!important"), "Dark HTML overrides inline text colors and sets black background")
    try check(HTMLPage.withSavedAppearance(in: dark, dark: true) == dark, "Repeated saves keep one appearance block")
    try check(HTMLPage.withSavedAppearance(in: dark, dark: false) == source, "Disabling restores original HTML colors without deleting author styles")
    let content = NSAttributedString(string: "White on black", attributes: [.font: NSFont(name: "Helvetica", size: 12)!, .foregroundColor: NSColor.red])
    let output = try HTMLImages.encode(content, title: "Dark test", dark: true)
    try check(String(data: output, encoding: .utf8)!.contains("qlm-saved-appearance"), "Formatted HTML encodes dark appearance")
    let reloaded = try HTMLImages.decode(output)
    try check(reloaded.string == content.string, "Dark HTML preserves editable document content")
    let option = NSApp.mainMenu?.item(withTitle: "Format")?.submenu?.item(withTitle: "Options")?.submenu?.item(withTitle: "Save HTML in Dark Mode")
    try check(option?.action == #selector(EditorController.toggleDarkHTMLSave(_:)), "Format Options exposes the preference")
    print("Verified default dark HTML saves, preference opt-out, repeat saves, author color restoration, and formatted HTML round-trip.")
}
