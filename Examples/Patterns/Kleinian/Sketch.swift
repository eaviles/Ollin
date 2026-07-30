import Ollin

/// Kleinian limit sets, traced live along their own curve.
///
/// Two complex traces pick a Möbius group; the depth-first walk returns its
/// limit set as one *ordered* closed curve, and this sketch spends the loop
/// proving it: a bright head runs the whole Jordan curve once per lap while
/// the full lace waits underneath. The gasket, the spirals, and the cusps
/// are all the same recipe with different traces. Click or press a key for
/// the next preset.
@main
final class Kleinian: Sketch {
    override var loopDuration: Double? { 16 }

    private let presets: [(name: String, preset: KleinianPreset)] = [
        ("the Apollonian gasket", .gasket),
        ("a spiral pair", .spiralPair),
        ("lace", .lace),
        ("the 1/15 double cusp", .doubleCusp),
        ("a deep cusp", .cusp),
        ("symmetric cusps", .symmetricCusps),
    ]
    private var index = 2
    private var curve: [Vector2] = []

    override func setup() {
        traceCurve()
    }

    override func draw() {
        background(Color(hex: 0x0B0D12))
        guard curve.count > 3 else { return }

        // The whole limit set, faint.
        noFill()
        stroke(Color(hex: 0x3D4A63))
        strokeWeight(1.2)
        drawPolyline(curve, closed: true)

        // The head: a window of the ordered curve, run once per loop.
        let head = loopProgress(over: 16) * Double(curve.count)
        let span = max(curve.count / 24, 8)
        var window: [Vector2] = []
        window.reserveCapacity(span)
        for i in 0 ..< span {
            window.append(curve[(Int(head) + i) % curve.count])
        }
        stroke(Color(hex: 0xF2D398))
        strokeWeight(2.5)
        drawPolyline(window)

        drawCaption("\(presets[index].name), one connected curve; click or press a key for the next")
    }

    override func mousePressed() { advance() }
    override func keyPressed() { advance() }

    private func advance() {
        index = (index + 1) % presets.count
        traceCurve()
    }

    private func traceCurve() {
        let traced = kleinianLimitSet(presets[index].preset, epsilon: 0.0035)
        curve = fitted(traced.points, in: canvasRectangle.inset(by: 110))
    }
}
