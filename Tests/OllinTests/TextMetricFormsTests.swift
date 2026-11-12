import Testing
@testable import Ollin

/// Every text metric a sketch can ask for is the active font's own number at
/// the active size: `textWidth` is the font's advance for the string,
/// `textAscent` its ascent times the size, and the two spellings of
/// `textBounds` and `textToShapes` answer alike. The sketch adds nothing of
/// its own, so each call is read here beside the value it hands back from the
/// font. The numbers are uneven on purpose (a size that is no font's design
/// size, an anchor off both axes, an alignment that is not the default), and
/// each reading must move when the state it reads does, so a call that
/// answered a constant would fail.
@Suite
@MainActor
struct TextMetricFormsTests {

    /// What a metric call hands back, so one table holds numbers, boxes,
    /// outlines, and characters.
    enum Reading: Equatable, Sendable {
        case number(Double)
        case box(Rectangle)
        case shapes([Shape])
        case characters([Character])
    }

    /// One metric's two spellings: the call on the sketch, and the value it
    /// forwards to. `font` sets the face the pair reads, and `moved` changes
    /// the state the call reads, after which the reading must be another one.
    struct Pair: Sendable, CustomTestStringConvertible {
        let name: String
        let font: @MainActor @Sendable (Sketch) -> Void
        let bare: @MainActor @Sendable (Sketch) -> Reading
        let twin: @MainActor @Sendable (Sketch) -> Reading
        var moved: @MainActor @Sendable (Sketch) -> Void = { $0.textSize(31) }
        var testDescription: String { name }
    }

    nonisolated static let size = 18.5
    nonisolated static let line = "Ollin moves"
    nonisolated static let block = "Ollin\nmoves on"
    nonisolated static let mixed = "aमbन"
    nonisolated static let anchor = Vector2(21, 34)

    nonisolated static let outline = OutlineFont.systemBold
    nonisolated static let bitmap = BitmapFont.builtIn
    nonisolated static let stroke = StrokeFont.builtIn

    nonisolated static let pairs: [Pair] = [
        Pair(name: "width, outline font", font: { $0.textFont(outline) },
             bare: { .number($0.textWidth(line)) },
             twin: { _ in .number(outline.width(of: line, size: size, direction: .automatic)) }),
        Pair(name: "width, bitmap font", font: { $0.textFont(bitmap) },
             bare: { .number($0.textWidth(line)) },
             twin: { _ in .number(Double(bitmap.inkWidth(of: line)) * (size / Double(bitmap.pixelHeight))) }),
        Pair(name: "width, stroke font", font: { $0.textFont(stroke) },
             bare: { .number($0.textWidth(line)) },
             twin: { _ in .number(stroke.width(of: line, size: size)) }),
        Pair(name: "ascent", font: { $0.textFont(outline) },
             bare: { .number($0.textAscent()) },
             twin: { _ in .number(outline.ascent * size) }),
        Pair(name: "descent", font: { $0.textFont(stroke) },
             bare: { .number($0.textDescent()) },
             twin: { _ in .number(stroke.descent * size) }),
        Pair(name: "leading", font: { $0.textFont(bitmap) },
             bare: { .number($0.textLeading()) },
             twin: { _ in .number(Double(bitmap.lineHeight) * (size / Double(bitmap.pixelHeight))) }),
        Pair(name: "bounds by point", font: { $0.textFont(outline) },
             bare: { .box($0.textBounds(block, 21, 34)) },
             twin: { .box($0.textBounds(block, at: anchor)) }),
        // Two lines, centered both ways: the box is the widest line across and
        // one line's advance plus an ascent and a descent down, set around
        // the anchor.
        Pair(name: "bounds from the metrics", font: { $0.textFont(outline) },
             bare: { .box($0.textBounds(block, 21, 34)) },
             twin: { sketch in
                 let extent = sketch.textWidth(block)
                 let height = sketch.textLeading() + sketch.textAscent() + sketch.textDescent()
                 return .box(Rectangle(x: 21 - extent / 2, y: 34 - height / 2, width: extent, height: height))
             }),
        Pair(name: "shapes by point", font: { $0.textFont(outline) },
             bare: { .shapes($0.textToShapes(line, 21, 34)) },
             twin: { .shapes($0.textToShapes(line, at: anchor)) }),
        Pair(name: "shapes from the font", font: { $0.textFont(outline) },
             bare: { .shapes($0.textToShapes(line, 21, 34)) },
             twin: { _ in
                 .shapes(OutlineFont.shapes(of: outline.placedGlyphs(
                     for: line, size: size, alignH: .center, alignV: .middle,
                     direction: .automatic, at: anchor)))
             }),
        // A pixel font holds only the glyphs in its own file, and the
        // built-in one holds no Devanagari. An outline font asks the whole
        // system, which is the state that moves this reading.
        Pair(name: "missing characters", font: { $0.textFont(bitmap) },
             bare: { .characters($0.textMissingCharacters(mixed)) },
             twin: { _ in
                 let missing: [Character] = mixed.filter { bitmap.glyph(for: $0) == nil }
                 return .characters(missing)
             },
             moved: { $0.textFont(outline) }),
    ]

    @Test(arguments: pairs)
    func theMetricIsTheFontsOwn(_ pair: Pair) {
        let sketch = Sketch()
        pair.font(sketch)
        sketch.textSize(Self.size)
        sketch.textAlign(.center, .middle)

        let bare = pair.bare(sketch)
        #expect(bare == pair.twin(sketch))

        pair.moved(sketch)
        #expect(pair.bare(sketch) != bare, "the call ignored the state it reads, and still answers \(bare)")
    }
}
