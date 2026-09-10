import Ollin
import OllinSamplePhotos
import OllinVision

//  Inspired by Zach Lieberman's reaction-diffusion daily sketches (2026).
//  Original interpretation of the technique; no source code ported.

/// A mirror that grows Turing patterns on you: the feed's person matte drives a
/// reaction-diffusion field's **modulation layer**, so the chemistry runs in the
/// maze/coral regime wherever you stand and the spot regime everywhere else. It is
/// one continuous simulation wearing both patterns, so the boundary between them is
/// chemistry, not a mask: as you move, the field reorganizes live around your
/// silhouette and the pattern flows across the edge instead of seaming at it.
///
/// The regime map is a plain drawn layer (a black canvas with the matte in white),
/// so anything a sketch can draw can steer the chemistry the same way; see
/// `.reactionDiffusion(feed:kill:toFeed:toKill:)` and `SimField.modulation`.
@main
final class TuringMirror: Sketch {
    // A mirror needs a person in front of it, so with no feed it wears the bundled dancer.
    let feed = Camera.orStill(SamplePhoto.dancer.load())
    lazy var people = PersonSegmenter(feed)
    private var rd: SimField!
    private var mask: RenderTarget!
    private var seeded = false
    // The raw field's luminance sits in a narrow band (the substrate around 0.21,
    // the pattern up to roughly 0.4), so the ramp packs its color travel into that
    // band: substrate near-black, pattern glowing blue through cyan to yellow-pink.
    private let look = Ramp(stops: [(0.00, Color(hex: 0x08060F)),
                                    (0.20, Color(hex: 0x140F33)),
                                    (0.26, Color(hex: 0x2C4BD8)),
                                    (0.32, Color(hex: 0x2BC8C4)),
                                    (0.38, Color(hex: 0xF2D53C)),
                                    (0.50, Color(hex: 0xFF5EA0)),
                                    (1.00, Color(hex: 0xFFF6EC))], in: .oklch)

    override func setup() {
        // The map's black end is the spot regime, its white end the worm maze; both
        // are living regimes, so the background stays patterned while your
        // silhouette wears a different texture.
        rd = makeSimField(.reactionDiffusion(feed: 0.046, kill: 0.065,
                                         toFeed: 0.055, toKill: 0.062))
        mask = makeRenderTarget()
        rd.modulation = mask
    }

    override func draw() {
        background(.black)

        // The regime map, redrawn each frame: your matte in white over black. Layers
        // are per-frame, so an undrawn map would fall back to the uniform field.
        withTarget(mask) {
            background(.black)
            if let matte = people.matte, let size = feed.frameSize {
                drawImage(matte, in: Rectangle(covering: size, in: bounds))
            }
        }

        withField(rd) {
            if !seeded {        // sow chemical B once; the two regimes take it from there
                noStroke(); fill(.white)
                for _ in 0 ..< 120 { drawCircle(random(width), random(height), 6) }
                seeded = true
            }
        }
        drawImage(rd.filtered(.gradientMap(look)).image, 0, 0)

        if feed.frame == nil {
            drawStatus(feed.waitingMessage)
        } else if let reason = people.unavailableReason {
            drawStatus(reason, style: .warning)
        }
        drawCaption("TuringMirror · your silhouette picks the reaction-diffusion regime")
    }
}
