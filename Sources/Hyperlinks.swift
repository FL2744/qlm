import AppKit
import WebKit

enum Hyperlinks {
    static func destination(_ input: String) throws -> URL {
        var value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.contains(":") { value = "https://" + value }
        guard !value.contains(where: { $0.isWhitespace }), let url = URL(string: value),
              let scheme = url.scheme?.lowercased(), ["https", "http", "mailto", "tel", "file"].contains(scheme),
              !["http", "https"].contains(scheme) || !(url.host ?? "").isEmpty else {
            throw aiError("Enter a valid web, email, telephone, or file URL.")
        }
        return url
    }
    static func prompt(existing: String = "", convertsToHTML: Bool = false) -> URL? {
        let field = NSTextField(string: existing)
        field.placeholderString = "https://example.com"
        field.frame = NSRect(x: 0, y: 0, width: 400, height: 24)
        field.setAccessibilityLabel("Link URL")
        let alert = NSAlert()
        alert.messageText = "Insert Link"
        alert.informativeText = convertsToHTML ? "Enter the destination URL. Adding a link makes this an HTML document; your original file stays unchanged." : "Enter the destination URL for the selected text."
        alert.accessoryView = field
        alert.addButton(withTitle: "Apply"); alert.addButton(withTitle: "Cancel")
        alert.buttons[0].keyEquivalent = "\r"; alert.buttons[1].keyEquivalent = "\u{1b}"
        alert.window.initialFirstResponder = field
        while alert.runModal() == .alertFirstButtonReturn {
            do { return try destination(field.stringValue) }
            catch { alert.informativeText = error.localizedDescription }
        }
        return nil
    }
}

extension EditorController {
    @objc func insertHyperlink(_ sender: Any?) {
        if let web = htmlPreview, !web.isHidden {
            let generation = web.editingGeneration
            web.evaluateJavaScript(Self.captureLinkSelection, in: nil, in: .defaultClient) { [weak self, weak web] result in
                guard let self, let web, web.editingGeneration == generation else { return }
                guard case .success(let value) = result, let selection = value as? [String: String] else {
                    self.window?.presentError(aiError("Select the text you want to link first.")); return
                }
                guard let url = Hyperlinks.prompt(existing: selection["href"] ?? "") else { return }
                self.applyWebHyperlink(url, web: web, generation: generation)
            }
            return
        }
        let range = text.selectedRange()
        guard range.length > 0, NSMaxRange(range) <= (text.textStorage?.length ?? 0) else {
            window?.presentError(aiError("Select the text you want to link first.")); return
        }
        let existing = text.textStorage?.attribute(.link, at: range.location, effectiveRange: nil)
        guard let url = Hyperlinks.prompt(existing: (existing as? URL)?.absoluteString ?? existing as? String ?? "", convertsToHTML: !doc.isRich && doc.format != .md && !htmlSourceView) else { return }
        applyHyperlink(url, range: range)
    }
    func applyHyperlink(_ url: URL, range: NSRange) {
        guard range.length > 0, NSMaxRange(range) <= (text.textStorage?.length ?? 0) else { return }
        text.setSelectedRange(range)
        if htmlSourceView {
            let words = (text.string as NSString).substring(with: range)
            text.insertText("<a href=\"" + HTMLImages.escaped(url.absoluteString) + "\">" + HTMLImages.escaped(words) + "</a>", replacementRange: range)
        } else if doc.format == .md {
            let words = (text.string as NSString).substring(with: range).replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
            text.insertText("[" + words + "](<" + url.absoluteString.replacingOccurrences(of: ">", with: "%3E") + ">)", replacementRange: range)
        } else {
            if !doc.isRich { doc.becomeImageHTML() }
            applyFontAttributes([.link: url])
            // New typing after the selection should not inherit its destination.
            text.typingAttributes.removeValue(forKey: .link)
        }
        text.undoManager?.setActionName("Insert Link")
    }
    static let captureLinkSelection = #"""
    (() => {
      const selection = window.getSelection();
      if (!selection || selection.isCollapsed || !selection.rangeCount || !selection.toString().trim()) return null;
      const range = selection.getRangeAt(0);
      if (!document.body.contains(range.commonAncestorContainer)) return null;
      window.qlmLinkRange = range.cloneRange();
      const node = range.startContainer.nodeType === 1 ? range.startContainer : range.startContainer.parentElement;
      return {text:selection.toString(),href:node.closest('a')?.getAttribute('href') || ''};
    })();
    """#
    func applyWebHyperlink(_ url: URL, web: HTMLWebView, generation: String) {
        guard web.editingGeneration == generation else { return }
        let literal = String(data: try! JSONSerialization.data(withJSONObject: [url.absoluteString]), encoding: .utf8)!
        let script = """
        (() => {
          const range = window.qlmLinkRange;
          if (!range || !range.startContainer.isConnected || !range.endContainer.isConnected) return false;
          document.body.focus({preventScroll:true});
          const selection = window.getSelection(); selection.removeAllRanges(); selection.addRange(range);
          const applied = document.execCommand('createLink', false, \(literal)[0]);
          window.qlmLinkRange = null;
          if (applied) document.body.dispatchEvent(new Event('input',{bubbles:true}));
          return applied;
        })();
        """
        web.evaluateJavaScript(script, in: nil, in: .defaultClient) { [weak self] result in
            if case .success(let applied) = result, applied as? Bool == true { return }
            self?.window?.presentError(aiError("The selected text could not be linked. Select it again and retry."))
        }
    }
}
