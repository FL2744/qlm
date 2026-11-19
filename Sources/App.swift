import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    let documents = QLMDocumentController()
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        UserDefaults.standard.set(false, forKey: "NSAutomaticSpellingCorrectionEnabled")
        UserDefaults.standard.set(false, forKey: "NSAutomaticTextCompletionEnabled")
        UserDefaults.standard.set(false, forKey: "NSAutomaticDashSubstitutionEnabled")
        UserDefaults.standard.set(false, forKey: "NSAutomaticTextReplacementEnabled")
        UserDefaults.standard.set(true, forKey: "NSAutomaticQuoteSubstitutionEnabled")
        buildMenus()
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        if ProcessInfo.processInfo.arguments.contains("--self-test") {
            do { try runSelfTests(); print("qlm self-tests passed"); exit(0) }
            catch { fputs("Self-test failed: \(error)\n", stderr); exit(1) }
        }
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { !ProcessInfo.processInfo.arguments.contains("--self-test") }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { documents.newDocument(nil) }
        return true
    }
    func buildMenus() {
        let main = NSMenu(); NSApp.mainMenu = main
        func menu(_ name: String) -> NSMenu { let item = NSMenuItem(); item.title = name; let m = NSMenu(title: name); item.submenu = m; main.addItem(item); return m }
        func item(_ m: NSMenu, _ title: String, _ action: Selector?, _ key: String = "", _ modifiers: NSEvent.ModifierFlags = .command) {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: key); i.keyEquivalentModifierMask = modifiers; m.addItem(i)
        }
        let app = menu("qlm")
        item(app, "About qlm", #selector(about(_:)))
        item(app, "Settings…", #selector(openSettings(_:)), ",")
        app.addItem(.separator())
        item(app, "Hide qlm", #selector(NSApplication.hide(_:)), "h", [.command, .control])
        item(app, "Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option])
        item(app, "Show All", #selector(NSApplication.unhideAllApplications(_:)))
        app.addItem(.separator()); item(app, "Quit qlm", #selector(NSApplication.terminate(_:)), "q")
        let file = menu("File")
        item(file, "New", #selector(NSDocumentController.newDocument(_:)), "n")
        item(file, "Open…", #selector(NSDocumentController.openDocument(_:)), "o")
        file.addItem(.separator())
        item(file, "Close", #selector(NSWindow.performClose(_:)), "w")
        item(file, "Save…", #selector(NSDocument.save(_:)), "s")
        item(file, "Save As…", #selector(NSDocument.saveAs(_:)), "s", [.command, .shift])
        item(file, "Revert to Saved…", #selector(NSDocument.revertToSaved(_:)))
        file.addItem(.separator())
        let export = NSMenu(title: "Export")
        let exportItem = NSMenuItem(title: "Export", action: nil, keyEquivalent: ""); exportItem.submenu = export; file.addItem(exportItem)
        for (title, ext) in [("PDF…", "pdf"), ("Window as PNG…", "png"), ("Window as JPG…", "jpg"), ("Window as TIFF…", "tiff")] {
            let i = NSMenuItem(title: title, action: #selector(EditorController.exportDocument(_:)), keyEquivalent: ""); i.representedObject = ext; export.addItem(i)
        }
        file.addItem(.separator())
        item(file, "Print…", #selector(EditorController.printCurrentDocument(_:)), "p")
        let edit = menu("Edit")
        item(edit, "Undo", Selector(("undo:")), "z"); item(edit, "Redo", Selector(("redo:")), "z", [.command, .shift]); edit.addItem(.separator())
        item(edit, "Cut", #selector(NSText.cut(_:)), "x"); item(edit, "Copy", #selector(NSText.copy(_:)), "c"); item(edit, "Paste", #selector(NSText.paste(_:)), "v")
        item(edit, "Paste as Plain Text", #selector(EditorController.pastePlain(_:)), "v", [.command, .option, .shift])
        item(edit, "Select All", #selector(NSText.selectAll(_:)), "a")
        edit.addItem(.separator())
        let find = NSMenuItem(title: "Find…", action: #selector(NSTextView.performFindPanelAction(_:)), keyEquivalent: "f"); find.tag = NSTextFinder.Action.showFindInterface.rawValue; edit.addItem(find)
        let next = NSMenuItem(title: "Find Next", action: #selector(NSTextView.performFindPanelAction(_:)), keyEquivalent: "g"); next.tag = NSTextFinder.Action.nextMatch.rawValue; edit.addItem(next)
        edit.addItem(.separator())
        item(edit, "Rewrite Selection", #selector(EditorController.rewriteSelection(_:)), "r")
        item(edit, "Translate Selection…", #selector(EditorController.translateSelection(_:)), "t")
        item(edit, "Cancel API Request", #selector(EditorController.cancelTextAction(_:)))
        let insert = menu("Insert")
        item(insert, "Link…", #selector(EditorController.insertHyperlink(_:)), "h")
        item(insert, "Image…", #selector(EditorController.insertImage(_:)), "i", [.command, .shift])
        item(insert, "HTML Embed…", #selector(EditorController.insertHTMLEmbed(_:)))
        let format = menu("Format")
        item(format, "Font…", #selector(EditorController.showFontPicker(_:)))
        item(format, "Resize Image…", #selector(EditorController.resizeImage(_:)))
        item(format, "Make HTML", #selector(QLMDocument.makeHTML(_:)))
        item(format, "Make Plain Text…", #selector(QLMDocument.makePlainText(_:)), "t", [.command, .shift])
        format.addItem(.separator())
        let optionsItem = NSMenuItem(title: "Options", action: nil, keyEquivalent: "")
        let options = NSMenu(title: "Options")
        optionsItem.submenu = options; format.addItem(optionsItem)
        item(options, "Writing Direction: Automatic", #selector(EditorController.directionNatural(_:)))
        item(options, "Writing Direction: Right to Left", #selector(EditorController.directionRTL(_:)))
        item(options, "Writing Direction: Left to Right", #selector(EditorController.directionLTR(_:)))
        options.addItem(.separator())
        item(options, "Save HTML in Dark Mode", #selector(EditorController.toggleDarkHTMLSave(_:)))
        item(options, "Don't Hide Image Bytes in HTML", #selector(EditorController.toggleImageBytes(_:)))
        item(options, "Pretty-print Source…", #selector(EditorController.prettyPrintSource(_:)))
        let view = menu("View")
        item(view, "Zoom In", #selector(EditorController.zoomIn(_:)), "+")
        item(view, "Zoom Out", #selector(EditorController.zoomOut(_:)), "-")
        item(view, "Actual Size", #selector(EditorController.actualSize(_:)), "0")
        item(view, "Mouse Wheel Zoom", #selector(EditorController.toggleMouseWheelZoom(_:)))
        view.addItem(.separator()); item(view, "Wrap to Page", #selector(EditorController.toggleWrap(_:)))
        item(view, "HTML Source", #selector(EditorController.toggleHTMLSource(_:)))
        let window = menu("Window")
        item(window, "Minimize", #selector(NSWindow.performMiniaturize(_:)), "m")
        item(window, "Zoom", #selector(NSWindow.performZoom(_:)))
        window.addItem(.separator()); item(window, "Bring All to Front", #selector(NSApplication.arrangeInFront(_:)))
        NSApp.windowsMenu = window
    }
    @objc func openSettings(_ sender: Any?) { SettingsController.shared.open() }
    @objc func about(_ sender: Any?) {
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "qlm", .applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1", .version: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1", .credits: NSAttributedString(string: "قلم → qalam → qlm\nA small space for words.\n\nLocal files. Optional API rewriting and translation. No update notifications.")])
    }
}

@main struct QLMApp {
    static func main() {
        if ProcessInfo.processInfo.arguments.contains("--initialize-api-file") {
            do { try APISettingsFile.ensureExists(); print("Created private API setup file."); exit(0) }
            catch { fputs("Could not initialize API setup: \(error.localizedDescription)\n", stderr); exit(1) }
        }
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}
