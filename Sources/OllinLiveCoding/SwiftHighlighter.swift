import AppKit
import OllinRuntime

/// A lightweight, full-document Swift styler for the performance editor. A
/// regex pass per keystroke is plenty at sketch scale (a few hundred lines),
/// and staying regex-simple keeps the editor dependency-free.
///
/// Beyond token colors it paints two things the stage depends on:
/// - The legibility backdrop: a near-black `backgroundColor` attribute laid
///   over every glyph run (never the newline, so the strip hugs the text
///   instead of filling the line), which keeps code readable over arbitrary
///   visuals without boxing it in a panel.
/// - Diagnostic tints: a red-leaning backdrop across each error line.
@MainActor
struct SwiftHighlighter {
    var fontSize: Double = 15
    var backdropOpacity: Double = 0.55

    // Tokens colored for contrast over the dark strip, whatever runs behind it.
    private static let textColor = NSColor(white: 0.96, alpha: 1)
    private static let keywordColor = NSColor(red: 1.00, green: 0.45, blue: 0.66, alpha: 1)
    private static let typeColor = NSColor(red: 0.45, green: 0.86, blue: 1.00, alpha: 1)
    private static let stringColor = NSColor(red: 1.00, green: 0.80, blue: 0.40, alpha: 1)
    private static let numberColor = NSColor(red: 0.78, green: 0.65, blue: 1.00, alpha: 1)
    private static let commentColor = NSColor(red: 0.58, green: 0.66, blue: 0.60, alpha: 1)
    private static let attributeColor = NSColor(red: 0.55, green: 0.90, blue: 0.60, alpha: 1)

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // The pattern is a fixed literal; a failure is a programmer error.
        try! NSRegularExpression(pattern: pattern)
    }

    /// The token patterns live in `SwiftTokens`, shared with the generator's
    /// source stage. This stage owns the one run its backdrop needs, and the
    /// colors.
    private static let glyphRuns = regex(#"[^\n]+"#)

    private static func color(for kind: SwiftTokens.Kind) -> NSColor {
        switch kind {
        case .type: typeColor
        case .number: numberColor
        case .keyword: keywordColor
        case .attribute: attributeColor
        case .string: stringColor
        case .comment: commentColor
        }
    }

    var font: NSFont {
        .monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }

    private var backdrop: NSColor {
        NSColor(red: 0.03, green: 0.03, blue: 0.06, alpha: backdropOpacity)
    }

    private var flashBackdrop: NSColor {
        NSColor(red: 0.32, green: 0.16, blue: 0.55, alpha: max(backdropOpacity, 0.5))
    }

    private var errorBackdrop: NSColor {
        NSColor(red: 0.42, green: 0.05, blue: 0.10, alpha: max(backdropOpacity, 0.6))
    }

    var typingAttributes: [NSAttributedString.Key: Any] {
        [.font: font, .foregroundColor: Self.textColor, .backgroundColor: backdrop]
    }

    /// Restyle the whole document: base attributes, token colors, the glyph
    /// backdrop, and the diagnostic line tints. Attribute-only edits inside
    /// `beginEditing`/`endEditing` don't re-enter the text-change delegate.
    func apply(to storage: NSTextStorage, diagnostics: [CompileDiagnostic], flashing: Bool) {
        let text = storage.string as NSString
        let all = NSRange(location: 0, length: text.length)
        let strip = flashing ? flashBackdrop : backdrop

        storage.beginEditing()
        storage.setAttributes([.font: font, .foregroundColor: Self.textColor], range: all)

        // In the scanner's own order: a later run paints over an earlier one.
        for run in SwiftTokens.runs(in: storage.string) {
            storage.addAttribute(.foregroundColor, value: Self.color(for: run.kind), range: run.range)
        }

        // The backdrop hugs glyph runs (newlines excluded), so short lines
        // carry short strips rather than full-width bars.
        Self.glyphRuns.enumerateMatches(in: storage.string, range: all) { match, _, _ in
            guard let match else { return }
            storage.addAttribute(.backgroundColor, value: strip, range: match.range)
        }

        for range in Self.lineRanges(of: diagnostics, in: text) {
            storage.addAttribute(.backgroundColor, value: errorBackdrop, range: range)
        }
        storage.endEditing()
    }

    /// The glyph range (newline excluded) of each diagnostic's line.
    private static func lineRanges(of diagnostics: [CompileDiagnostic], in text: NSString) -> [NSRange] {
        guard !diagnostics.isEmpty, text.length > 0 else { return [] }
        var ranges: [NSRange] = []
        let wanted = Set(diagnostics.map(\.line))
        var index = 0
        var line = 1
        while index < text.length {
            let lineRange = text.lineRange(for: NSRange(location: index, length: 0))
            if wanted.contains(line) {
                var content = lineRange
                while content.length > 0 {
                    let last = text.character(at: content.location + content.length - 1)
                    if last == 0x0A || last == 0x0D { content.length -= 1 } else { break }
                }
                if content.length > 0 { ranges.append(content) }
            }
            index = lineRange.location + lineRange.length
            line += 1
        }
        return ranges
    }
}
