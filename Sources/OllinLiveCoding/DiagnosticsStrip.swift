import SwiftUI
import Ollin
import OllinRuntime

/// The compact error readout pinned to the stage's bottom edge: one row per
/// compiler diagnostic (click jumps the editor caret to the line), or the raw
/// message when nothing parsed (a shader error, a loader failure). It never
/// dims the stage; during a set the last good sketch keeps playing behind a
/// typo, and this strip is the only sign of it.
struct DiagnosticsStrip: View {
    let diagnostics: [CompileDiagnostic]
    let fallback: String?
    let onJump: (CompileDiagnostic) -> Void

    private static let maxRows = 4

    private var errors: [CompileDiagnostic] {
        diagnostics.filter { $0.severity == .error }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        VStack(alignment: .leading, spacing: 5) {
            if errors.isEmpty {
                if let fallback {
                    Text(condensed(fallback))
                        .lineLimit(3)
                }
            } else {
                ForEach(Array(errors.prefix(Self.maxRows).enumerated()), id: \.offset) { _, diagnostic in
                    Button {
                        onJump(diagnostic)
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("L\(diagnostic.line)")
                                .foregroundStyle(OllinInspector.red)
                                .frame(minWidth: 34, alignment: .trailing)
                            Text(diagnostic.message)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Jump to line \(diagnostic.line)")
                }
                if errors.count > Self.maxRows {
                    Text("+\(errors.count - Self.maxRows) more")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .font(.system(size: 11.5, design: .monospaced))
        .foregroundStyle(Color(white: 0.95))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 720, alignment: .leading)
        .background {
            shape.fill(Color(red: 0.09, green: 0.05, blue: 0.06).opacity(0.92))
                .overlay(shape.fill(OllinInspector.red.opacity(0.08)))
        }
        .overlay(shape.strokeBorder(OllinInspector.red.opacity(0.35), lineWidth: 0.5))
        .textSelection(.enabled)
    }

    /// The raw log trimmed to its informative head (a shader diagnostic's
    /// first lines carry the file, line, and message).
    private func condensed(_ message: String) -> String {
        message
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: "\n")
            .prefix(3)
            .joined(separator: "\n")
    }
}
