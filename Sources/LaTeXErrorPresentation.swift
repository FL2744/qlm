import AppKit

enum LaTeXErrorPresentation {
    static func alert(for error: NSError) -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(error.localizedDescription.prefix(200))
        alert.informativeText = String((error.localizedRecoverySuggestion ?? "Check the LaTeX source and try exporting again.").prefix(900))
        alert.addButton(withTitle: "OK")
        alert.buttons[0].keyEquivalent = "\r"
        if let transcript = error.userInfo[LaTeXExporter.transcriptKey] as? String {
            alert.addButton(withTitle: "Copy Compiler Log")
            let visible = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1000, height: 800)
            let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: min(560, max(240, visible.width - 240)), height: min(220, max(100, visible.height - 420))))
            scroll.hasVerticalScroller = true
            scroll.borderType = .bezelBorder
            let log = NSTextView(frame: scroll.bounds)
            log.isEditable = false; log.isSelectable = true
            log.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            log.string = transcript
            log.isVerticallyResizable = true; log.isHorizontallyResizable = false
            log.textContainer?.widthTracksTextView = true
            log.autoresizingMask = [.width]
            log.setAccessibilityLabel("Compiler log")
            scroll.documentView = log
            alert.accessoryView = scroll
        }
        return alert
    }
    static func present(_ error: NSError) {
        let result = alert(for: error).runModal()
        if result == .alertSecondButtonReturn, let transcript = error.userInfo[LaTeXExporter.transcriptKey] as? String {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(transcript, forType: .string)
        }
    }
}
