import AppIntents
import AppKit
import MarcusCore
import MarcusPreview

// Shortcuts actions (App Intents; ROADMAP candidate, scope agreed with
// Ernesto on 2026-10-05). Six actions, all working on *files* — never on
// "whatever is open" — because the files are the user's and the honest
// unit of work. Four of them run without a window; only Open (and Create
// when asked) show the app. The pure parts live in MarcusCore and
// MarcusPreview; this file is the wiring and the error messages.
//
// File parameters use `supportedTypeIdentifiers` (deprecated in macOS 15 in
// favor of UTTypes) because the typed initializer needs macOS 15 and the
// app runs on 14. Every title, description and parameter label is a string literal: the
// metadata processor (scripts/build-dmg.sh) extracts them from the
// compiled constants, and Shortcuts localizes them from the app bundle's
// own Localizable.strings (Resources/Localizable.xcstrings → copied into
// Contents/Resources/*.lproj), not from the SwiftPM resource bundle.

/// What can go wrong, said in the user's language in Shortcuts.
enum IntentError: Error, CustomLocalizedStringResourceConvertible {
    case fileNotOnDisk
    case notText
    case notMarkdown
    case exportFailed

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .fileNotOnDisk: "Marcus needs a file saved on disk."
        case .notText: "Marcus can't read this file as text."
        case .notMarkdown: "Only Markdown and plain-text files can be exported."
        case .exportFailed: "The export could not be written."
        }
    }
}

/// Shared helpers: reading a file the way Marcus reads it, naming outputs.
enum IntentSupport {

    /// The file's text with `\n` terminators, its line ending style and
    /// its URL on disk (nil for data handed over without a file).
    static func decode(_ file: IntentFile) throws -> (text: String, lineEnding: LineEnding, url: URL?) {
        let data: Data
        if let url = file.fileURL {
            data = try Data(contentsOf: url)
        } else {
            data = file.data
        }
        do {
            let decoded = try TextFile.decode(data)
            return (decoded.text, decoded.lineEnding, file.fileURL)
        } catch {
            throw IntentError.notText
        }
    }

    /// The format of a file by its extension, as the app classifies it.
    static func format(of file: IntentFile) -> DocumentFormat {
        DocumentFormat.classify(pathExtension: file.fileURL?.pathExtension
            ?? (file.filename as NSString).pathExtension)
    }

    /// `<destination or the file's folder>/<name>.<ext>`.
    static func outputURL(for file: IntentFile, destination: IntentFile?, pathExtension: String) throws -> URL {
        let folder: URL
        if let destination {
            guard let url = destination.fileURL else { throw IntentError.fileNotOnDisk }
            folder = url
        } else if let url = file.fileURL {
            folder = url.deletingLastPathComponent()
        } else {
            folder = FileManager.default.temporaryDirectory
        }
        let base = ((file.fileURL?.lastPathComponent ?? file.filename) as NSString).deletingPathExtension
        return folder.appendingPathComponent(base).appendingPathExtension(pathExtension)
    }

    /// Opens files in this app and brings it forward, through Launch
    /// Services, so it works whether the intent launched Marcus in the
    /// background or found it running.
    @MainActor
    static func open(_ urls: [URL]) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        _ = try await NSWorkspace.shared.open(urls, withApplicationAt: Bundle.main.bundleURL, configuration: configuration)
    }
}

// MARK: - Open in Marcus

struct OpenInMarcusIntent: AppIntent {
    static let title: LocalizedStringResource = "Open in Marcus"
    static let description = IntentDescription("Opens Markdown or text files in Marcus.")
    static let openAppWhenRun = true

    @Parameter(title: "Files", supportedTypeIdentifiers: ["public.plain-text"])
    var files: [IntentFile]

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$files) in Marcus")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let urls = files.compactMap(\.fileURL)
        guard urls.count == files.count, !urls.isEmpty else { throw IntentError.fileNotOnDisk }
        try await IntentSupport.open(urls)
        return .result()
    }
}

// MARK: - Create Markdown Document

struct CreateDocumentIntent: AppIntent {
    static let title: LocalizedStringResource = "Create Markdown Document"
    static let description = IntentDescription("Writes the text to a new Markdown file (UTF-8, never overwriting an existing one) and returns it.")

    @Parameter(title: "Text")
    var text: String

    @Parameter(title: "File Name", default: "Untitled")
    var name: String

    @Parameter(title: "Folder", description: "Where to create the file. Your Documents folder when left empty.", supportedTypeIdentifiers: ["public.folder"])
    var folder: IntentFile?

    @Parameter(title: "Open in Marcus", default: false)
    var open: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Create Markdown document \(\.$name) with \(\.$text)") {
            \.$folder
            \.$open
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        let directory: URL
        if let folder {
            guard let url = folder.fileURL else { throw IntentError.fileNotOnDisk }
            directory = url
        } else {
            directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser
        }
        let fileName = UniqueFileName.available(UniqueFileName.markdownFileName(from: name)) {
            FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path)
        }
        let url = directory.appendingPathComponent(fileName)
        let content = LineEnding.normalized(text)
        try TextFile.encode(content.hasSuffix("\n") || content.isEmpty ? content : content + "\n", lineEnding: .lf)
            .write(to: url, options: .withoutOverwriting)
        if open {
            try await IntentSupport.open([url])
        }
        return .result(value: IntentFile(fileURL: url))
    }
}

// MARK: - Get Text from Document

struct GetDocumentTextIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Text from Document"
    static let description = IntentDescription("Reads a Markdown or text file the way Marcus does (any encoding it can read losslessly) and returns its text.")

    @Parameter(title: "File", supportedTypeIdentifiers: ["public.plain-text"])
    var file: IntentFile

    static var parameterSummary: some ParameterSummary {
        Summary("Get text from \(\.$file)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let decoded = try IntentSupport.decode(file)
        return .result(value: decoded.text)
    }
}

// MARK: - Append to Document

struct AppendToDocumentIntent: AppIntent {
    static let title: LocalizedStringResource = "Append to Document"
    static let description = IntentDescription("Adds text at the end of a Markdown or text file, keeping its encoding and line endings. If the file is open in Marcus, the editor reloads it.")

    @Parameter(title: "File", supportedTypeIdentifiers: ["public.plain-text"])
    var file: IntentFile

    @Parameter(title: "Text")
    var text: String

    @Parameter(title: "On a New Line", default: true)
    var onNewLine: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Append \(\.$text) to \(\.$file)") {
            \.$onNewLine
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        guard let url = file.fileURL else { throw IntentError.fileNotOnDisk }
        let decoded = try IntentSupport.decode(file)
        let appended = TextAppend.appended(text, to: decoded.text, onNewLine: onNewLine)
        try TextFile.encode(appended, lineEnding: decoded.lineEnding).write(to: url, options: .atomic)
        return .result(value: IntentFile(fileURL: url))
    }
}

// MARK: - Export Document

enum ExportFormat: String, AppEnum {
    case html, pdf, rtf, docx

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Format")
    static let caseDisplayRepresentations: [ExportFormat: DisplayRepresentation] = [
        .html: "HTML",
        .pdf: "PDF",
        .rtf: "RTF",
        .docx: "Word",
    ]

    var pathExtension: String { rawValue }
}

struct ExportDocumentIntent: AppIntent {
    static let title: LocalizedStringResource = "Export Document"
    static let description = IntentDescription("Exports a Markdown file as HTML, PDF, RTF or Word, exactly as File → Export does, and returns the exported file. An existing export with the same name is replaced.")

    @Parameter(title: "File", supportedTypeIdentifiers: ["public.plain-text"])
    var file: IntentFile

    @Parameter(title: "Format", default: .pdf)
    var format: ExportFormat

    @Parameter(title: "Destination Folder", description: "Next to the original when left empty.", supportedTypeIdentifiers: ["public.folder"])
    var destination: IntentFile?

    static var parameterSummary: some ParameterSummary {
        Summary("Export \(\.$file) as \(\.$format)") {
            \.$destination
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        guard IntentSupport.format(of: file).supportsMarkdown else { throw IntentError.notMarkdown }
        let decoded = try IntentSupport.decode(file)
        let output = try IntentSupport.outputURL(for: file, destination: destination, pathExtension: format.pathExtension)
        let title = (output.lastPathComponent as NSString).deletingPathExtension
        let baseURL = decoded.url?.deletingLastPathComponent()
        let text = decoded.text
        switch format {
        case .html:
            let html = MarkdownHTMLExporter.document(from: text, options: HTMLExportOptions(title: title, baseURL: baseURL))
            try html.write(to: output, atomically: true, encoding: .utf8)
        case .rtf:
            try MarkdownRTFExporter.data(from: text, title: title, baseURL: baseURL).write(to: output, options: .atomic)
        case .docx:
            try MarkdownDocxExporter.data(from: text, options: DocxExportOptions(title: title, baseURL: baseURL))
                .write(to: output, options: .atomic)
        case .pdf:
            // Paginated by the same on-demand layout engine as File → Export
            // as PDF, through a document that never shows a window.
            guard let url = decoded.url else { throw IntentError.fileNotOnDisk }
            let controller = NSDocumentController.shared
            let type = try controller.typeForContents(of: url)
            guard let document = try controller.makeDocument(withContentsOf: url, ofType: type) as? MarkdownDocument
            else { throw IntentError.notMarkdown }
            let success = await withCheckedContinuation { continuation in
                document.runPrintJob(.pdfFile(output)) { continuation.resume(returning: $0) }
            }
            guard success else { throw IntentError.exportFailed }
        }
        return .result(value: IntentFile(fileURL: output))
    }
}

// MARK: - Count Words

/// Words and characters as one value Shortcuts can pick apart.
struct WordCount: TransientAppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Word Count")

    @Property(title: "Words")
    var words: Int

    @Property(title: "Characters")
    var characters: Int

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(words) words, \(characters) characters")
    }

    init() {}
}

struct CountWordsIntent: AppIntent {
    static let title: LocalizedStringResource = "Count Words"
    static let description = IntentDescription("Counts words and characters the way Marcus's count bar does (a YAML front matter block is not counted). Pass text, or a file: Shortcuts reads it as text.")

    @Parameter(title: "Text")
    var text: String

    static var parameterSummary: some ParameterSummary {
        Summary("Count words in \(\.$text)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<WordCount> {
        let counts = TextMetrics.count(LineEnding.normalized(text), skippingFrontMatter: true)
        var result = WordCount()
        result.words = counts.words
        result.characters = counts.characters
        return .result(value: result)
    }
}
