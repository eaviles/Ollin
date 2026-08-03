import Ollin

/// Soap bubbles: thin glass with a living, swirling film.
///
/// A real bubble is two materials at once. It's a *thin wall of glass*
/// (`Material.glass()`, thickness `0`), so the world passes through it almost
/// straight, and it's a *film whose thickness drains and swirls*, so interference
/// colors marble across the surface and drift while you watch. The first half is
/// transmission; the second is the iridescence finish in soap-film mode:
///
/// ```swift
/// var film = Material.glass()          // a thin see-through shell
/// film.iridescence = 0.8               // the interference sheen
/// film.iridescenceFlow = 1.0           // film-thickness swirl (the bubble look)
/// film.iridescencePhase = time * 0.35  // you drive the clock, so exports reproduce
/// material(film)
/// ```
///
/// A handful of bubbles rise, wobble, and pop back in at the bottom, each with its
/// own film phase. The camera drifts on its own; drag to look around. (The bubbles
/// refract the environment rather than the traced scene: a thin film passes light
/// through nearly straight, so for free-floating bubbles the environment is the
/// whole story, and overlapping bubbles stay clear instead of hitting the
/// glass-through-glass envelope.)
@main
final class SoapBubble: Sketch {

    struct Bubble {
        var x, z, y0: Double     // column position + vertical seed
        var radius: Double
        var speed: Double        // rise, world units per second
        var wobble: Double       // wobble phase offset
        var film: Double         // film-swirl phase offset
    }
    var bubbles: [Bubble] = []

    override func setup() {
        for _ in 0..<7 {
            bubbles.append(Bubble(x: random(-2.6, 2.6), z: random(-1.6, 1.6),
                                  y0: random(0, 6), radius: random(0.35, 0.95),
                                  speed: random(0.25, 0.5), wobble: random(0, .tau),
                                  film: random(0, 40)))
        }
    }

    override func draw() {
        background(Color(hex: 0x14171d))
        cameraShowcase(.sway(amplitude: 0.3, period: .tau / 0.07),
                       target: Vector3(0, 1.2, 0), radius: 9, elevation: 0.1,
                       fieldOfView: .pi / 4, near: 1, far: 40)
        environment(.courtyard.intensity(1.05))
        directionalLight(.white, direction: Vector3(-0.4, -1, -0.25), intensity: 0.5)

        for b in bubbles {
            // Rise and wrap: a popped bubble is reborn at the bottom of the column.
            let span = 6.0
            let y = (b.y0 + time * b.speed).truncatingRemainder(dividingBy: span) - 1.4
            // A gentle volume-preserving wobble, the slow breathing of a free bubble.
            let w = sin(time * 2.1 + b.wobble) * 0.05

            var film = Material.glass()
            film.iridescence = 0.8
            film.iridescenceScale = 1.3
            film.iridescenceFlow = 1.0
            film.iridescencePhase = time * 0.35 + b.film
            film.iridescenceFlowSize = 0.45  // fine wisps on small, distant bubbles
            withState {
                material(film)
                fill(.white)
                translate(b.x + sin(time * 0.6 + b.wobble) * 0.15, y, b.z)
                scale(1 + w, 1 - w, 1 + w * 0.4)
                drawSphere(radius: b.radius)
            }
        }

        drawCaption("Thin glass + iridescenceFlow: the film drains and swirls")
    }
}
