import Foundation

/// Runs outside the UI thread. A failed build never replaces an existing exported PDF.
enum LaTeXExporter {
    static var executable: URL? {
        let candidates = ["/opt/homebrew/bin/tectonic", "/usr/local/bin/tectonic"]
        return candidates.map { URL(fileURLWithPath: $0) }.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
    static func error(_ message: String, detail: String = "") -> NSError {
        NSError(domain: "qlm.LaTeX", code: 1, userInfo: [NSLocalizedDescriptionKey: message, NSLocalizedRecoverySuggestionErrorKey: detail])
    }
    static let transcriptKey = "QLMCompilerTranscript"
    static func compilationError(_ transcript: String) -> NSError {
        let firstError = transcript.components(separatedBy: .newlines).first { $0.hasPrefix("error:") }
        let summary = String((firstError ?? "The compiler stopped before producing a PDF.").prefix(500))
        let recovery = summary + "\n\nCheck that images and other referenced files are beside the saved .tex file in the expected folders. Full details are available in the compiler log below."
        return NSError(domain: "qlm.LaTeX", code: 1, userInfo: [NSLocalizedDescriptionKey: "LaTeX could not be typeset.", NSLocalizedRecoverySuggestionErrorKey: recovery, transcriptKey: transcript])
    }
    static func compile(source: String, directory: URL?, to destination: URL, timeout: TimeInterval = 120) throws {
        guard let executable else {
            throw error("LaTeX PDF export needs Tectonic.", detail: "Install Tectonic with Homebrew (brew install tectonic), then export again.")
        }
        let fm = FileManager.default
        let staging = fm.temporaryDirectory.appendingPathComponent("qlm-tex-" + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }
        let input = staging.appendingPathComponent("input.tex")
        try source.write(to: input, atomically: true, encoding: .utf8)
        let log = staging.appendingPathComponent("compiler.log")
        fm.createFile(atPath: log.path, contents: nil)
        let output = try FileHandle(forWritingTo: log)
        defer { try? output.close() }
        let process = Process()
        process.executableURL = executable
        // stdin lets relative figures, bibliography and input files resolve from the source folder.
        // Shell escape stays disabled. Tectonic caches required TeX resources locally.
        process.arguments = ["--untrusted", "--keep-logs", "--outdir", staging.path, "-"]
        process.currentDirectoryURL = directory ?? staging
        let inputHandle = try FileHandle(forReadingFrom: input)
        defer { try? inputHandle.close() }
        process.standardInput = inputHandle
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let deadline = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
        process.waitUntilExit()
        deadline.cancel()
        let transcript = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
        guard process.terminationReason == .exit, process.terminationStatus == 0 else {
            throw compilationError(transcript)
        }
        let pdf = staging.appendingPathComponent("texput.pdf")
        guard let bytes = try? Data(contentsOf: pdf), bytes.starts(with: Array("%PDF-".utf8)) else {
            throw compilationError(transcript)
        }
        try bytes.write(to: destination, options: .atomic)
    }
}
