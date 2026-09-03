import Ollin
import Foundation

// The three fractal leaves of the raymarched field: the Mandelbulb, the Menger sponge, and
// the Mandelbox. None has a closed-form distance; each one estimates it by iterating its own
// map, and the same sphere tracer that draws a melted sphere draws them. Pick one from the
// menu, then turn its own dial: the bulb's power (a fractional power is a different picture,
// and sweeping it is the classic breathing animation), the sponge's depth, the box's scale.
// `iterations` is detail against cost, since every march step runs the loop. The camera
// orbits slowly so the relief keeps catching the light.
@main
final class RaymarchedFractals: Sketch {
    enum Fractal: CaseIterable, ParamOption {
        case mandelbulb, mengerSponge, mandelbox
    }

    @Param(group: "Fractal") var fractal: Fractal = .mandelbulb
    @Param(1...16, group: "Fractal") var iterations = 8
    @Param(2...16, group: "Mandelbulb") var power = 8.0
    @Param(group: "Mandelbulb") var breathe = false
    @Param(-3.0...3.0, group: "Mandelbox") var boxScale = -1.5

    override func draw() {
        background(Color(hex: 0x0f1014))
        let t = time

        camera(.orbiting(target: .zero, radius: 5.4, azimuth: t * 0.12,
                         elevation: 0.32, fieldOfView: .pi / 4.5, near: 0.1, far: 30))
        directionalLight(.white, direction: Vector3(-0.45, -0.8, -0.4),
                         intensity: 1.2, softness: 0.25)
        ambientLight(Color(white: 0.16))
        material(.clay)

        let field: SDF3D
        switch fractal {
        case .mandelbulb:
            // The breathing bulb sweeps its power through the family; 8 is the classic.
            let n = breathe ? 8 + 4 * sin(t * 0.35) : power
            field = SDF3D.mandelbulb(power: n, iterations: iterations, radius: 1.35)
                .colored(Color(hex: 0xff6b6b))
        case .mengerSponge:
            // Past level 5 the holes drop below a pixel at this framing; the dial caps there.
            field = SDF3D.mengerSponge(iterations: min(iterations, 5), size: 2.4)
                .colored(Color(hex: 0xffd166))
        case .mandelbox:
            field = SDF3D.mandelbox(scale: boxScale, iterations: iterations, size: 2.4)
                .colored(Color(hex: 0x4ea8ff))
        }
        drawSDF3D(field.rotatedY(t * 0.05))
    }
}
