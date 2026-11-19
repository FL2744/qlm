import AppKit
import WebKit

/// Runs only the bundled formatter. Document code is passed as a string to its parser.
@MainActor final class SourceFormatter: NSObject, WKNavigationDelegate {
    private let web = WKWebView(frame: .zero, configuration: {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        return configuration
    }())
    private var ready: CheckedContinuation<Void, Error>?
    func format(_ source: String, parser: String) async throws -> String {
        guard source.utf8.count <= 2_000_000 else { throw aiError("Pretty-print previews currently support up to 2 MB of source. Select a smaller file to keep formatting responsive.") }
        web.navigationDelegate = self
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            ready = continuation
            web.loadHTMLString("<!doctype html><html><head><meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; script-src 'unsafe-eval'\"></head><body></body></html>", baseURL: nil)
        }
        for name in ["standalone", "html", "babel", "estree", "postcss"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "js", subdirectory: "Prettier") else { throw aiError("The bundled source formatter is missing. Reinstall qlm.") }
            _ = try await web.evaluateJavaScript(String(contentsOf: url, encoding: .utf8))
        }
        let result = try await web.callAsyncJavaScript("return await prettier.format(source, {parser, plugins: Object.values(prettierPlugins), printWidth: 100, tabWidth: 2, htmlWhitespaceSensitivity: 'strict'});", arguments: ["source": source, "parser": parser], in: nil, contentWorld: .page)
        guard let formatted = result as? String else { throw aiError("The source could not be formatted.") }
        return formatted
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { ready?.resume(); ready = nil }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { ready?.resume(throwing: error); ready = nil }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { ready?.resume(throwing: error); ready = nil }
}

final class SourcePreviewController: NSWindowController {
    init(source: String, dark: Bool) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 650), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "qlm — Pretty-print Source"
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        super.init(window: window)
        let root = NSView(); window.contentView = root
        let note = NSTextField(labelWithString: "Read-only preview · Original source unchanged · Close this window to continue editing")
        note.font = .systemFont(ofSize: 12); note.textColor = .secondaryLabelColor
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 850, height: 600))
        text.isEditable = false; text.isRichText = false; text.isSelectable = true
        text.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        text.backgroundColor = dark ? .black : .white; text.textColor = dark ? .white : .black
        text.textContainerInset = NSSize(width: 20, height: 16)
        text.isVerticallyResizable = true; text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]; text.textContainer?.widthTracksTextView = true
        text.string = source; text.setAccessibilityLabel("Formatted source preview, read only")
        scroll.documentView = text
        for view in [note, scroll] { view.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(view) }
        NSLayoutConstraint.activate([
            note.topAnchor.constraint(equalTo: root.topAnchor, constant: 12), note.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20), note.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -20),
            scroll.topAnchor.constraint(equalTo: note.bottomAnchor, constant: 12), scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor), scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])
        if let screen = NSScreen.main { window.setFrame(EditorController.boundedFrame(window.frame, within: screen.visibleFrame), display: false) }
        window.center()
    }
    required init?(coder: NSCoder) { fatalError() }
}

extension EditorController {
    func sourceProjection(_ source: String) -> HTMLSourceProjection? {
        Self.showImageBytes ? nil : HTMLSourceProjection(source)
    }
    @objc func prettyPrintSource(_ sender: Any?) {
        guard !formattingSource else { return }
        let source: String
        do {
            if doc.format == .html {
                if !htmlSourceView { toggleHTMLSource(nil) }
                guard htmlSourceView else { return }
                source = try expandedHTMLSource()
            } else { source = text.string }
        } catch { window?.presentError(error); return }
        let parser = doc.format == .html ? "html" : doc.format == .json ? "json" : "babel"
        formattingSource = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.formattingSource = false }
            do {
                let formatter = SourceFormatter()
                let formatted = try await formatter.format(source, parser: parser)
                let display = parser == "html" ? (self.sourceProjection(formatted)?.display ?? formatted) : formatted
                self.sourcePreview = SourcePreviewController(source: display, dark: !self.light)
                self.sourcePreview?.showWindow(nil); self.sourcePreview?.window?.makeKeyAndOrderFront(nil)
            } catch { self.window?.presentError(aiError("Could not pretty-print this source. The original is unchanged. Check its syntax or try a smaller file.")) }
        }
    }
}
