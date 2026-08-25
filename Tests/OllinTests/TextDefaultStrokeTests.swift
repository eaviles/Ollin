import Testing
@testable import Ollin

/// Outline text decorates with the stroke only once the sketch has set one: the
/// initial default (the black 1px shape stroke) must never outline glyphs. A 1px
/// opaque band straddling every contour reads as bolding on a light ground and
/// eats thin light glyphs on a dark one, the defect that surfaced as "dimmed"
/// dark-theme figure labels. These pin the rule at the vertex level, where the
/// band shows up as opaque black runs beside the fill-colored ones.
@Suite
@MainActor
struct TextDefaultStrokeTests {

    private final class Label: Sketch {
        var prepare: (Label) -> Void = { _ in }
        override var canvasSize: CanvasSize { .square(256) }
        override func draw() {
            background(Color(hex: 0x1E1B18))
            textFont(.systemMedium)
            textSize(14)
            fill(Color(hex: 0xE8E5E1, alpha: 0.62))
            prepare(self)
            drawText("thin glyphs", 20, 60)
        }
    }

    /// The distinct vertex colors the frame recorded.
    private func vertexColors(_ prepare: @escaping (Label) -> Void) -> Set<SIMD4<Float>> {
        let sketch = Label()
        sketch.prepare = prepare
        _ = OllinApp.image(of: sketch, frame: 0)
        return Set(sketch.drawer.vertices.map(\.color))
    }

    @Test func defaultStateTextCarriesNoStroke() {
        let colors = vertexColors { _ in }
        #expect(!colors.contains(SIMD4<Float>(0, 0, 0, 1)))
        #expect(colors.count == 1)   // the fill alone
    }

    @Test func anExplicitStrokeStillDecorates() {
        let red = SIMD4<Float>(1, 0, 0, 1)
        let colors = vertexColors { $0.stroke(Color(red: 1, green: 0, blue: 0)) }
        #expect(colors.contains(red))
    }

    /// A stroke set inside `withState` must not leak its "set" mark past the
    /// pop: the restored default is back to never decorating text.
    @Test func popStateRestoresTheUnsetDefault() {
        let colors = vertexColors { sketch in
            sketch.withState { sketch.stroke(.black) }
        }
        #expect(!colors.contains(SIMD4<Float>(0, 0, 0, 1)))
    }
}
