// figure: frame=420
//
// Guide diagram (Chapter 17): the excitable-media automata, four panels. Top
// left, Griffeath's cyclic automaton self-organized from noise into turning
// spirals under a closed hue wheel. Top right, a Greenberg-Hastings medium:
// scripted sparks grown into rings, half the plane wiped so the broken front
// curls into a spiral pair. Bottom left, Brian's Brain boiling from a seeded
// soup, white fire over its cool afterglow. Bottom right, the hodgepodge
// machine's infection waves on the classic constants, mapped with turbo. Each
// panel is its own SimField; every pattern emerges, none is drawn.
import Ollin

final class ExcitableFamilyFigure: Sketch {
    override var canvasSize: CanvasSize { .square(560) }

    private var cyclic: SimField!
    private var medium: SimField!
    private var brain: SimField!
    private var hodgepodge: SimField!

    private let wheel = Ramp(stops: (0 ... 6).map {
        (position: Double($0) / 6,
         color: Color(hue: Double($0) / 6, saturation: 0.72, brightness: 0.95))
    })
    private let glow = Ramp(stops: [(0.0, Color(hex: 0x05070C)),
                                    (0.5, Color(hex: 0x3A6BD8)),
                                    (1.0, .white)])

    override func setup() {
        cyclic = simField(.cyclic(seed: 4), scale: 0.25)
        medium = simField(.excitable(states: 5), scale: 0.25)
        brain = simField(.briansBrain(), scale: 0.25)
        hodgepodge = simField(.hodgepodge(seed: 4), scale: 0.25)
        randomSeed(7)
    }

    override func draw() {
        background(.black)

        withField(medium) {
            noStroke()
            if frameCount == 1 {          // a line and four sparks
                fill(.white)
                drawRect(140, 300, 280, 6)
                for p in [(90.0, 90.0), (430.0, 120.0), (120.0, 460.0), (460.0, 440.0)] {
                    drawCircle(p.0, p.1, 6)
                }
            }
            if frameCount == 30 {         // the wipe that makes the spiral pair
                fill(.black)
                drawRect(0, 0, 560, 288)
            }
        }
        withField(brain) {
            noStroke()
            if frameCount == 1 {          // the classic start: soup everywhere
                fill(.white)
                for _ in 0 ..< 3000 {
                    drawCircle(random(width), random(height), 2.2)
                }
            }
        }

        drawImage(cyclic.filtered(.gradientMap(wheel)).image, 0, 0, 278, 278)
        drawImage(medium.filtered(.gradientMap(.inferno)).image, 282, 0, 278, 278)
        drawImage(brain.filtered(.gradientMap(glow)).image, 0, 282, 278, 278)
        drawImage(hodgepodge.filtered(.gradientMap(.turbo)).image, 282, 282, 278, 278)
    }
}
