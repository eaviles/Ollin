import Ollin

/// A scribble becomes a few curves. A dense trace of points, the kind a hand
/// leaves when it draws with the mouse, is first lightened to the points it
/// needs (`simplified(tolerance:)`), which also pulls each corner it rounded
/// over several points onto one point. The trace is then cut at its corners
/// (`split(atCornersOver:span:)`), and each piece between two corners is
/// traced with a handful of smooth cubic curves (`fitted(tolerance:)`): a
/// `Path`, drawn here with its handles (`Path.cubics`). Hundreds of points
/// come back as a dozen curves that pass within the tolerance of every one.
///
/// Draw with the mouse to trace your own. Otherwise a scribble draws itself
/// over the first half of each lap, fitted as it grows, and the counts in
/// the corner say what the fit saved.
///
/// ```sh
/// swift run Example-Shapes-TraceToCurves --export-loop /tmp/trace-to-curves.gif
/// ```
///
/// The fitted curves are sampled to points on the way out, so `--export-svg`
/// writes them as plottable lines.
@main
final class TraceToCurves: Sketch {
    @Param(0.5 ... 12, icon: "scope") var tolerance = 4.0
    @Param(30 ... 150, icon: "angle") var cornerDegrees = 70.0
    @Param(icon: "point.topleft.down.to.point.bottomright.curvepath") var showsHandles = true
    @Param(icon: "scribble") var showsTrace = true

    private var hand: [Vector2] = []
    private var isTracing = false
    private var demo: [Vector2] = []
    private let period = 10.0
    override var loopDuration: Double? { period }

    override func setup() {
        demo = Self.scribble(width: width, height: height, scale: scale)
    }

    override func mousePressed() {
        hand = [mouse]
        isTracing = true
    }

    override func mouseReleased() {
        isTracing = false
    }

    override func draw() {
        background(Color(hex: 0xF4EAD6))
        if isTracing, let last = hand.last, mouse.distance(to: last) > 1 * scale {
            hand.append(mouse)
        }

        // The hand's trace while there is one, otherwise the scribble
        // revealed over the first half of the lap.
        let shown: [Vector2]
        if hand.count > 1 {
            shown = hand
        } else {
            let progress = min(1, loopProgress(over: period) * 2)
            shown = Array(demo.prefix(max(2, Int(Double(demo.count) * progress))))
        }
        let trace = Contour(shown, closed: false)

        // Lighter first, so a rounded corner becomes one point, then cut at
        // the corners, then each piece fitted.
        let lighter = trace.simplified(tolerance: 0.6 * scale)
        let pieces = lighter.split(atCornersOver: cornerDegrees * .pi / 180, span: 8 * scale)
        let paths = pieces.map { $0.fitted(tolerance: tolerance * scale) }

        if showsTrace {
            noFill()
            stroke(Color(hex: 0x14161C).withAlpha(0.14))
            strokeWeight(16 * scale)
            strokeCap(.round)
            strokeJoin(.round)
            drawPolyline(trace.points)
        }

        for (k, path) in paths.enumerated() {
            let ink = k.isMultiple(of: 2) ? Color(hex: 0x1F4E79) : Color(hex: 0xC2452D)
            if showsHandles {
                stroke(ink.withAlpha(0.45))
                strokeWeight(1.5 * scale)
                for cubic in path.cubics {
                    drawLine(cubic.start, cubic.control1)
                    drawLine(cubic.end, cubic.control2)
                }
                noStroke()
                fill(ink.withAlpha(0.6))
                for cubic in path.cubics {
                    drawCircle(center: cubic.control1, radius: 4 * scale)
                    drawCircle(center: cubic.control2, radius: 4 * scale)
                }
            }
            noFill()
            stroke(ink)
            strokeWeight(5 * scale)
            drawPolyline(path.contour.points)
            noStroke()
            fill(Color(hex: 0x14161C))
            for cubic in path.cubics { drawCircle(center: cubic.start, radius: 6 * scale) }
            if let last = path.cubics.last { drawCircle(center: last.end, radius: 6 * scale) }
        }

        // What the fit saved.
        let curves = paths.reduce(0) { $0 + $1.cubics.count }
        fill(Color(hex: 0x14161C))
        textSize(26 * scale)
        textAlign(.left, .bottom)
        drawText("\(trace.count) points, \(pieces.count) pieces, \(curves) curves", 40 * scale, height - 40 * scale)
    }

    /// A scribble with loops, a couple of sharp corners, and a hand's small
    /// wobble: sampled densely from a drawn path, then shaken by noise.
    static func scribble(width: Double, height: Double, scale: Double) -> [Vector2] {
        let u = width / 1080, v = height / 1080
        var path = Path()
        path.move(to: Vector2(130 * u, 640 * v))
        path.curve(to: Vector2(210 * u, 330 * v))
        path.curve(to: Vector2(330 * u, 560 * v))
        path.curve(to: Vector2(410 * u, 300 * v))
        path.line(to: Vector2(470 * u, 700 * v))
        path.line(to: Vector2(600 * u, 300 * v))
        path.curve(to: Vector2(700 * u, 560 * v))
        path.curve(to: Vector2(640 * u, 760 * v))
        path.curve(to: Vector2(540 * u, 620 * v))
        path.curve(to: Vector2(720 * u, 420 * v))
        path.curve(to: Vector2(900 * u, 520 * v))
        path.curve(to: Vector2(960 * u, 360 * v))
        let smooth = path.contour
        // Dense like a mouse trace, then wobbled like a hand.
        var points: [Vector2] = []
        var walked = 0.0
        let step = 2.5 * scale
        let total = smooth.length
        while walked <= total {
            let p = smooth.point(at: walked / total)
            let wobble = Vector2(sin(walked * 0.37) * 0.6 + sin(walked * 0.11) * 1.1,
                                 cos(walked * 0.29) * 0.6 + sin(walked * 0.07) * 0.9) * scale
            points.append(p + wobble)
            walked += step
        }
        return points
    }
}
