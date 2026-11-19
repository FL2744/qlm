import AppKit
import PDFKit

func runSelfTests() throws {
    func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        if try !condition() { throw NSError(domain: "qlm.tests", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    try QLMDocument.validateEditableSize(1024 * 1024)
    do {
        try QLMDocument.validateEditableSize(470_606_220)
        throw NSError(domain: "qlm.tests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Oversized document was accepted"])
    } catch let error as NSError {
        try check(error.domain == "qlm" && error.code == 413, "Oversized files fail before loading")
    }
    let large = QLMDocument(); large.fileType = Format.json.type
    let largeSource = "[\n" + String(repeating: "{\"value\":123456789},\n", count: 50000) + "{}\n]"
    try large.read(from: Data(largeSource.utf8), ofType: Format.json.type)
    let start = Date()
    large.makeWindowControllers()
    try check(Date().timeIntervalSince(start) < 10, "Large JSON opens without full-document layout")
    try check(try large.data(ofType: Format.json.type) == Data(largeSource.utf8), "Large JSON remains complete and unchanged")
    large.editor?.close()
    let hugeLog = String(repeating: "warning: verbose compiler diagnostic\n", count: 5000) + "error: texput.tex:72: Unable to load picture or PDF file 'figures/missing.png'"
    let compilerError = LaTeXExporter.compilationError(hugeLog)
    try check((compilerError.localizedRecoverySuggestion ?? "").count < 1000 && (compilerError.localizedRecoverySuggestion ?? "").contains("figures/missing.png"), "Compiler summary stays short and identifies the error")
    let compilerAlert = LaTeXErrorPresentation.alert(for: compilerError)
    try check(compilerAlert.buttons.first?.title == "OK" && compilerAlert.buttons.first?.keyEquivalent == "\r", "Compiler error always has a default dismissal button")
    try check((compilerAlert.accessoryView as? NSScrollView)?.documentView is NSTextView && (compilerAlert.accessoryView?.frame.height ?? 1000) <= 220, "Large compiler log uses a bounded scroll view")
    try check((compilerError.userInfo[LaTeXExporter.transcriptKey] as? String) == hugeLog, "Complete compiler log retained for copying")
    let slideSentence = "Most of the projects in this slide deck have technical reports created about them, you can find them at: github.com/fl274https://github.com/FL2744/Technical-Papers/4/"
    let slidePasteboard = NSPasteboard.withUniqueName()
    defer { slidePasteboard.releaseGlobally() }
    slidePasteboard.setData(try Data(contentsOf: Bundle.main.url(forResource: "Favicon", withExtension: "png")!), forType: .png)
    slidePasteboard.setString(slideSentence, forType: .string)
    try check(WritingView.clipboardTextOverImage(slidePasteboard) == slideSentence, "Slide text wins over its image representation")
    let slideDoc = QLMDocument(); slideDoc.fileType = Format.txt.type; slideDoc.makeWindowControllers()
    let slideEditor = slideDoc.editor!
    try check(slideEditor.text.readSelection(from: slidePasteboard, type: .png), "Mixed slide clipboard can be pasted")
    try check(slideEditor.text.string == slideSentence && !HTMLImages.containsImages(slideEditor.documentContent()), "Slide paste remains editable text")
    slideEditor.text.setSelectedRange(NSRange(location: 0, length: (slideSentence as NSString).length))
    try check(slideEditor.selectedPassage()?.value == slideSentence, "AI reads pasted slide text")
    slideEditor.applyFontAttributes([.foregroundColor: NSColor.red])
    try check(slideEditor.documentContent().attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == .red, "Pasted slide text can be recolored")
    try check(EditorController.editablePassage("\u{FFFC}\n\n") == nil, "Image-only AI selections are rejected before a request")
    slidePasteboard.clearContents()
    slidePasteboard.setData(try Data(contentsOf: Bundle.main.url(forResource: "Favicon", withExtension: "png")!), forType: .png)
    try check(WritingView.clipboardTextOverImage(slidePasteboard) == nil, "Image-only paste remains an image")
    slideDoc.updateChangeCount(.changeCleared); slideEditor.close()
    let sample = "qlm\nمرحباً بالعالم\nA ‘quiet’ tool — 𝄞\r\n"
    for encoding in [String.Encoding.utf8, .utf16LittleEndian, .utf16BigEndian] {
        var codec = PlainCodec(); codec.encoding = encoding
        let bytes = try codec.encode(sample)
        var decoded = PlainCodec()
        try check(try decoded.decode(bytes) == sample, "Unicode round-trip")
        try check(try decoded.encode(sample) == bytes, "Encoding preservation")
    }
    var bom = PlainCodec(); bom.utf8BOM = true
    var reader = PlainCodec()
    let bytes = try bom.encode(sample)
    try check(try reader.decode(bytes) == sample && reader.utf8BOM, "UTF-8 BOM")
    let rich = NSAttributedString(string: sample, attributes: [.font: NSFont(name: "Helvetica", size: 12)!])
    for kind in Format.allCases {
        let doc = QLMDocument(); doc.fileType = kind.type; doc.content = rich
        let data = try doc.data(ofType: kind.type)
        let loaded = QLMDocument(); loaded.fileType = kind.type
        try loaded.read(from: data, ofType: kind.type)
        try check(loaded.content.string.contains("مرحباً بالعالم"), "\(kind.rawValue) Arabic round-trip")
        if !kind.rich { try check(loaded.content.string == sample, "\(kind.rawValue) exact text round-trip") }
    }
    let doc = QLMDocument(); doc.fileType = Format.txt.type; doc.content = rich
    doc.makeWindowControllers()
    guard let editor = doc.editor else { fatalError() }
    editor.window?.makeKeyAndOrderFront(nil)
    editor.window?.displayIfNeeded()
    try check(NSDocumentController.shared.maximumRecentDocumentCount == 30, "30 recent files")
    try check(editor.text.font?.pointSize == 12, "Default 12pt font")
    try check(editor.text.font?.familyName == "Helvetica", "Default Helvetica")
    try check(!editor.wrap && !editor.text.isContinuousSpellCheckingEnabled && !editor.text.isGrammarCheckingEnabled, "No wrap/spelling/grammar")
    try check(!editor.text.isAutomaticDashSubstitutionEnabled && !editor.text.isAutomaticLinkDetectionEnabled && !editor.text.isAutomaticSpellingCorrectionEnabled && !editor.text.isAutomaticTextCompletionEnabled, "No automatic substitutions/completion")
    try check(editor.text.isAutomaticQuoteSubstitutionEnabled && !editor.scroll.rulersVisible, "Quotes on, rulers off")
    try check(editor.text.frame.width < 2000, "Short text must not create a huge horizontal canvas")
    try check(editor.wordmark.stringValue == "qlm" && editor.wordmark.font?.pointSize == 12, "Compact 12-point wordmark")
    try check(editor.header.subviews.compactMap { ($0 as? NSTextField)?.stringValue } == ["qlm"], "No extra header text")
    try check(editor.window?.titleVisibility == .hidden && editor.window?.representedURL == nil, "No filename or file icon above header")
    try check(WritingScrollView.zoomDelta(delta: 3, precise: false, modifiers: []) == 0.1, "Wheel up zooms in")
    try check(WritingScrollView.zoomDelta(delta: -3, precise: false, modifiers: []) == -0.1, "Wheel down zooms out")
    try check(WritingScrollView.zoomDelta(delta: 3, precise: false, modifiers: [.option]) == nil, "Option-wheel scrolls normally")
    try check(WritingScrollView.zoomDelta(delta: 3, precise: true, modifiers: []) == nil, "Trackpad remains scrollable")
    try check(WritingScrollView.zoomDelta(delta: 3, precise: false, modifiers: [], enabled: false) == nil, "Disabled mouse-wheel zoom leaves wheel input for scrolling")
    try check(WritingScrollView.zoomDelta(delta: 3, precise: true, modifiers: [.command], enabled: false) == nil, "Disabled wheel zoom also leaves modified trackpad scrolling alone")
    try check(NSApp.mainMenu?.item(withTitle: "View")?.submenu?.item(withTitle: "Mouse Wheel Zoom")?.action == #selector(EditorController.toggleMouseWheelZoom(_:)), "View menu exposes mouse-wheel zoom toggle")
    editor.scroll.onZoom?(0.1)
    try check(abs(editor.zoom - 1.1) < 0.001 && editor.text.font?.pointSize == 12, "Wheel callback zooms without changing saved font")
    editor.actualSize(nil)
    let formatMenu = NSApp.mainMenu?.item(withTitle: "Format")?.submenu
    try check(formatMenu?.item(withTitle: "Options")?.submenu?.items.filter { $0.action == #selector(EditorController.directionNatural(_:)) || $0.action == #selector(EditorController.directionRTL(_:)) || $0.action == #selector(EditorController.directionLTR(_:)) }.count == 3 && formatMenu?.item(withTitle: "Writing Direction: Automatic") == nil, "Writing directions grouped in Format Options")
    let marginSample = editor.documentContent()
    editor.text.string = String(repeating: "Words should fill this window while keeping equal margins. ", count: 400)
    for size in [NSSize(width: 680, height: 580), NSSize(width: 1100, height: 700)] {
        editor.window?.setContentSize(size)
        editor.window?.contentView?.layoutSubtreeIfNeeded()
        for scale: CGFloat in [1, 1.5, 0.75] {
            editor.zoom = scale; editor.changeZoom(0)
            editor.updateContainer()
            let actualScale = editor.scroll.magnification
            let left = (editor.text.textContainerInset.width + (editor.text.textContainer?.lineFragmentPadding ?? 0)) * actualScale
            let right = (editor.scroll.contentView.bounds.width - editor.text.textContainerInset.width - (editor.text.textContainer?.containerSize.width ?? 0) + (editor.text.textContainer?.lineFragmentPadding ?? 0)) * actualScale
            try check(abs(left - 48) < 0.5 && abs(right - 48) < 0.5, "Symmetric fixed side margins at window size and zoom")
            try check(abs(editor.text.frame.width - editor.scroll.contentView.bounds.width) < 1 && !editor.scroll.hasHorizontalScroller, "Text fills window width without horizontal overflow")
            try check(editor.text.frame.height > editor.scroll.contentView.bounds.height, "Long text wraps and scrolls vertically")
        }
    }
    editor.text.textStorage?.setAttributedString(marginSample)
    editor.actualSize(nil)
    editor.updateContainer()
    let originalAttributes = editor.documentContent()
    editor.applyAppearance(lightMode: false)
    try check(editor.text.backgroundColor == .black && editor.scroll.backgroundColor == .black, "Pure black dark canvas")
    let displayedColor = editor.text.layoutManager?.temporaryAttribute(.foregroundColor, atCharacterIndex: 0, effectiveRange: nil) as? NSColor
    try check(displayedColor == .white, "Pure white dark text")
    try check(editor.documentContent().isEqual(to: originalAttributes), "Dark mode must not change saved document colors")
    editor.applyAppearance(lightMode: true)
    try check(editor.text.backgroundColor == .white, "Light canvas restoration")
    for ext in ["png", "jpg", "tiff"] {
        let data = try editor.windowImage(ext)
        guard let bitmap = NSBitmapImageRep(data: data) else { throw CocoaError(.fileReadCorruptFile) }
        try check(bitmap.pixelsWide > 500 && bitmap.pixelsHigh > 300, "Window image dimensions")
        let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["QLM_TEST_OUTPUT"] ?? NSTemporaryDirectory())
        try data.write(to: directory.appendingPathComponent("qlm-window-test." + ext))
    }
    try runHTMLAppearanceTests()
    try runHTMLSourceTests()
    try runFontPickerTests()
    try runHyperlinkTests()
    try runHTMLEmbedTests()
    try runImageTests()
    try runImageResizeTests()
    try runAITests(editor: editor)
    editor.changeZoom(0.5)
    try check(editor.text.font?.pointSize == 12 && editor.zoom == 1.5, "Zoom must not change saved fonts")
    editor.toggleWrap(nil)
    try check(editor.wrap && (editor.text.textContainer?.containerSize.width ?? 0) < 2000, "Wrap bounds")
    let output = URL(fileURLWithPath: ProcessInfo.processInfo.environment["QLM_TEST_OUTPUT"] ?? NSTemporaryDirectory()).appendingPathComponent("qlm-test.pdf")
    editor.text.string = (1...120).map { "Line \($0) — مرحباً بالعالم" }.joined(separator: "\n")
    try editor.exportPDF(to: output)
    let pdf = try Data(contentsOf: output)
    try check(pdf.starts(with: Array("%PDF".utf8)), "PDF export")
    try check((PDFDocument(url: output)?.pageCount ?? 0) >= 3, "PDF must include offscreen text over multiple pages")
    let printed = PDFDocument(url: output)!
    try check(printed.page(at: 0)?.bounds(for: .mediaBox).size == NSSize(width: 612, height: 792), "Print PDF defaults to US Letter")
    try check(printed.string?.contains("120") == true, "Print PDF includes the last offscreen line")
    let printOperation = try DocumentPrinting.operation(for: printed, title: "Print test")
    try check(printOperation.showsPrintPanel && printOperation.jobTitle == "Print test", "Printing offers the native dialog without submitting a job in tests")
    let printItem = NSApp.mainMenu?.item(withTitle: "File")?.submenu?.items.first { $0.action == #selector(EditorController.printCurrentDocument(_:)) }
    try check(printItem?.keyEquivalent == "p", "Print is available with Command-P")
    let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byClipping
    let unwrapped = String(repeating: "LongWord", count: 1000) + " FINALPRINTMARKER"
    editor.text.textStorage?.setAttributedString(NSAttributedString(string: unwrapped, attributes: [.font: NSFont.systemFont(ofSize: 12), .paragraphStyle: paragraph]))
    try editor.exportPDF(to: output)
    let wrapped = PDFDocument(url: output)!
    try check(wrapped.pageCount > 1 && wrapped.string?.filter { !$0.isWhitespace }.contains("FINALPRINTMARKER") == true, "Print wraps long lines even when imported paragraphs disable wrapping")
    try check((editor.documentContent().attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.lineBreakMode == .byClipping, "Print layout does not change the document")
    try check(Format.from(URL(fileURLWithPath: "notes.md")) == .md, "Markdown extension detection")
    try check(UTTypeFor(.md).preferredFilenameExtension == "md", "Markdown file dialog registration")
    let directory = output.deletingLastPathComponent().appendingPathComponent("latex-fixture")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try "Relative input works.".write(to: directory.appendingPathComponent("section.tex"), atomically: true, encoding: .utf8)
    let source = #"""
    \documentclass[11pt]{article}
    \usepackage[margin=1in]{geometry}
    \usepackage{amsmath,booktabs}
    \title{qlm: a small space for words}
    \author{}
    \date{}
    \begin{document}
    \maketitle
    \section{A typeset page}
    This PDF is compiled from LaTeX, including mathematics and a table.
    \input{section.tex}
    \begin{equation}\label{eq:gauss}
    \int_{-\infty}^{\infty}e^{-x^2}\,dx=\sqrt{\pi}
    \end{equation}
    Equation~\ref{eq:gauss} is resolved by the compiler.
    \begin{center}
    \begin{tabular}{lr}\toprule
    Tool & Version \\\midrule
    qlm & 0.2 \\\bottomrule
    \end{tabular}
    \end{center}
    \end{document}
    """#
    doc.fileType = Format.tex.type
    doc.fileURL = directory.appendingPathComponent("example.tex")
    editor.text.string = source
    let latexPDF = output.deletingLastPathComponent().appendingPathComponent("qlm-latex-test.pdf")
    try editor.exportPDF(to: latexPDF)
    guard let compiled = PDFDocument(url: latexPDF) else { throw CocoaError(.fileReadCorruptFile) }
    let compiledText = compiled.string ?? ""
    try check(compiled.pageCount == 1 && compiledText.contains("Relative input works."), "Typeset PDF with relative input")
    try check(!compiledText.contains("documentclass") && !compiledText.contains("??"), "LaTeX commands and references must be rendered")
    let originalPDF = try Data(contentsOf: latexPDF)
    do {
        try LaTeXExporter.compile(source: #"\documentclass{article}\begin{document}\undefinedcommand\end{document}"#, directory: directory, to: latexPDF)
        throw NSError(domain: "qlm.tests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid LaTeX unexpectedly succeeded"])
    } catch let error as NSError where error.domain == "qlm.LaTeX" {
        try check(try Data(contentsOf: latexPDF) == originalPDF, "Failed LaTeX export must preserve existing PDF")
    }
    print("Verified: 9 format round-trips, Markdown type, Arabic/Unicode, encoding, editor defaults, zoom, wrapping, recents, window images, paginated PDF, typeset LaTeX mathematics/table/references/relative input, and safe compiler failure.")
    editor.close()
}
