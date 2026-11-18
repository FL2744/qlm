import AppKit
import PDFKit

/// Printing uses a paginated intermediate PDF, never the editor's viewport.
enum DocumentPrinting {
    static func letterInfo() -> NSPrintInfo {
        let info = NSPrintInfo()
        info.paperSize = NSSize(width: 612, height: 792)
        info.orientation = .portrait
        info.topMargin = 36; info.bottomMargin = 36
        info.leftMargin = 54; info.rightMargin = 54
        info.isHorizontallyCentered = false; info.isVerticallyCentered = false
        info.horizontalPagination = .fit; info.verticalPagination = .automatic
        return info
    }
    static func operation(for pdf: PDFDocument, title: String) throws -> NSPrintOperation {
        // PDF pages already include their margins; do not inset them a second time.
        let info = letterInfo()
        info.topMargin = 0; info.bottomMargin = 0; info.leftMargin = 0; info.rightMargin = 0
        guard let operation = pdf.printOperation(for: info, scalingMode: .pageScaleToFit, autoRotate: true) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        operation.jobTitle = title
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        return operation
    }
}

extension EditorController {
    @objc func printCurrentDocument(_ sender: Any?) {
        guard !exportingLaTeX else { return }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("qlm-print-" + UUID().uuidString)
        let url = directory.appendingPathComponent("Document.pdf")
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        catch { window?.presentError(error); return }
        let finish: (Result<Void, Error>) -> Void = { [self] result in
            defer { try? FileManager.default.removeItem(at: directory) }
            exportingLaTeX = false; updateStatus()
            do {
                try result.get()
                guard let pdf = PDFDocument(url: url) else { throw CocoaError(.fileReadCorruptFile) }
                let operation = try DocumentPrinting.operation(for: pdf, title: doc.displayName)
                withExtendedLifetime(pdf) { _ = operation.run() } // Cancel is a normal outcome.
            } catch {
                if doc.format == .tex { LaTeXErrorPresentation.present(error as NSError) }
                else { window?.presentError(error) }
            }
        }
        if doc.format == .tex {
            exportingLaTeX = true; operationStatus = "Preparing print…"
            let source = text.string, folder = doc.fileURL?.deletingLastPathComponent()
            DispatchQueue.global(qos: .userInitiated).async {
                let result = Result { try LaTeXExporter.compile(source: source, directory: folder, to: url) }
                DispatchQueue.main.async { finish(result) }
            }
        } else {
            finish(Result {
                if let web = htmlPreview, !web.isHidden {
                    guard web.editingReady else { throw NSError(domain: "qlm", code: 425, userInfo: [NSLocalizedDescriptionKey: "The page is still loading. Try printing again in a moment."]) }
                    let info = DocumentPrinting.letterInfo()
                    info.jobDisposition = .save
                    info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
                    let operation = web.printOperation(with: info)
                    operation.showsPrintPanel = false; operation.showsProgressPanel = false
                    guard operation.run() else { throw CocoaError(.fileWriteUnknown) }
                } else {
                    try exportPDF(to: url)
                }
            })
        }
    }
}
