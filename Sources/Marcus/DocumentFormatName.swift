import MarcusCore
import UniformTypeIdentifiers

extension DocumentFormat {
    /// User-facing name for the format indicator (count bar, window
    /// subtitle): "Markdown", "Plain Text", or whatever the system calls
    /// the type ("HTML text", "CSS"…) — already localized by macOS — with
    /// the bare extension as the last resort for types nobody declared.
    var displayName: String {
        switch self {
        case .markdown:
            return L("Markdown")
        case .plainText:
            return L("Plain Text")
        case .other(let fileExtension):
            guard !fileExtension.isEmpty else { return L("Plain Text") }
            // Dynamic types (unknown extensions) carry no real description;
            // the uppercased extension reads better than their identifier.
            if let type = UTType(filenameExtension: fileExtension), !type.isDynamic,
               let name = type.localizedDescription {
                return name
            }
            return fileExtension.uppercased()
        }
    }
}
