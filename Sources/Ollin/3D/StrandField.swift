import Foundation

/// A patch of grass-like blades the GPU grows in the draw itself.
///
/// `drawStrands(_:)` renders about `count` blades over a `width` x `depth`
/// ground patch with NO geometry anywhere: no vertex buffer, no instance list,
/// nothing to build or upload. A mesh pipeline synthesizes every blade inside
/// the draw call, from hashes of its index: where it roots, how tall it grows,
/// which way it leans, how it sways on the sketch clock, and how its color
/// runs from `lowColor` at the root to `tipColor` at the tip. The camera
/// drives the work: tiles outside the view are skipped whole, and distant
/// tiles emit blades with fewer segments, which is the kind of per-blade
/// geometry change no instanced draw can express.
///
/// ```swift
/// var lawn = StrandField(width: 30, depth: 30, count: 400_000)
/// lawn.tipColor = Color(hue: 0.28, saturation: 0.5, brightness: 0.8)
///
/// override func draw() {
///     camera(...)
///     directionalLight(...)
///     drawStrands(lawn)          // the whole meadow, grown in-draw
/// }
/// ```
///
/// Blades shade through the solid lit path (lights, shadows received,
/// image-based lighting, fog) with the current `material(_:)` finish, and the
/// patch rides the 3D transform stack. Because the geometry exists only inside
/// the draw, strands never cast into the shadow maps and cannot be exported
/// spatially; they are surface dressing, not solids.
public struct StrandField: Sendable {

    /// Patch extent along x, world units (centered on the origin).
    public var width: Double
    /// Patch extent along z, world units.
    public var depth: Double
    /// Approximate blade count (the tile grid rounds it; read `bladeCount` for
    /// the exact number drawn).
    public var count: Int

    /// A blade's height, world units, before variance.
    public var bladeHeight: Double = 1
    /// How much heights vary, 0 (uniform) ... 1 (0 to double the height).
    public var heightVariance: Double = 0.35
    /// A blade's width at the root, world units.
    public var bladeWidth: Double = 0.06
    /// How far a blade's tip leans from vertical, world units.
    public var lean: Double = 0.3

    /// How far the sway carries a tip, world units (0 = still).
    public var swayAmount: Double = 0.12
    /// Sway speed, radians per second on the sketch clock.
    public var swayFrequency: Double = 1.6
    /// Color at the blade root (straight sRGB, like a vertex color).
    public var lowColor = Color(hue: 0.3, saturation: 0.55, brightness: 0.25)
    /// Color at the tip.
    public var tipColor = Color(hue: 0.26, saturation: 0.5, brightness: 0.62)
    /// Seeds the per-blade hashes, so two fields can differ.
    public var seed: Double = 0

    /// Camera distance at which blades still get full detail.
    public var detailNear: Double = 12
    /// Camera distance by which blades are down to their simplest form.
    public var detailFar: Double = 45

    /// Skip tiles outside the camera's view (the default). The A/B switch:
    /// turning it off draws every tile and must not change the picture.
    public var cullingEnabled = true
    /// Reduce distant blades' segment counts (the default). Turning it off
    /// gives every blade full detail everywhere, the honest way to measure
    /// what the adaptive detail saves.
    public var levelOfDetailEnabled = true

    /// A patch of about `count` blades over `width` x `depth` world units.
    public init(width: Double, depth: Double, count: Int) {
        self.width = width
        self.depth = depth
        self.count = max(1, count)
    }

    /// Blades per tile: one mesh-stage bundle of GPU threads handles 24, so a
    /// tile is a few bundles.
    static let bladesPerTile = 96

    /// The derived tile grid: tiles sized so each holds ~`bladesPerTile`.
    var tiling: (tilesX: Int, tilesZ: Int, tileEdge: Double) {
        let area = max(width * depth, 0.0001)
        let edge = (area * Double(StrandField.bladesPerTile) / Double(count)).squareRoot()
        let tx = max(1, Int((width / edge).rounded(.up)))
        let tz = max(1, Int((depth / edge).rounded(.up)))
        return (tx, tz, edge)
    }

    /// The exact number of blades drawn (the tile grid times its per-tile count).
    public var bladeCount: Int {
        let t = tiling
        return t.tilesX * t.tilesZ * StrandField.bladesPerTile
    }
}
