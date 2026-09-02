import Ollin

/// Every built-in `ChaoticMap` preset, drawn as an accumulating density field:
/// pick one on the parameter and each frame iterates the map another 60k steps,
/// adding them as faint additive dots onto a canvas that never clears. Where
/// the orbit returns again and again the dots pile into bright filaments; the
/// sparse outskirts stay dim, so the structure paints itself in over a few
/// seconds. `blendMode(.add)` over `noClear()` is the sandpainting build-up
/// the float pipeline is made for; switching presets wipes the canvas and
/// starts the new accumulation fresh.
///
/// Two behaviors, chosen per preset. Most of the maps are dissipative, so one
/// long orbit carried across frames (`current` persists) settles onto the
/// attractor and keeps thickening it: `clifford` and `deJong` are the
/// trigonometric webs (`x' = sin(a·y) + c·cos(a·x)`, `y' = sin(b·x) +
/// d·cos(b·y)` and its cousin, within roughly ±2), `henon` folds a thin
/// boomerang curve, `ikeda` swirls light around a ring cavity, and `hopalong`
/// hops square-root rings that keep widening as it runs. `gumowskiMira`, the
/// particle-beam recurrence `x' = y + a·(1 - b·y²)·y + G(x)`, `y' = G(x') - x`,
/// is instead nearly area-preserving with a whisper of damping: any one orbit
/// slowly decays onto a few islands, and the classic plates superimpose many,
/// so that preset reseeds a fresh orbit from a random point in the sea every
/// frame and the layered transients fill in the many-petaled filigree.
/// Seeded, so the piece reproduces.
@main
final class ChaoticMaps: Sketch {

    enum Preset: String, CaseIterable, ParamOption {
        case clifford, deJong, henon, gumowskiMira, ikeda, hopalong
    }

    @Param(icon: "scribble") var preset: Preset = .clifford

    private let perFrame = 60_000
    private var showing: Preset?
    private var chaos = ChaoticMap.clifford()
    private var current = Vector2(0.1, 0.1)

    override func setup() {
        noClear()                         // pile onto a persistent canvas
        noStroke()
    }

    override func draw() {
        // A preset change (and the first frame) wipes the accumulation and
        // starts the new map from its own start point.
        if showing != preset {
            showing = preset
            seed(7)
            background(.black)
            chaos = chaoticMap(for: preset)
            current = chaos.start
        }

        let (center, reachShare) = window(for: preset)
        let reach = shortSide * reachShare
        let mid = Vector2(width / 2, height / 2)

        // The per-preset behavioral choice: gumowskiMira layers a fresh orbit
        // each frame (the transient is the picture); every other preset
        // carries one continuous orbit forward.
        if preset == .gumowskiMira {
            current = Vector2(random(-3, 3), random(-3, 3))
        }

        var points = [Vector2]()
        points.reserveCapacity(perFrame)
        for _ in 0..<perFrame {
            current = chaos.next(current)
            points.append(mid + (current - center) * reach)
        }

        blendMode(.add)
        fill(ink(for: preset))
        pointSize(1.0 * scale)
        drawPoints(points)
    }

    private func chaoticMap(for preset: Preset) -> ChaoticMap {
        switch preset {
        case .clifford:     return .clifford()
        case .deJong:       return .deJong()
        case .henon:        return .henon()
        case .gumowskiMira: return .gumowskiMira()
        case .ikeda:        return .ikeda()
        case .hopalong:     return .hopalong()
        }
    }

    /// Each map lives in its own patch of the plane, so each preset frames its
    /// own window: the map-space point that lands at the canvas center, and
    /// the reach (canvas share per map unit) that scales the orbit to fit.
    private func window(for preset: Preset) -> (center: Vector2, reachShare: Double) {
        switch preset {
        case .clifford:     return (Vector2(0, 0), 0.22)        // within roughly ±2
        case .deJong:       return (Vector2(0, 0), 0.22)        // within roughly ±2
        case .henon:        return (Vector2(0, 0), 0.30)        // a thin curve near the axis
        case .gumowskiMira: return (Vector2(0, 0), 0.052)       // roughly [-9, 9] x [-6, 6]
        case .ikeda:        return (Vector2(0.65, -0.65), 0.26) // roughly [-0.4, 1.7] x [-2.2, 0.9]
        case .hopalong:     return (Vector2(0, 0), 0.011)       // rings widen as the orbit runs
        }
    }

    private func ink(for preset: Preset) -> Color {
        switch preset {
        case .clifford:
            return Color(red: 0.42, green: 0.74, blue: 1.0, alpha: 0.05)
        case .deJong:
            return Color(red: 0.55, green: 1.0, blue: 0.75, alpha: 0.05)
        case .henon:
            return Color(red: 1.0, green: 0.85, blue: 0.40, alpha: 0.035)
        case .gumowskiMira:
            // The hue leans between ember and violet from orbit to orbit, so
            // the layers read as depth.
            let ember = Color(red: 1.0, green: 0.62, blue: 0.30, alpha: 0.045)
            let violet = Color(red: 0.62, green: 0.44, blue: 1.0, alpha: 0.045)
            return Color.mix(ember, violet, random(0, 1))
        case .ikeda:
            return Color(red: 0.95, green: 0.50, blue: 0.55, alpha: 0.05)
        case .hopalong:
            return Color(red: 0.70, green: 0.90, blue: 0.50, alpha: 0.05)
        }
    }
}
