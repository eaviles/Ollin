import Ollin

/// The toy gear set as geometry: a wheel gear rolls inside a fixed ring with a
/// pen partway out from its center, and `hypotrochoid` bakes the whole path
/// (the curve only closes after enough laps to line the gear teeth up again).
/// Here one gear pair is stacked at several pen distances into a nested
/// rosette, drawn additively so the layers glow where they cross. The pen
/// slides in and out over the loop, so the lobes round, cusp, and knot; the
/// slow spin advances exactly one lobe per lap, which is what makes the loop
/// seamless. Change the gears and the whole rosette re-weaves.
@main
final class Spirograph: Sketch {
    @Param(24 ... 96, icon: "circle") var ring = 84.0
    @Param(7 ... 60, icon: "circle.dashed") var wheel = 33.0
    @Param(3 ... 16, icon: "square.stack") var layers = 9.0

    let period = 12.0
    override var loopDuration: Double? { period }

    override func draw() {
        background(Color(hex: 0x0D1017))
        noFill()
        blendMode(.add)
        strokeWeight(1.4 * scale)

        let r = Int(ring)
        let w = min(Int(wheel), r - 1)
        let count = max(3, Int(layers))
        let breathe = 0.55 + 0.8 * pingPong(over: period)

        // The pen's furthest reach at full breathe, so the nest always fits.
        let reach = Double(r - w) + Double(w) * 1.35
        let fit = shortSide * 0.47 / reach

        // The rosette repeats every ring/gcd lobes, so advancing one lobe
        // per loop lands back on itself.
        let lobes = r / greatestCommonDivisor(r, w)

        let a = Color(hex: 0x37C8AD)
        let b = Color(hex: 0xE84E7A)

        withState {
            translate(center)
            scale(fit)
            rotate(loopProgress(over: period) * .tau / Double(max(1, lobes)))
            for i in 0..<count {
                let t = Double(i) / Double(max(1, count - 1))
                let pen = Double(w) * map(t, 0, 1, 0.2, 1.0) * breathe
                stroke(Color.mix(a, b, t).withAlpha(0.55))
                drawPolyline(hypotrochoid(ring: r, wheel: w, pen: pen).points,
                             closed: true)
            }
        }
    }

    private func greatestCommonDivisor(_ a: Int, _ b: Int) -> Int {
        var a = a
        var b = b
        while b != 0 { (a, b) = (b, a % b) }
        return max(1, a)
    }
}
