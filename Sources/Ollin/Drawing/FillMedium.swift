import Foundation
import simd
import COllinShaders

/// What a fill is made of: thick paint that rises along its edge and is lit as a
/// surface, paint laid with a knife, a wash of pigment in water, chrome, glass,
/// faceted glass, rock, marble, or sand. Set it with `fillMedium(_:)` beside
/// `fill`:
///
/// ```swift
/// fill(Color(hex: 0xC8553D))
/// fillMedium(.impasto)
/// drawShape(blob)
/// ```
///
/// A medium shades the fill per pixel from how far the pixel is from the fill's
/// own edge and which way that edge lies, so the paint can rise along the
/// outline and level off inside, and a pane of glass can bend what is under its
/// rim while its middle shows it straight. The fill's color is the pigment (the
/// tint, for the metal and the glasses) and its alpha the opacity. Textures sit
/// in the shape's own coordinates, so a shape moved by `translate` or `rotate`
/// carries its paint with it.
///
/// The wash, the gouache, chrome, and both glasses read what is already drawn
/// under them: the frame without the fills and strokes that read it themselves,
/// as a wet stroke medium reads it. Inside a layer there is nothing to read, and
/// they draw from their color alone.
///
/// The media are raster: a vector export writes the fill flat.
public struct FillMedium: Hashable, Sendable {

    /// Which look shades the fill. The raw values are what the fill medium
    /// fragment switches on (`OllinFillMedium.kind`).
    enum Kind: UInt32, Sendable {
        case impasto = 1
        case knife = 2
        case wash = 3
        case chrome = 4
        case glass = 5
        case facetedGlass = 6
        case rock = 7
        case marble = 8
        case sand = 9
    }

    let kind: Kind
    /// How far in from the edge the relief rises, or the outline dissolves, in
    /// canvas points.
    var edge: Double = 16
    /// The height of the relief, `1` the default and `0` flat.
    var relief: Double = 1
    /// Impasto: the low swells; rock: how deep the creases are.
    var swell: Double = 0.5
    /// Impasto: the fine detail; the wash: how far it has flowed; sand: how
    /// much each grain catches the light.
    var detail: Double = 0.3
    /// The second color's share (impasto, the knife, rock, sand), the water
    /// (the wash), or how far the glass bends what is under it.
    var amount: Double = 0.35
    /// The size of the look's features in canvas points: swells, knife passes,
    /// the wash's streaks, facets, rock folds, the veins' spacing, the grain.
    var scale: Double = 60
    /// The direction of the knife's passes, the wash's flow, or the marble's
    /// veins, in radians.
    var angle: Double = 0
    /// How far the ground is read from, in canvas points: the wash's drag and
    /// chrome's reflection.
    var reach: Double = 30
    /// How thin the marble's veins are drawn: the exponent their band is raised to.
    var sharpness: Double = 8
    /// The second color (the patches, the knife's other paint, the rock's
    /// second stone, the marble's veins, the sand's other grains); `nil` is a
    /// shade of the fill's own.
    var second: Color? = nil
    var seed: Int = 0

    // MARK: Paint

    /// Impasto, paint laid on thick: it rises along the outline over `edge`
    /// points and levels off inside, swells and ripples there, and is lit as a
    /// surface from the upper left, with two colors worked together in patches.
    ///
    /// - Parameters:
    ///   - edge: how far in from the edge the paint rises, in canvas points.
    ///   - relief: the height of the paint, `1` the default and `0` flat.
    ///   - swell: how much the paint swells inside, `0` level to `1` lumpy.
    ///   - detail: how much fine texture the brush left, `0` smooth to `1` rough.
    ///   - size: the size of the swells, in canvas points.
    ///   - second: the second color worked into the paint; `nil` is a lighter
    ///     shade of the fill's own.
    ///   - mottle: the second color's share of the surface, `0` none to `1` most.
    ///   - seed: which swells and patches.
    public static func impasto(edge: Double = 18, relief: Double = 1, swell: Double = 0.5,
                               detail: Double = 0.3, size: Double = 70, second: Color? = nil,
                               mottle: Double = 0.35, seed: Int = 0) -> FillMedium {
        FillMedium(kind: .impasto, edge: max(edge, 0.5), relief: max(relief, 0),
                   swell: min(max(swell, 0), 2), detail: min(max(detail, 0), 2),
                   amount: min(max(mottle, 0), 1), scale: max(size, 4), second: second, seed: seed)
    }

    /// Impasto with its default settings.
    public static let impasto = FillMedium.impasto()

    /// Paint spread with a palette knife: flat passes, each tilted its own way,
    /// meeting in straight ridges, the paint rising along the outline.
    ///
    /// - Parameters:
    ///   - edge: how far in from the edge the paint rises, in canvas points.
    ///   - relief: the height of the paint, `1` the default and `0` flat.
    ///   - cut: the length of one pass of the knife, in canvas points.
    ///   - angle: the direction the knife moves, in radians.
    ///   - second: the other paint on the knife; `nil` is a lighter shade of the
    ///     fill's own.
    ///   - mottle: the share of passes in the second paint, `0` none to `1` all.
    ///   - seed: which passes.
    public static func knife(edge: Double = 10, relief: Double = 1, cut: Double = 46,
                             angle: Double = 0.35, second: Color? = nil, mottle: Double = 0.3,
                             seed: Int = 0) -> FillMedium {
        FillMedium(kind: .knife, edge: max(edge, 0.5), relief: max(relief, 0),
                   amount: min(max(mottle, 0), 1), scale: max(cut, 4), angle: angle,
                   second: second, seed: seed)
    }

    /// The knife with its default settings.
    public static let knife = FillMedium.knife()

    /// A wash of pigment carried in water. Wet, it glazes what is under it:
    /// each channel the darker of the ground and the pigment at its density,
    /// so a wash darkens the ground and never lightens it, pooling at its edge.
    /// Dry, it covers the ground, as gouache does. The flow drifts the wash's
    /// direction with position, streaks the pigment along it, and drags the
    /// ground along behind it, the drier the farther.
    ///
    /// - Parameters:
    ///   - water: how much water carries the pigment, `0` (opaque gouache) to
    ///     `1` (a transparent glaze).
    ///   - flow: how far the wash has flowed, `0` still to `1` the full `reach`.
    ///   - angle: the direction it flowed, in radians.
    ///   - reach: how far the flow drags the ground, in canvas points.
    ///   - size: the size of the pigment's streaks, in canvas points.
    ///   - edge: how far in from the edge a wet wash pools, in canvas points.
    ///   - seed: which streaks.
    public static func wash(water: Double = 0.85, flow: Double = 0.5, angle: Double = 1.2,
                            reach: Double = 24, size: Double = 40, edge: Double = 6,
                            seed: Int = 0) -> FillMedium {
        FillMedium(kind: .wash, edge: max(edge, 0.5), detail: min(max(flow, 0), 1),
                   amount: min(max(water, 0), 1), scale: max(size, 4), angle: angle,
                   reach: max(reach, 0), seed: seed)
    }

    /// A wash with its default settings.
    public static let wash = FillMedium.wash()

    /// Gouache: the wash at its dry end, opaque, covering the ground and
    /// dragging it the farthest.
    public static let gouache = FillMedium.wash(water: 0, flow: 0.6)

    // MARK: Materials

    /// Chrome: a polished metal whose rim rounds over within `edge` points of
    /// the outline. Where it faces up it reflects a studio's bright sky and dark
    /// floor; toward the rim it reflects what is drawn around it, `reach` points
    /// out. The fill's color tints the metal, so white is plain chrome and a
    /// warm color reads as gold or copper.
    ///
    /// - Parameters:
    ///   - edge: how far in from the edge the rim rounds over, in canvas points.
    ///   - relief: how high the rim rises, `1` the default.
    ///   - reach: how far out the rim's reflection reaches, in canvas points.
    public static func chrome(edge: Double = 40, relief: Double = 1, reach: Double = 60) -> FillMedium {
        FillMedium(kind: .chrome, edge: max(edge, 0.5), relief: max(relief, 0), scale: 90,
                   reach: max(reach, 0))
    }

    /// Chrome with its default settings.
    public static let chrome = FillMedium.chrome()

    /// Glass: a clear pane whose rim rounds over within `edge` points of the
    /// outline, refracting what is drawn under it: straight through the flat
    /// middle, bent toward the rim, with a reflection there that grows as the
    /// surface turns away. The fill's color tints the glass, more where it is
    /// thick.
    ///
    /// - Parameters:
    ///   - edge: how far in from the edge the rim rounds over, in canvas points.
    ///   - relief: how high the rim rises, `1` the default.
    ///   - refraction: how far the rim bends what is under it, `0` none to `4`.
    public static func glass(edge: Double = 32, relief: Double = 1, refraction: Double = 1) -> FillMedium {
        FillMedium(kind: .glass, edge: max(edge, 0.5), relief: max(relief, 0),
                   amount: min(max(refraction, 0), 4))
    }

    /// Glass with its default settings.
    public static let glass = FillMedium.glass()

    /// Faceted glass: glass cut into flat facets on a jittered triangle lattice,
    /// each facet bending what is under it its own way, with a bright or dark
    /// crease where two meet.
    ///
    /// - Parameters:
    ///   - facet: the size of one facet, in canvas points.
    ///   - edge: how far in from the edge the rim rounds over, in canvas points.
    ///   - relief: how steep the facets and the rim are, `1` the default.
    ///   - refraction: how far the facets bend what is under them, `0` none to `4`.
    ///   - seed: which lattice.
    public static func facetedGlass(facet: Double = 34, edge: Double = 14, relief: Double = 1,
                                    refraction: Double = 1, seed: Int = 0) -> FillMedium {
        FillMedium(kind: .facetedGlass, edge: max(edge, 0.5), relief: max(relief, 0),
                   amount: min(max(refraction, 0), 4), scale: max(facet, 4), seed: seed)
    }

    /// Faceted glass with its default settings.
    public static let facetedGlass = FillMedium.facetedGlass()

    /// Rock: noise folded into valley creases that run with the outline near the
    /// edge, the valleys shaded deeper, on an edge that rounds over.
    ///
    /// - Parameters:
    ///   - size: the size of the folds, in canvas points.
    ///   - depth: how deep the creases cut, `0` smooth to `2`.
    ///   - edge: how far in from the edge the stone rounds over, in canvas points.
    ///   - relief: the height of the relief, `1` the default.
    ///   - second: a second stone mixed in broad patches; `nil` keeps one stone.
    ///   - seed: which folds.
    public static func rock(size: Double = 70, depth: Double = 1, edge: Double = 12,
                            relief: Double = 1, second: Color? = nil, seed: Int = 0) -> FillMedium {
        FillMedium(kind: .rock, edge: max(edge, 0.5), relief: max(relief, 0),
                   swell: min(max(depth, 0), 2), amount: second == nil ? 0 : 0.6,
                   scale: max(size, 4), second: second, seed: seed)
    }

    /// Rock with its default settings.
    public static let rock = FillMedium.rock()

    /// Marble: a polished slab veined by a sine band across it, warped by noise
    /// and drawn thin, with fainter veins crossing it.
    ///
    /// - Parameters:
    ///   - veins: the veins' color; `nil` is a deep shade of the fill's own.
    ///   - spacing: how far apart the veins run, in canvas points.
    ///   - angle: the direction the veins run across, in radians.
    ///   - sharpness: how thin the veins are drawn, `1` broad clouds to `20`
    ///     hairlines.
    ///   - edge: how far in from the edge the slab rounds over, in canvas points.
    ///   - seed: which veins.
    public static func marble(veins: Color? = nil, spacing: Double = 90, angle: Double = 0.6,
                              sharpness: Double = 8, edge: Double = 8, seed: Int = 0) -> FillMedium {
        FillMedium(kind: .marble, edge: max(edge, 0.5), scale: max(spacing, 4), angle: angle,
                   sharpness: min(max(sharpness, 1), 40), second: veins, seed: seed)
    }

    /// Marble with its default settings.
    public static let marble = FillMedium.marble()

    /// Sand: grains a few canvas points across, each catching the light its own
    /// way, thinning out toward the outline so the edge dissolves.
    ///
    /// - Parameters:
    ///   - grain: the size of one grain, in canvas points.
    ///   - edge: how far in from the outline the grains thin out, in canvas points.
    ///   - sparkle: how much each grain catches the light, `0` flat to `1`.
    ///   - second: a second color for some grains; `nil` keeps one color.
    ///   - mottle: the second color's share of the grains, `0` none to `1` all.
    ///   - seed: which grains.
    public static func sand(grain: Double = 1.6, edge: Double = 18, sparkle: Double = 0.5,
                            second: Color? = nil, mottle: Double = 0.3, seed: Int = 0) -> FillMedium {
        FillMedium(kind: .sand, edge: max(edge, 0.5), detail: min(max(sparkle, 0), 1),
                   amount: second == nil ? 0 : min(max(mottle, 0), 1), scale: max(grain, 0.35),
                   second: second, seed: seed)
    }

    /// Sand with its default settings.
    public static let sand = FillMedium.sand()

    // MARK: Reading

    /// Whether this medium reads the ground under the fill, which is what asks
    /// the renderer to draw the frame once more without it.
    var readsGround: Bool {
        switch kind {
        case .wash, .chrome, .glass, .facetedGlass: true
        default: false
        }
    }

    /// How far in from the edge the fill's distance has to be carried, in
    /// canvas points: past it the look no longer changes with the distance.
    var reachIn: Double {
        switch kind {
        case .sand: edge * 2
        case .rock: max(edge, scale * 0.6)
        default: edge
        }
    }

    /// The uniform block the fill medium fragment reads, for a pass whose canvas
    /// points are `pixelScale` attachment pixels each.
    func uniforms(pixelScale: SIMD2<Float>, hasGround: Bool) -> OllinFillMedium {
        var u = OllinFillMedium()
        u.kind = kind.rawValue
        u.hasGround = hasGround && readsGround ? 1 : 0
        u.edge = Float(edge)
        u.relief = Float(relief)
        u.swell = Float(swell)
        u.detail = Float(detail)
        u.amount = Float(amount)
        u.scale = Float(scale)
        u.angle = Float(angle)
        u.reach = Float(reach)
        u.sharpness = Float(sharpness)
        // A seed past a float's exact integers would round several seeds to
        // one; folding it into the hashes' period keeps every seed distinct.
        u.seed = Float(UInt32(truncatingIfNeeded: seed) % 65_521)
        u.pixelScale = pixelScale
        u.second = second?.simd4 ?? SIMD4<Float>(-1, -1, -1, -1)
        return u
    }
}
