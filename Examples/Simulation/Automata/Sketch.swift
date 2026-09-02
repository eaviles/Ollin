import Ollin

/// Eight classic **cellular automata** on one `SimField`, behind a rule picker.
/// Each rule is one entry in a table: its sim and parameters, its ramp, its
/// seeding recipe, and its parameters. Switching rules starts a fresh field with that
/// rule's classic opening. One shared brush works everywhere: drag to paint the
/// field, hold any key while dragging to erase. The rules, a line each (the `Sim`
/// catalog in `Docs/Drawing/Effects.md` carries every rule's full story):
///
///   • **life**: Conway's Game of Life, B3/S23 over a chunky grid; a random
///     soup settles into gliders and oscillators, and the brush draws cells.
///   • **brain**: Silverman's Brian's Brain; fire on exactly two, rest one
///     step, and loose soup explodes into permanent glider traffic (a solid
///     blob dies at once, so the brush sprinkles single cells).
///   • **cyclic**: Griffeath's cyclic automaton; each color eats the one
///     before it, and seeded noise self-organizes into turning spiral cores; a
///     closed hue wheel hands the top state back to state zero without a seam.
///   • **excitable**: the Greenberg-Hastings excitable medium; fire, recover,
///     rest; sparks grow rings, and a scripted half-plane wipe at frame forty
///     breaks the biggest front so its cut ends curl into a spiral pair.
///   • **hodgepodge**: the Gerhardt-Schuster machine; infection chasing
///     recovery into Belousov-Zhabotinsky spirals, `speed` (the original
///     authors' constant g) the behavior dial.
///   • **sandpile**: the Abelian sandpile; a dropped mountain collapsing four
///     grains at a time into the classic lobed figure, one color per stable
///     grain count; hold the mouse to pour a torrent somewhere else.
///   • **lenia**: Lenia, the continuous Game of Life; a mass field convolved
///     with a soft ring kernel, blobs that pulse, split, and swim, the growth
///     rule tunable live.
///   • **sand**: the falling-sand automaton; grains fall, roll off each other
///     into heaps, sink through water that spreads flat, and stop at walls; the
///     brush pours whichever material the parameter names, `friction` sets how steep
///     a heap can stand.
///
/// See `Simulation/GrayScott` for the reaction-diffusion sibling.
@main
final class Automata: Sketch {

    enum Rule: String, CaseIterable, ParamOption {
        case life, brain, cyclic, excitable, hodgepodge, sandpile, lenia, sand
    }

    /// What the brush pours in the falling-sand rule.
    enum Grain: String, CaseIterable, ParamOption {
        case sand, water, wall

        var material: SandMaterial {
            switch self {
            case .sand: return .sand
            case .water: return .water
            case .wall: return .wall
            }
        }
    }

    @Param(icon: "square.grid.3x3", group: "Rule") var rule: Rule = .life

    // Per-rule parameters, grouped under the rule they tune.
    @Param("States", 2 ... 24, icon: "circle.grid.3x3", group: "Cyclic") var hueStates = 14
    @Param("Threshold", 1 ... 4, icon: "chart.bar.fill", group: "Cyclic") var threshold = 1
    /// Count the corner neighbors too (the eight-cell block instead of the four).
    @Param("Corners", icon: "square.grid.3x3", group: "Cyclic") var corners = false
    /// The excitable cycle length: rest, firing, then the refractory tail. Longer
    /// tails make broader waves and slower, wider spirals.
    @Param("States", 3 ... 24, icon: "timer", group: "Excitable") var tail = 6
    /// The speed of infection (the hodgepodge rule's constant g).
    @Param("Speed", 1 ... 60, icon: "speedometer", group: "Hodgepodge") var speed = 25
    /// Radius of the sandpile's dropped mountain, in canvas points.
    @Param("Mountain", 4 ... 40, icon: "triangle", group: "Sandpile") var mountain = 16.0
    /// Toppling passes per frame: an avalanche front moves one cell per pass,
    /// so this is the pacing dial.
    @Param("Pace", 1 ... 128, icon: "speedometer", group: "Sandpile") var pace = 64.0
    @Param("Growth center", 0.05 ... 0.3, icon: "target", group: "Lenia") var growthCenter = 0.15
    @Param("Growth width", 0.005 ... 0.05, icon: "slider.horizontal.below.rectangle", group: "Lenia") var growthWidth = 0.015
    @Param("Pour", icon: "paintbrush.pointed", group: "Sand") var grain: Grain = .sand
    /// How often a grain that could roll off a slope stays put: 0 slumps flat,
    /// 1 stacks straight up.
    @Param("Friction", 0 ... 1, icon: "triangle", group: "Sand") var friction = 0.2

    private var field: SimField!
    private var active: Rule?
    private var fieldAge = 0

    /// Life's grid, in cells across: one texel is one chunky, visible cell.
    private let cells = 130

    /// Brian's Brain: ready is the dark ground, resting the cool afterglow,
    /// firing the white spark.
    private let glow = Ramp(stops: [(0.0, Color(hex: 0x05070C)),
                                    (0.5, Color(hex: 0x3A6BD8)),
                                    (1.0, .white)])

    /// The cyclic state ramp, closed into a wheel: the last stop repeats the first
    /// hue so the top state advancing to zero reads as one more step, not a cliff.
    private let wheel = Ramp(stops: (0 ... 6).map {
        (position: Double($0) / 6,
         color: Color(hue: Double($0) / 6, saturation: 0.72, brightness: 0.95))
    })

    /// Sandpile: one color per stable grain count, the classic way these piles are
    /// pictured. The field stores its count in quarters, so 0, 1, 2, 3 grains sit
    /// at exactly 0, ¼, ½, ¾ and the top catches cells flashing mid-topple.
    private let counts = Ramp(stops: [(0.00, Color(hex: 0x10141F)),
                                      (0.25, Color(hex: 0x2C6E91)),
                                      (0.50, Color(hex: 0xE3A857)),
                                      (0.75, Color(hex: 0xF2E9DC)),
                                      (1.00, .white)])

    /// Falling sand: one tone per material, at the thirds the field stores them
    /// on (empty, water, sand, wall).
    private let materials = Ramp(stops: [(0.000, Color(hex: 0x14161C)),
                                         (1 / 3, Color(hex: 0x2E7BC4)),
                                         (2 / 3, Color(hex: 0xD9B36C)),
                                         (1.000, Color(hex: 0x6B6B70))])

    override func setup() {
        restart(with: rule)
    }

    override func draw() {
        background(.black)
        if rule != active { restart(with: rule) }   // a rule switch starts fresh
        field.sim = sim(for: rule)                  // the parameters retune the rule live
        fieldAge += 1

        withField(field) {
            noStroke()
            seedIfDue()
            if mouseIsPressed { paint() }
        }
        drawImage(recolored(), 0, 0)
        drawCaption(caption())
    }

    /// A fresh field for `rule`: new ping-pong state, age zero, so the rule's
    /// seeding recipe replays from its opening frame.
    private func restart(with rule: Rule) {
        field = makeSimField(sim(for: rule), scale: fieldScale(for: rule))
        active = rule
        fieldAge = 0
    }

    /// The table's sim column: each rule's `Sim` case under its parameters.
    private func sim(for rule: Rule) -> Sim {
        switch rule {
        case .life: return .gameOfLife()
        case .brain: return .briansBrain()
        case .cyclic: return .cyclic(states: hueStates, threshold: threshold,
                                     neighborhood: corners ? .moore : .vonNeumann,
                                     seed: Double(variation))
        case .excitable: return .excitable(states: tail)
        case .hodgepodge: return .hodgepodge(infectionRate: speed, seed: Double(variation))
        case .sandpile: return .sandpile(pour: 1024, topplings: Int(pace))
        case .lenia: return .lenia(growthCenter: growthCenter, growthWidth: growthWidth)
        case .sand: return .fallingSand(passes: 16, friction: friction)
        }
    }

    /// Field resolution per rule: coarse where one texel should read as a cell,
    /// finer for the smooth fields.
    private func fieldScale(for rule: Rule) -> Double {
        switch rule {
        case .life: return Double(cells) / width
        case .brain: return 0.15
        case .cyclic, .excitable, .hodgepodge: return 0.25
        case .sandpile, .lenia, .sand: return 0.5
        }
    }

    /// The table's seeding column, run inside the paint block: each rule's classic
    /// opening at the age it calls for. Cyclic and hodgepodge need nothing (they
    /// start from seeded random states picked by `variation`).
    private func seedIfDue() {
        switch rule {
        case .life where fieldAge == 1:
            // A random soup to get life going, cell-aligned so one mark is one cell.
            fill(.white)
            let cw = width / Double(cells)
            for _ in 0 ..< 7000 {
                let gx = Double(Int(random(Double(cells)))), gy = Double(Int(random(Double(cells))))
                drawRect(gx * cw, gy * cw, cw, cw)
            }
        case .brain where fieldAge == 1:   // the classic start: soup everywhere
            fill(.white)
            for _ in 0 ..< 6500 {
                drawCircle(random(width), random(height), 3.4)
            }
        case .excitable where fieldAge == 1:
            // A line whose front the wipe will break, and a few loose sparks.
            fill(.white)
            drawRect(width * 0.25, height * 0.55, width * 0.5, 6)
            for _ in 0 ..< 10 {
                drawCircle(random(width), random(height), 4)
            }
        case .excitable where fieldAge == 40:
            // The classic spiral recipe: wipe half the plane, and the broken
            // front's two free ends curl into counter-rotating spirals.
            fill(.black)
            drawRect(0, 0, width, height * 0.52)
        case .sandpile where fieldAge == 1:   // the opening mountain
            fill(.white)
            drawCircle(width / 2, height / 2, mountain)
        case .lenia where fieldAge == 1:
            // A dense primordial soup, reproducible per variation.
            for _ in 0 ..< 350 {
                fill(Color(white: 1, alpha: random(0.2, 0.8)))
                drawCircle(random(width), random(height), random(15, 70))
            }
        case .sand where fieldAge == 1:
            // Two shelves and a pool: the stream piles on the upper shelf,
            // slumps off it, and what reaches the pool sinks to its floor.
            fill(SandMaterial.wall.color)
            drawRect(width * 0.12, height * 0.45, width * 0.36, 8)
            drawRect(width * 0.36, height * 0.68, width * 0.28, 8)
            fill(SandMaterial.water.color)
            drawRect(width * 0.55, height * 0.8, width * 0.45, height * 0.2)
        case .sand where fieldAge <= 300:
            // A stream of loose grains from one tap for the first seconds.
            fill(SandMaterial.sand.color)
            drawCircle(width * 0.27 + random(-12, 12), 10, 2)
        default:
            break
        }
    }

    /// The shared brush: the mouse paints each rule's ink, a held key erases.
    private func paint() {
        switch rule {
        case .life:
            // Cell-aligned, so the brush lands on whole cells.
            fill(keyIsPressed ? .black : .white)
            let cw = width / Double(cells)
            let gx = Double(Int(mouseX / cw)), gy = Double(Int(mouseY / cw))
            drawRect((gx - 1) * cw, (gy - 1) * cw, cw * 3, cw * 3)
        case .brain:
            // A solid blob dies at once, so the brush sprinkles loose cells.
            if keyIsPressed {
                fill(.black)
                drawCircle(mouseX, mouseY, 80)
            } else {
                sprinkle(mouseX, mouseY, radius: 60)
            }
        case .cyclic:
            // White stamps the top state (the wheel spins it back in), black
            // stamps state zero; either way the spirals eat the wound.
            fill(keyIsPressed ? .black : .white)
            drawCircle(mouseX, mouseY, 60)
        case .excitable:
            // A small dab sparks a ring; a broad black brush calms the medium.
            fill(keyIsPressed ? .black : .white)
            drawCircle(mouseX, mouseY, keyIsPressed ? 60 : 8)
        case .hodgepodge:
            // Mid-gray stamps a degree of infection; black heals.
            fill(keyIsPressed ? .black : Color(white: 0.6))
            drawCircle(mouseX, mouseY, 60)
        case .sandpile:
            // Sand cannot be unpoured (a dark mark adds no grains), so the held
            // key simply holds the torrent.
            if !keyIsPressed {
                fill(.white)
                drawCircle(mouseX, mouseY, mountain)
            }
        case .lenia:
            fill(keyIsPressed ? .black : Color(white: 1, alpha: 0.85))
            drawCircle(mouseX, mouseY, 42)
        case .sand:
            // The brush pours the chosen material; a held key clears a hole
            // (an empty mark is a material too, so it also cuts through walls).
            fill(keyIsPressed ? SandMaterial.empty.color : grain.material.color)
            drawCircle(mouseX, mouseY, grain == .wall ? 12 : 24)
        }
    }

    /// A pinch of random soup: loose single cells at the density that boils. One
    /// dot is one field cell, so the dot radius follows the field's scale.
    private func sprinkle(_ x: Double, _ y: Double, radius: Double = 150) {
        fill(.white)
        for _ in 0 ..< Int(radius * radius * 0.018) {   // constant soup density
            let angle = random(.pi * 2)
            let r = radius * random().squareRoot()
            drawCircle(x + cos(angle) * r, y + sin(angle) * r, 3.4)
        }
    }

    /// The table's ramp column: Life's raw state is already the classic crisp
    /// black-and-white; every other rule recolors through a gradient map.
    private func recolored() -> Image {
        switch rule {
        case .life: return field.image
        case .brain: return field.filtered(.gradientMap(glow)).image
        case .cyclic: return field.filtered(.gradientMap(wheel)).image
        case .excitable: return field.filtered(.gradientMap(.inferno)).image
        case .hodgepodge: return field.filtered(.gradientMap(.turbo)).image
        case .sandpile: return field.filtered(.gradientMap(counts)).image
        case .lenia: return field.filtered(.gradientMap(.magma)).image
        case .sand: return field.filtered(.gradientMap(materials)).image
        }
    }

    private func caption() -> String {
        switch rule {
        case .life:
            return "Game of Life · drag to draw cells, hold a key to erase"
        case .brain:
            return "Brian's Brain · fire on exactly two · drag to sprinkle, hold a key to clear"
        case .cyclic:
            return "cyclic automaton · each color eats the one before it · drag to stamp"
        case .excitable:
            return "excitable medium · fire, recover, rest · dab to spark, hold a key to calm"
        case .hodgepodge:
            return "hodgepodge machine · infection chasing recovery · drag to infect, hold a key to heal"
        case .sandpile:
            return "Abelian sandpile · four grains at a time · hold to pour another mountain"
        case .lenia:
            return "Lenia · a continuous automaton · drag to add mass, hold a key to erase"
        case .sand:
            return "falling sand · grains fall, roll, and sink through water · drag to pour, hold a key to erase"
        }
    }
}
