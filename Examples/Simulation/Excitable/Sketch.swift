import Ollin

/// The Greenberg-Hastings model of an **excitable medium**, the cellular automaton
/// behind heart tissue, neurons, and chemical oscillators. A resting cell fires
/// when a neighbor is firing, then climbs alone through a refractory tail back to
/// rest, and mid-recovery it cannot be re-lit, which is exactly what turns a spark
/// into a traveling ring with a dead zone behind it. The sketch scripts the classic
/// demonstration: sparks grow into rings, rings annihilate where they collide, and
/// at frame forty a black wipe breaks the biggest front in half so its cut ends
/// curl into a pair of counter-rotating spirals that re-excite the field forever.
/// Dab to spark more rings; hold a key and drag to calm the medium back to rest.
@main
final class Excitable: Sketch {

    /// The cycle length: rest, firing, then the refractory tail. Longer tails make
    /// broader waves and slower, wider spirals.
    @Param(3 ... 24, icon: "timer", group: "Rule") var states = 6

    private var field: SimField!

    override func setup() {
        field = simField(.excitable(states: states), scale: 0.25)
    }

    override func draw() {
        background(.black)
        field.sim = .excitable(states: states)

        withField(field) {
            noStroke()
            if frameCount == 1 {
                // A line whose front the wipe will break, and a few loose sparks.
                fill(.white)
                drawRect(width * 0.25, height * 0.55, width * 0.5, 6)
                for _ in 0 ..< 10 {
                    drawCircle(random(width), random(height), 4)
                }
            }
            if frameCount == 40 {
                // The classic spiral recipe: wipe half the plane, and the broken
                // front's two free ends curl into counter-rotating spirals.
                fill(.black)
                drawRect(0, 0, width, height * 0.52)
            }
            if mouseIsPressed {
                fill(keyIsPressed ? .black : .white)
                drawCircle(mouseX, mouseY, keyIsPressed ? 60 : 8)
            }
        }
        drawImage(field.filtered(.gradientMap(.inferno)).image, 0, 0)
        drawCaption("Excitable medium · fire, recover, rest · dab to spark, hold a key to calm")
    }
}
