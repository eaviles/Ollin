import Ollin

/// The logistic map's bifurcation diagram, printed like a plate from a
/// dynamics text: for every growth rate `r` across the window, the settled
/// orbit's values stack vertically, so the single stable line forks at 3,
/// doubles again and again into chaos, and opens the period-3 window near
/// 3.83. Below it, the Lyapunov exponent for the same window: negative
/// wherever the diagram is a few crisp lines, positive wherever it's a band
/// of dust, kissing zero at every fork.
///
/// Both panels are pure functions of the window, so they render once into
/// retained batches and every frame just replays them; drag the `from`/`to`
/// parameters to zoom into the cascade (try 3.82...3.87: the period-3 window's
/// own doubling cascade, the whole diagram again in miniature).
@main
final class Bifurcation: Sketch {
    @Param(2.4 ... 4.0, icon: "arrow.left.to.line") var from = 2.4
    @Param(2.4 ... 4.0, icon: "arrow.right.to.line") var to = 4.0

    private let map = IteratedMap.logistic()
    private let labelFont = OutlineFont.system
    private var plates: Batch?
    private var builtWindow: ClosedRange<Double> = 0...0

    private var window: ClosedRange<Double> {
        let lo = min(from, to), hi = max(from, to)
        return hi - lo < 0.02 ? lo...(lo + 0.02) : lo...hi
    }

    private var diagramRect: Rectangle {
        Rectangle(x: 90, y: 80, width: width - 180, height: (height - 250) * 0.74)
    }

    private var exponentRect: Rectangle {
        let top = diagramRect.y + diagramRect.height + 56
        return Rectangle(x: 90, y: top, width: width - 180, height: height - 114 - top)
    }

    override func draw() {
        if plates == nil || builtWindow != window {
            builtWindow = window
            plates = makeBatch { drawPlates(over: builtWindow) }
        }

        background(Color(hex: 0xF6F1E7))
        if let plates { drawBatch(plates) }
        drawLabels(over: builtWindow)
    }

    /// Both panels, recorded once per window: the diagram's dot columns and
    /// the exponent trace are static geometry, so the batch replays them for
    /// free while the parameters rest.
    private func drawPlates(over window: ClosedRange<Double>) {
        // The diagram: one column of settled orbit values per pixel, faint
        // ink dots piling into tone where the branches crowd.
        noStroke()
        fill(Color(hex: 0x232A4D).withAlpha(0.18))
        pointSize(1)
        drawBifurcation(map, over: window, in: diagramRect, perColumn: 320, settle: 900)

        // The exponent underneath, on the same horizontal axis. Zero first.
        let rect = exponentRect
        stroke(Color(hex: 0x1F2033).withAlpha(0.25))
        strokeWeight(1)
        let floorL = -2.2, ceilL = 1.0
        let zero = rect.point(u: 0, v: (ceilL - 0) / (ceilL - floorL)).y
        drawLine(rect.x, zero, rect.x + rect.width, zero)

        // The trace, clamped to the panel: superstable dips run to minus
        // infinity, and the print only needs the shape near zero.
        let columns = 540
        let span = window.upperBound - window.lowerBound
        let trace = (0..<columns).map { i -> Vector2 in
            let r = window.lowerBound + span * (Double(i) + 0.5) / Double(columns)
            let l = clamp(map.lyapunovExponent(at: r, iterations: 3000, settle: 300),
                          floorL, ceilL)
            return rect.point(u: (Double(i) + 0.5) / Double(columns),
                              v: (ceilL - l) / (ceilL - floorL))
        }
        noFill()
        stroke(Color(hex: 0xB0492C))
        strokeWeight(1.6 * scale)
        drawPolyline(trace, closed: false)
    }

    private func drawLabels(over window: ClosedRange<Double>) {
        fill(Color(hex: 0x1F2033).withAlpha(0.55))
        textFont(labelFont)
        textSize(15)
        textAlign(.center, .middle)
        let span = window.upperBound - window.lowerBound
        let step = span > 0.8 ? 0.2 : span > 0.2 ? 0.05 : 0.01
        var r = (window.lowerBound / step).rounded(.up) * step
        while r <= window.upperBound + 1e-9 {
            let u = (r - window.lowerBound) / span
            let x = diagramRect.x + u * diagramRect.width
            drawText(String(format: step < 0.05 ? "%.2f" : "%.1f", r),
                     x, exponentRect.y + exponentRect.height + 26)
            r += step
        }
        textAlign(.left, .middle)
        drawText("λ", exponentRect.x - 26, exponentRect.y + 10)
    }
}
