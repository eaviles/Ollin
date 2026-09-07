import Ollin

/// Embroidery: see the stitches before the machine sews them. The sketch
/// composes a leaf as plain contours (an outline, its veins, and a fill laid as
/// rows), plans them with `Embroidery.stitches(_:in:)`, and draws the plan
/// itself: every penetration as a dot, the thread between them, and the jumps
/// where the thread is carried over. A needle walks the plan at machine speed.
///
/// The same frame writes a `.dst` file a machine reads directly, with each color
/// as its own thread:
///
/// ```sh
/// swift run Example-Export-Embroidery --export-embroidery /tmp/leaf.dst
/// swift run Example-Export-Embroidery --export-embroidery /tmp/leaf.dst --embroidery-width 80
/// ```
@main
final class Embroidery_Example: Sketch {
    @Param("Stitch", 1 ... 6, icon: "ruler", group: "Plan") var stitchLength = 2.5
    @Param("Rows", 0.3 ... 3, icon: "line.3.horizontal", group: "Plan") var fillSpacing = 1.2
    @Param(icon: "figure.walk", group: "View") var needle = true

    private let leaf = Color(hex: 0x2E7D4F)
    private let vein = Color(hex: 0xF3E6B3)
    private let stitchInk = Color(hex: 0x1B1040)

    private var outline: [Vector2] = []
    private var veins: [[Vector2]] = []
    private var rows: [[Vector2]] = []
    private var plan: Stitching?
    private var lastKey = ""

    override func setup() {
        // A leaf: a pointed oval, a midrib, and side veins that curve toward the tip.
        // Laid out in the left half, which is the canvas the plan is made for.
        let center = Vector2(width * 0.25, height * 0.5)
        let long = width * 0.2, wide = height * 0.17
        outline = (0 ..< 96).map { k in
            let t = Double(k) / 96 * .tau
            let taper = pow(abs(sin(t)), 0.75)
            return center + Vector2(cos(t) * long * (0.9 + 0.1 * taper), sin(t) * wide * taper)
        }
        let tip = center + Vector2(long, 0), base = center - Vector2(long, 0)
        veins = [[base, tip]]
        for k in 1 ... 5 {
            let along = Double(k) / 6
            let root = base.lerp(to: tip, along)
            for side in [-1.0, 1.0] {
                let reach = wide * 0.8 * sin(along * .pi)
                veins.append([root, root + Vector2(long * 0.16, side * reach * 0.6),
                              root + Vector2(long * 0.3, side * reach)])
            }
        }
    }

    override func draw() {
        background(Color(white: 0.96))
        let key = "\(stitchLength)/\(fillSpacing)"
        if key != lastKey { replan(); lastKey = key }
        guard let plan else { return }

        // The design as drawn: what the exported file sews. While a vector export
        // records the frame, only the design is drawn, centered, so the plan's own
        // dots and hops never become stitches.
        func design() {
            noStroke()
            fill(leaf)
            drawPolygon(outline)
            stroke(vein)
            strokeWeight(3)
            strokeCap(.round)
            for v in veins { drawPolyline(v) }
        }
        if isVectorExporting {
            withState {
                translate(width / 4, 0)
                design()
            }
            return
        }
        let left = Rectangle(x: 0, y: 0, width: width / 2, height: height)
        withClip(left) { design() }
        // The plan beside it: dots where the needle goes down, the thread between
        // them, the jumps as thin gray hops, and the needle walking the plan.
        withState {
            translate(width / 2, 0)
            noFill()
            var previous: Vector2?
            for stitch in plan.stitches {
                defer { previous = stitch.position }
                guard let p = previous else { continue }
                switch stitch.kind {
                case .stitch:
                    stroke(stitchInk.withAlpha(0.55))
                    strokeWeight(1.2)
                    drawLine(p, stitch.position)
                case .jump:
                    stroke(Color(white: 0.6))
                    strokeWeight(0.6)
                    drawLine(p, stitch.position)
                case .colorChange:
                    break
                }
            }
            noStroke()
            fill(stitchInk)
            for stitch in plan.stitches where stitch.kind == .stitch {
                drawCircle(center: stitch.position, radius: 1.6)
            }
            if needle {
                // The thread sewn so far, over the plan, and the needle at its end.
                let at = needleIndex(in: plan)
                stroke(Color(hex: 0xC94B3F))
                strokeWeight(2.2)
                var last: Vector2?
                for stitch in plan.stitches.prefix(at + 1) {
                    defer { last = stitch.position }
                    guard let p = last, stitch.kind == .stitch else { continue }
                    drawLine(p, stitch.position)
                }
                noStroke()
                fill(Color(hex: 0xC94B3F))
                drawCircle(center: plan.stitches[at].position, radius: 6)
            }
        }
        stroke(Color(white: 0.8))
        strokeWeight(2)
        drawLine(width / 2, 0, width / 2, height)

        noStroke()
        fill(Color(white: 0.25))
        textSize(20)
        textAlign(.left, .bottom)
        let size = plan.size
        drawText("\(plan.stitchCount) stitches, \(Int(plan.threadLength.rounded())) mm of thread, "
                 + "\(Int(size.width.rounded())) × \(Int(size.height.rounded())) mm", 24, height - 24)
    }

    /// The design as contours in one thread: the outline, the veins, and the
    /// fill as rows, planned at the current pitch and spacing.
    private func replan() {
        let settings = Embroidery(width: 100, stitchLength: stitchLength, fillSpacing: fillSpacing)
        let canvas = Rectangle(x: 0, y: 0, width: width / 2, height: height)
        let scale = 100 / canvas.width
        rows = Hatching(spacing: fillSpacing / scale, angle: 0.35).lines(filling: Shape(outline))
        var contours = rows.map { Contour($0, closed: false) }
        contours.append(Contour(outline, closed: true))
        contours.append(contentsOf: veins.map { Contour($0, closed: false) })
        plan = settings.stitches(contours, in: canvas)
    }

    /// Where the needle is, walking the plan at about forty stitches a second.
    private func needleIndex(in plan: Stitching) -> Int {
        let n = plan.stitches.count
        guard n > 0 else { return 0 }
        return Int(time * 40) % n
    }
}
