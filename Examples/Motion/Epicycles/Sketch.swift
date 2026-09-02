import Ollin

/// Fourier epicycles: an imported outline rebuilt by a chain of spinning
/// circles. `Epicycles` runs the discrete Fourier transform over a whale
/// silhouette read by the SVG importer; each term is a circle spinning a
/// whole number of turns per lap, and chained tip to tail the last tip
/// re-draws the whale. The Terms parameter truncates the chain to its largest
/// circles (a handful gives a soft phantom, more sharpens the outline), and
/// the chain itself is drawn by `drawEpicycles`. One trace is one lap, so the
/// sketch declares `loopDuration` and `--export-loop epicycles.gif` renders a
/// seamless cycle.
@main
final class EpicycleTrace: Sketch {
    @Param("Terms", 4...160) var termCount = 64
    @Param("Show chain") var showChain = true

    let period = 12.0
    override var loopDuration: Double? { period }
    var epicycles = Epicycles(points: [])

    override func setup() {
        guard let art = SVG(resource: "whale", in: .module) else { return }
        let fitted = art.fitted(in: bounds.inset(by: .all(140 * scale)))
        guard let outline = fitted.contours.first else { return }
        epicycles = Epicycles(outline, samples: 320)
    }

    override func draw() {
        background(Color(hex: 0x0B1220))
        let phase = loopProgress(over: period)

        // The trail: a fixed length just under one lap, fading toward its
        // tail. Its shape is the same every frame (the pen just re-inks it),
        // so the exported loop has no pop at the wrap. `point(at:)` is
        // periodic, so reaching behind phase 0 wraps by itself.
        let trailLaps = 0.86
        let samples = 560
        let trail = (0 ... samples).map { i in
            epicycles.point(at: phase - trailLaps * (1 - Double(i) / Double(samples)),
                            terms: termCount)
        }
        noFill()
        strokeWeight(3 * scale)
        let chunk = 20
        for start in stride(from: 0, to: samples, by: chunk) {
            let age = 1 - Double(start) / Double(samples)   // 1 at the tail, 0 at the pen
            stroke(Color(hex: 0x9FD6E8, alpha: 0.18 + 0.82 * (1 - age) * (1 - age)))
            drawPolyline(Array(trail[start ... min(start + chunk, samples)]))
        }

        // The machine that draws it: the chain of spinning circles.
        if showChain {
            strokeWeight(1 * scale)
            stroke(Color(hex: 0x51648A, alpha: 0.55))
            drawEpicycles(epicycles, at: phase, terms: termCount)
        }

        // The pen.
        noStroke()
        fill(Color(hex: 0xFFE9A8))
        drawCircle(center: epicycles.point(at: phase, terms: termCount), radius: 5 * scale)
    }
}
