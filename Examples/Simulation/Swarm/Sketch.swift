import Ollin

/// Steering at scale: 30,000 creatures, each deciding where to go from the same short
/// list of urges, all of it worked out on the GPU. Every behavior is a weight, and the
/// weighted forces are added up and capped before an agent moves, so a swarm is a flock
/// or a crowd or a drifting cloud depending only on which numbers are turned up.
///
/// Move the mouse to give them somewhere to be. Hold the button and they chase it;
/// press `f` and they run from it instead. Press `space` to cycle the three moods:
/// **flock** (the classic three rules), **current** (a flow field carries them), and
/// **roam** (each one wanders on its own).
@main
final class Swarm_Example: Sketch {
    var flock: Swarm!
    var mood = 0
    var fleeing = false

    @Param(0 ... 3, icon: "arrow.left.and.right") var separation = 1.5
    @Param(0 ... 3, icon: "arrow.right") var alignment = 1.5
    @Param(0 ... 3, icon: "circle.dotted") var cohesion = 0.8
    @Param(60 ... 300, icon: "speedometer") var topSpeed = 220.0

    let moods = ["flock", "current", "roam"]
    let palette = [Color(hue: 0.55, saturation: 0.7, brightness: 0.5),
                   Color(hue: 0.62, saturation: 0.6, brightness: 0.45),
                   Color(hue: 0.48, saturation: 0.6, brightness: 0.42)]

    override func setup() {
        background(.black)
        noClear()
        // These numbers are tied to each other. An agent wants to see roughly twenty
        // others, which sets the perception radius against how densely the canvas is
        // filled, and it has to take several frames to cross that radius, or it
        // outruns the neighbors it is supposed to be reacting to.
        flock = swarm(count: 30_000, perceptionRadius: 16, colors: palette, size: 1.5)
        flock.separationRadius = 5.5
        flock.maxForce = 800           // a wide enough turn to travel, not orbit
        flock.minSpeed = 45            // keeps a crowded swarm flowing instead of jamming
        applyMood()
    }

    override func draw() {
        // A translucent sheet over the accumulated canvas, so every agent leaves a
        // fading trail and the shape of the movement shows rather than just where
        // everyone happens to be this frame. (`background` would wipe the canvas
        // outright, however little alpha its color carried.)
        blendMode(.normal)
        noStroke()
        fill(Color(white: 0.02, alpha: 0.16))
        drawRect(0, 0, width, height)
        blendMode(.add)

        flock.maxSpeed = topSpeed
        flock.separation = separation
        flock.alignment = mood == 0 ? alignment : 0
        flock.cohesion = mood == 0 ? cohesion : 0

        flock.target = mouse
        flock.seek = mouseIsPressed && !fleeing ? 1.8 : 0
        flock.flee = mouseIsPressed && fleeing ? 2.4 : 0

        updateSwarm(flock)
        drawParticles(flock)

        blendMode(.normal)
        drawCaption("Swarm · 30,000 agents · \(moods[mood]) · "
            + "space changes mood, f flips chase/flee, drag to lead them")
    }

    override func keyPressed() {
        if key == " " { mood = (mood + 1) % moods.count; applyMood() }
        if key == "f" { fleeing.toggle() }
    }

    /// The three moods differ only in which urges are switched on.
    private func applyMood() {
        flock.wander = 0
        flock.flow = 0
        switch mood {
        case 1:  flock.flow = 1.4              // a current runs through the whole field
        case 2:  flock.wander = 1.0            // everyone roams on their own
        default: break                         // flocking, set per frame from the knobs
        }
    }
}
