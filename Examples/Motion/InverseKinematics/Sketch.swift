import Ollin

/// Tentacles that reach: five `IKChain`s planted along the bottom edge, all
/// straining toward a lure that swims a slow loop overhead. Each chain is a
/// row of rigid segments solved fresh every frame, warm-started from its last
/// pose, so the arms move coherently instead of snapping.
///
/// The `stiffness` knob is `maxBend`, the angle each segment may fold against
/// its neighbor: low values make ropes, high values make whips. The `whippy`
/// toggle swaps the solver, and the difference is the whole aesthetic choice:
/// the default spreads motion evenly down the arm (smooth, plant-like), the
/// alternative favors the segments near the tip, so the arms curl and lash.
/// Press the mouse to steal the lure.
@main
final class InverseKinematics: Sketch {
    @Param(0.05 ... 0.8, icon: "line.diagonal.arrow", group: "Arms") var stiffness = 0.22
    @Param(icon: "scribble.variable", group: "Arms") var whippy = false

    private var arms: [IKChain] = []
    private let colors = [Color(hex: 0x2C7DA0), Color(hex: 0x62B6CB),
                          Color(hex: 0x8FBFA0), Color(hex: 0xE9C46A),
                          Color(hex: 0xD1495B)]

    override var loopDuration: Double? { 16 }

    override func setup() {
        arms = (0 ..< 5).map { i in
            let base = Vector2(width * (0.18 + 0.16 * Double(i)), height - 40)
            return IKChain(from: base, segments: 15 + 2 * i, length: 40)
        }
    }

    override func draw() {
        background(Color(hex: 0x11141B))

        // The lure: a slow figure through looping noise so the lap closes,
        // unless the mouse has taken over.
        let t = loopProgress(over: 16)
        var lure = Vector2(width * (0.5 + signedNoise(3, loop: t, radius: 1.3) * 0.36),
                           height * (0.34 + signedNoise(9, loop: t, radius: 1.3) * 0.22))
        if mouseIsPressed { lure = Vector2(mouseX, mouseY) }

        strokeCap(.round)
        for (i, arm) in arms.enumerated() {
            arm.maxBend = stiffness
            arm.solver = whippy ? .ccd : .fabrik
            arm.reach(toward: lure)

            // Draw thick at the root, thin at the tip.
            let color = colors[i]
            for s in 0 ..< arm.lengths.count {
                let taper = 1 - Double(s) / Double(arm.lengths.count)
                stroke(color.withAlpha(0.55 + 0.45 * taper))
                strokeWeight(2 + 13 * taper * taper)
                drawLine(arm.joints[s], arm.joints[s + 1])
            }
            noStroke()
            fill(color)
            drawCircle(center: arm.tip, radius: 7)
        }

        // The lure itself.
        fill(.white)
        drawCircle(center: lure, radius: 10)
        noFill()
        stroke(Color.white.withAlpha(0.35))
        strokeWeight(2)
        drawCircle(center: lure, radius: 18)

        drawCaption(mouseIsPressed ? "the arms follow the mouse"
                                   : "press and drag to steal the lure")
    }
}
