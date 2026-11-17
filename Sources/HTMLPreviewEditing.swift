import AppKit
import WebKit

final class HTMLPreviewEditBridge: NSObject, WKScriptMessageHandler {
    weak var web: HTMLWebView?
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let payload = message.body as? [String: String], payload["generation"] == web?.editingGeneration else { return }
        if payload["kind"] == "ready" { web?.editingReady = true }
        else if payload["kind"] == "dirty" { web?.onDocumentEdit?(nil) }
        else if payload["kind"] == "content", let html = payload["html"] { web?.onDocumentEdit?(html) }
    }
}

extension HTMLWebView {
    static let editingScript = #"""
    (() => {
      if (!document.body) return;
      const original = {};
      for (const name of ['contenteditable','spellcheck','autocorrect','autocomplete','autocapitalize']) original[name] = document.body.getAttribute(name);
      document.body.contentEditable = 'true';
      document.body.spellcheck = false;
      document.body.setAttribute('autocorrect','off');
      document.body.setAttribute('autocomplete','off');
      document.body.setAttribute('autocapitalize','off');
      window.qlmEditedSource = () => {
        const copy = document.documentElement.cloneNode(true);
        const body = copy.querySelector('body');
        for (const [name,value] of Object.entries(original)) {
          if (value === null) body.removeAttribute(name); else body.setAttribute(name,value);
        }
        return Array.from(document.childNodes).map(node => {
          if (node === document.documentElement) return copy.outerHTML;
          if (node.nodeType === Node.DOCUMENT_TYPE_NODE) return new XMLSerializer().serializeToString(node);
          if (node.nodeType === Node.COMMENT_NODE) return '<!--' + node.data + '-->';
          return node.textContent || '';
        }).join('\n');
      };
      window.qlmDocumentDirty = false;
      let timer;
      document.addEventListener('input', () => {
        window.qlmDocumentDirty = true;
        window.webkit.messageHandlers.qlmDocumentEdit.postMessage({generation:window.qlmGeneration,kind:'dirty'});
        clearTimeout(timer);
        timer = setTimeout(() => window.webkit.messageHandlers.qlmDocumentEdit.postMessage({generation:window.qlmGeneration,kind:'content',html:window.qlmEditedSource()}), 180);
      });
      window.webkit.messageHandlers.qlmDocumentEdit.postMessage({generation:window.qlmGeneration,kind:'ready'});
      document.body.focus({preventScroll:true});
    })();
    """#
    func enableDocumentEditing(_ callback: @escaping (String?) -> Void) {
        onDocumentEdit = callback
        let bridge = HTMLPreviewEditBridge(); bridge.web = self
        configuration.userContentController.add(bridge, contentWorld: .defaultClient, name: "qlmDocumentEdit")
        prepareDocumentEditingScript()
    }
    func prepareDocumentEditingScript() {
        editingGeneration = UUID().uuidString
        configuration.userContentController.removeAllUserScripts()
        let script = "window.qlmGeneration = '\(editingGeneration)';\n" + Self.editingScript
        configuration.userContentController.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient))
    }
    func editedSourceIfReady() throws -> String? {
        guard editingReady else { return nil }
        var result: Result<Any, Error>?
        evaluateJavaScript("({html:window.qlmEditedSource(),changed:!!window.qlmDocumentDirty})", in: nil, in: .defaultClient) { result = $0 }
        let deadline = Date().addingTimeInterval(5)
        while result == nil && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.005)) }
        guard let result, let payload = try result.get() as? [String: Any], let source = payload["html"] as? String else { throw aiError("The HTML editor is still busy. Your changes remain open; try saving again.") }
        if payload["changed"] as? Bool == true { documentWasEdited = true }
        return source
    }
}

extension EditorController {
    func receiveHTMLPreviewEdit(_ source: String?) {
        guard document is QLMDocument, !htmlSourceView, doc.format == .html, !doc.htmlRich else { return }
        if let source {
            loading = true; text.string = source; loading = false
            doc.content = NSAttributedString(string: source)
            previewSource = source
        } else { doc.updateChangeCount(.changeDone) }
    }
    func synchronizeHTMLPreview() throws {
        guard document is QLMDocument, !htmlSourceView, doc.format == .html, !doc.htmlRich,
              let web = htmlPreview, !web.isHidden, let source = try web.editedSourceIfReady() else { return }
        // Avoid normalizing untouched source merely because it was previewed.
        if web.documentWasEdited { receiveHTMLPreviewEdit(source) }
    }
}
