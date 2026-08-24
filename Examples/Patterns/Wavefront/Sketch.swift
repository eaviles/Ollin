import Ollin

/// Where a wave will be, worked out the way Huygens did it in 1678.
///
/// Every point of a front sends out a little wave of its own. A moment later the
/// front is not the sum of those wavelets, it is the curve they all lean on: their
/// envelope. Hold the mouse to see the wavelets themselves at one step, which is
/// the whole construction in one picture.
///
/// The interesting part is what happens in the hollows. Where the front curves
/// back on itself, the wavelets from either side of the bend get there first, and
/// the piece in the middle is swallowed. It is dropped rather than drawn, so the
/// front tears and comes to a point: that is a focus, and it is why a curved
/// mirror has one.
///
/// The rule that does it is the definition itself. A point of the new front is
/// exactly one wavelet from the old one, and no nearer to any part of it.
@main
final class Wavefront_Example: Sketch {
    override var loopDuration: Double? { 12 }

    private var shore: [Vector2] = []
    private var fronts: [[Contour]] = []
    private let step = 30.0

    override func setup() {
        // A shoreline with a headland in it, so there is something to focus. The
        // wave travels down the canvas, into the side the headland curves toward.
        shore = (0 ... 220).map { i -> Vector2 in
            let x = Double(i) / 220 * (width - 120) + 60
            let t = (x - 60) / (width - 120)
            return Vector2(x, height * 0.17
                + sin(t * .tau * 1.5) * height * 0.10
                + sin(t * .tau * 3.2 + 1) * height * 0.035)
        }
        // The fronts never change, so they are worked out once. Each one costs a
        // pass over every segment of the shore, which is not a per-frame job.
        fronts = stride(from: step, through: height * 0.86, by: step).map {
            huygensFront(from: shore, advancing: -$0)
        }
    }

    override func draw() {
        background(Color(hex: 0x080B12))

        noFill()
        stroke(Color(hex: 0x2A3550))
        strokeWeight(4)
        drawPolyline(shore)

        if mouseIsPressed {
            // The wavelets at one step, and the front they lean on.
            let distance = 150.0
            stroke(Color(hex: 0x4C86FF, alpha: 0.22))
            strokeWeight(1)
            for (index, point) in shore.enumerated() where index % 12 == 0 {
                drawCircle(center: point, radius: distance)
            }
            stroke(Color(hex: 0xFFD166))
            strokeWeight(3)
            for run in huygensFront(from: shore, advancing: -distance) {
                drawPolyline(run.points)
            }
            drawCaption("every point sends out a wavelet; the front is the curve they lean on")
            return
        }

        // A front every so often, out to where the wave has reached.
        let reached = Int((loopProgress(over: 12) * Double(fronts.count + 2)).rounded(.down))
        var pieces = 0
        for (index, front) in fronts.enumerated() where index < reached {
            stroke(CosinePalette.rainbow.color(at: 0.55 + Double(index) / Double(fronts.count) * 0.35)
                .withAlpha(0.85))
            strokeWeight(2)
            for run in front { drawPolyline(run.points) }
            pieces = front.count
        }
        let runs = min(reached, fronts.count)

        drawCaption("\(runs) fronts, the last one in \(pieces) piece\(pieces == 1 ? "" : "s"); "
            + "hold the mouse for the wavelets behind one of them")
    }
}
