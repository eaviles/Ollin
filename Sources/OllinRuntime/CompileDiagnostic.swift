import Foundation

/// One `swiftc` diagnostic, parsed out of the raw compiler log so a host can
/// map it to an editor line. The log a failed `SketchLoader.compile` returns is
/// the compiler's plain text; the lines worth structuring look like
/// `path:line:col: error: message`, and the caret / source-context lines in
/// between are skipped (the raw log stays available for full display).
public struct CompileDiagnostic: Sendable, Equatable {
    public enum Severity: String, Sendable {
        case error, warning, note
    }

    /// The path as the compiler printed it. For a buffer compile this names the
    /// per-compile work copy, not the file on disk; match on `fileName`.
    public let path: String
    public let line: Int
    public let column: Int
    public let severity: Severity
    public let message: String

    /// The path's last component, the stable key for matching a diagnostic to
    /// the buffer it came from (a buffer compile keeps the sketch's file name).
    public var fileName: String {
        (path as NSString).lastPathComponent
    }

    public init(path: String, line: Int, column: Int, severity: Severity, message: String) {
        self.path = path
        self.line = line
        self.column = column
        self.severity = severity
        self.message = message
    }

    /// Parse a raw compiler log into its diagnostics, in order. Lines that
    /// don't match the `path:line:col: severity: message` shape (caret markers,
    /// quoted source, link errors) are dropped.
    public static func parse(_ log: String) -> [CompileDiagnostic] {
        let pattern = #"^(.+?):(\d+):(\d+): (error|warning|note): (.*)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        var diagnostics: [CompileDiagnostic] = []
        log.enumerateLines { rawLine, _ in
            let range = NSRange(rawLine.startIndex..., in: rawLine)
            guard let match = regex.firstMatch(in: rawLine, range: range),
                  let pathRange = Range(match.range(at: 1), in: rawLine),
                  let lineRange = Range(match.range(at: 2), in: rawLine),
                  let columnRange = Range(match.range(at: 3), in: rawLine),
                  let severityRange = Range(match.range(at: 4), in: rawLine),
                  let messageRange = Range(match.range(at: 5), in: rawLine),
                  let line = Int(rawLine[lineRange]),
                  let column = Int(rawLine[columnRange]),
                  let severity = Severity(rawValue: String(rawLine[severityRange]))
            else { return }
            diagnostics.append(CompileDiagnostic(
                path: String(rawLine[pathRange]),
                line: line,
                column: column,
                severity: severity,
                message: String(rawLine[messageRange])))
        }
        return diagnostics
    }
}
