import Foundation

/// What pressing Return should do inside a list line (writing aid, opt-in).
/// Pure logic: the editor decides where and whether to apply it.
public enum ListContinuation {

    public enum Action: Equatable, Sendable {
        /// Insert a newline followed by this marker (list continues).
        case insert(String)
        /// The item is empty: remove this line-relative range (the marker)
        /// instead of adding a new item (list ends).
        case endList(NSRange)
    }

    /// Decides the Return action for the given line, or nil for the default
    /// newline. `line` may include its trailing newline.
    public static func actionForReturn(in line: String) -> Action? {
        let content = line.hasSuffix("\n") ? String(line.dropLast()) : line

        let indentEnd = content.firstIndex(where: { $0 != " " && $0 != "\t" }) ?? content.endIndex
        let indent = String(content[..<indentEnd])
        let rest = content[indentEnd...]

        // Bullet: -, * or + followed by a space (a bare "-" run is a
        // thematic break, not a list).
        if let first = rest.first, first == "-" || first == "*" || first == "+" {
            let afterMarker = rest.dropFirst()
            guard afterMarker.first == " " else { return nil }
            let body = afterMarker.dropFirst()
            // Task item: [ ] / [x] / [X] plus space.
            if body.count >= 4, body.hasPrefix("[") {
                let box = body.prefix(4)
                if (box.hasSuffix("] ")), "xX ".contains(Array(box)[1]) {
                    let taskBody = body.dropFirst(4)
                    let marker = "\(indent)\(first) [ ] "
                    return taskBody.trimmingCharacters(in: .whitespaces).isEmpty
                        ? endOfList(markerLength: indent.count + 6)
                        : .insert(marker)
                }
            }
            return body.trimmingCharacters(in: .whitespaces).isEmpty
                ? endOfList(markerLength: indent.count + 2)
                : .insert("\(indent)\(first) ")
        }

        // Ordered: digits then "." or ")" then a space.
        let digits = rest.prefix(while: \.isNumber)
        if !digits.isEmpty, let number = Int(digits) {
            let afterDigits = rest.dropFirst(digits.count)
            guard let delimiter = afterDigits.first, delimiter == "." || delimiter == ")",
                  afterDigits.dropFirst().first == " "
            else { return nil }
            let body = afterDigits.dropFirst(2)
            let markerLength = indent.count + digits.count + 2
            return body.trimmingCharacters(in: .whitespaces).isEmpty
                ? endOfList(markerLength: markerLength)
                : .insert("\(indent)\(number + 1)\(delimiter) ")
        }

        return nil
    }

    private static func endOfList(markerLength: Int) -> Action {
        .endList(NSRange(location: 0, length: markerLength))
    }
}
