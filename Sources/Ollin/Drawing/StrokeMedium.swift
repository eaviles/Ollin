import Foundation
import simd
import COllinShaders

/// The material a stroke is made in: graphite, charcoal, or pastel catching on
/// the paper's tooth, a brush whose bristles streak two pigments, a brush running
/// dry, wet paint that drags the ground under it, oil lit by its own relief, or
/// ink from a pen's nib soaking into the paper. Set it with `strokeMedium(_:)`
/// beside `strokeWeight` and `stroke`:
///
/// ```swift
/// stroke(Color(hex: "#2B2B33"))
/// strokeWeight(10)
/// strokeMedium(.pencil)
/// drawMark(mark)
/// ```
///
/// A medium shades the stroke's ribbon per pixel in the ribbon's own
/// coordinates: how far along the path the pixel is, where it sits across the
/// width, and the local half-width. The stroke's color is the pigment and its
/// alpha the density, so a mark recorded with an opacity response (a light
/// press, a hurried hand) thins the pigment where the hand did, and a dry medium
/// breaks into speckles there rather than fading evenly.
///
/// A medium mark lays down one coat: where it crosses itself, the crossing reads
/// as the rest of the mark does rather than twice as dark. Separate marks still
/// layer over one another.
///
/// The media are raster: a vector export writes the stroke as the flat ribbon
/// it would be without one.
public struct StrokeMedium: Hashable, Sendable {

    /// Which renderer shades the ribbon. The raw values are what the medium
    /// fragment switches on (`OllinStrokeMedium.kind`).
    enum Kind: UInt32, Sendable {
        case dry = 1
        case bristles = 2
        case dryBrush = 3
        case wet = 4
        case oil = 5
        case ink = 6
    }

    let kind: Kind
    /// The paper's tooth (dry media) or grain (dry brush): its cell size in
    /// canvas points.
    var tooth: Double = 2
    /// How gradually pigment gives way to bare paper, `0` hard to `1` soft.
    var softness: Double = 0.2
    /// How far the tooth eats into the stroke's edge, as a fraction of the
    /// half-width.
    var roughness: Double = 0.2
    /// A color per tooth cell, for the multicolor dry media; empty is the
    /// stroke's own color.
    var palette: [Color] = []
    /// The second pigment a brush streaks along the path; `nil` is a darker
    /// shade of the stroke's own.
    var second: Color? = nil
    /// How many bristle streaks run across the width.
    var streaks: Int = 14
    /// How much of the effect: the second pigment's share (bristles), how
    /// soon the brush runs dry (dry brush), or how much ground is dragged
    /// (wet, oil).
    var amount: Double = 0.5
    /// How far back along the path the ground is dragged from, in canvas points.
    var reach: Double = 36
    /// The height of the paint's relief, `1` the default and `0` flat.
    var relief: Double = 1
    /// Ink: how much denser the first and last pen width lie, `0` to `1`.
    var pooling: Double = 0.5
    /// Ink: the writing speed in canvas points per second, which a recorded
    /// point's own speed is measured against.
    var speed: Double = 900
    /// Ink: the shape of the nib's end, the stroke's cap when it was drawn
    /// (the drawer sets it; the ribbon itself always runs square past the ends
    /// to leave the feather room).
    var cap: StrokeCap = .butt
    var seed: Int = 0

    // MARK: Dry media

    /// A dry medium on toothed paper: pigment catches on the tooth's peaks, so
    /// a dense stroke covers it and a light one leaves only the highest peaks
    /// inked. A light line breaks into speckles rather than fading evenly, the
    /// way graphite and chalk behave.
    ///
    /// - Parameters:
    ///   - tooth: the size of the paper's cells, in canvas points. Pencil's is
    ///     about a point and a half; pastel's four or five.
    ///   - softness: how gradually pigment gives way to bare paper, `0` (a hard
    ///     edge to every speck) to `1` (a soft grain).
    ///   - roughness: how far the tooth eats into the stroke's edge, as a
    ///     fraction of the half-width: `0` keeps a clean edge, `0.5` frays it.
    ///   - palette: a color per tooth cell, for a multicolor stick; empty draws
    ///     in the stroke's own color.
    ///   - seed: which paper; the same seed lays the same tooth.
    public static func dry(tooth: Double, softness: Double = 0.2, roughness: Double = 0.2,
                           palette: [Color] = [], seed: Int = 0) -> StrokeMedium {
        StrokeMedium(kind: .dry, tooth: max(tooth, 0.25), softness: min(max(softness, 0), 1),
                     roughness: min(max(roughness, 0), 1), palette: Array(palette.prefix(maxPalette)),
                     seed: seed)
    }

    /// Graphite: a fine, hard tooth and a nearly clean edge.
    public static let pencil = StrokeMedium.dry(tooth: 1.4, softness: 0.12, roughness: 0.12)

    /// Charcoal: a coarse, soft grain and a frayed edge.
    public static let charcoal = StrokeMedium.dry(tooth: 3.2, softness: 0.4, roughness: 0.5)

    /// Pastel: a broad, chalky tooth with a broken edge.
    public static let pastel = StrokeMedium.dry(tooth: 4.5, softness: 0.25, roughness: 0.35)

    /// Pastel with a color per tooth cell: each cell the stick catches takes one
    /// of `palette`'s colors, chosen by the cell, so the mark reads as several
    /// sticks worked together.
    public static func pastel(palette: [Color], seed: Int = 0) -> StrokeMedium {
        .dry(tooth: 4.5, softness: 0.25, roughness: 0.35, palette: palette, seed: seed)
    }

    /// The most colors a multicolor dry medium carries (`OllinStrokeMedium.palette`).
    static let maxPalette = 8

    // MARK: Brushes

    /// A loaded brush whose bristles streak two pigments along the path: the
    /// stroke's color and `second`, the share of the second set by `amount`.
    /// Each streak keeps its own mix along its length, and the bristles at the
    /// edge of the brush run out first near the end of the mark.
    ///
    /// - Parameters:
    ///   - second: the second pigment; `nil` is a deeper shade of the stroke's
    ///     own color.
    ///   - streaks: how many bristles run across the width.
    ///   - amount: the second pigment's share, `0` none to `1` most.
    ///   - seed: which bristles.
    public static func bristles(_ second: Color? = nil, streaks: Int = 14, amount: Double = 0.5,
                                seed: Int = 0) -> StrokeMedium {
        StrokeMedium(kind: .bristles, second: second, streaks: max(streaks, 1),
                     amount: min(max(amount, 0), 1), seed: seed)
    }

    /// A two-pigment bristle brush with its default settings.
    public static let bristles = StrokeMedium.bristles()

    /// A brush running dry: its bristles catch on the paper's grain at three
    /// scales, so the mark breaks up as the paint runs out along it.
    ///
    /// - Parameters:
    ///   - grain: the paper's finest grain, in canvas points.
    ///   - amount: how soon the brush runs dry, `0` loaded the whole way to `1`
    ///     nearly dry by the end.
    ///   - streaks: how many bristles run across the width.
    ///   - seed: which paper and bristles.
    public static func dryBrush(grain: Double = 1.5, amount: Double = 0.6, streaks: Int = 18,
                                seed: Int = 0) -> StrokeMedium {
        StrokeMedium(kind: .dryBrush, tooth: max(grain, 0.25), streaks: max(streaks, 1),
                     amount: min(max(amount, 0), 1), seed: seed)
    }

    /// A dry brush with its default settings.
    public static let dryBrush = StrokeMedium.dryBrush()

    // MARK: Wet paint

    /// Wet paint that drags the ground under it: each pixel of the stroke mixes
    /// its pigment with what lies behind it along the path, strongest toward the
    /// tail, so the mark pulls the colors it crosses along with it.
    ///
    /// The ground is the frame without its wet strokes: everything drawn this
    /// frame (or already on a canvas that keeps its paint) except the wet marks
    /// themselves, so a wet mark never drags itself and the picture is the same
    /// on every run.
    ///
    /// - Parameters:
    ///   - amount: how much of the ground is dragged into the pigment, `0` none
    ///     to `1` the ground alone at the tail.
    ///   - reach: how far back along the path the ground is pulled from, in
    ///     canvas points.
    public static func wet(amount: Double = 0.7, reach: Double = 36) -> StrokeMedium {
        StrokeMedium(kind: .wet, amount: min(max(amount, 0), 1), reach: max(reach, 0))
    }

    /// Wet paint with its default settings.
    public static let wet = StrokeMedium.wet()

    /// Oil: wet paint under a dominant color, its bristle ridges lit as a
    /// relief from the upper left.
    ///
    /// - Parameters:
    ///   - amount: how much of the ground is dragged into the pigment.
    ///   - reach: how far back the ground is pulled from, in canvas points.
    ///   - relief: the height of the ridges, `1` the default and `0` flat.
    ///   - streaks: how many ridges run across the width.
    ///   - seed: which ridges.
    public static func oil(amount: Double = 0.25, reach: Double = 24, relief: Double = 1,
                           streaks: Int = 10, seed: Int = 0) -> StrokeMedium {
        StrokeMedium(kind: .oil, streaks: max(streaks, 1), amount: min(max(amount, 0), 1),
                     reach: max(reach, 0), relief: max(relief, 0), seed: seed)
    }

    /// Oil with its default settings.
    public static let oil = StrokeMedium.oil()

    // MARK: Ink

    /// A pen: ink from a nib. The ink soaks a little way into the paper past
    /// the line's edge, out along the paper's fibers, and farther where the pen
    /// moved slowly or rested; it lies denser in the first and last pen width,
    /// where the nib landed and lifted; and it thins when the pen hurries, down
    /// to a ballpoint's skips. A mark recorded from the pointer carries the speed
    /// each point was made at (`StrokeMark.Sample.speed`), which is what the pen
    /// reads; a line drawn without timing counts as written at `speed`.
    ///
    /// Unlike the other media, an ink stroke lays a second coat where it crosses
    /// itself, as a pen does, so a translucent ink reads darker at every
    /// crossing.
    ///
    /// - Parameters:
    ///   - feather: how far the ink spreads past the nib's edge, in canvas
    ///     points, where the pen moves at its writing speed; up to two and a
    ///     half times that where it rests.
    ///   - pooling: how much denser the first and last pen width lie, `0` none
    ///     to `1`.
    ///   - amount: how much the flow thins with speed, `0` the same ink at any
    ///     speed to `1` a ballpoint that skips when hurried.
    ///   - speed: the writing speed, in canvas points per second. Slower than it
    ///     feathers more; faster thins the flow.
    ///   - seed: which paper, the fibers the feather follows.
    public static func ink(feather: Double = 3, pooling: Double = 0.5, amount: Double = 0.5,
                           speed: Double = 900, seed: Int = 0) -> StrokeMedium {
        StrokeMedium(kind: .ink, amount: min(max(amount, 0), 1), reach: max(feather, 0),
                     pooling: min(max(pooling, 0), 1), speed: max(speed, 1), seed: seed)
    }

    /// A pen with its default settings.
    public static let ink = StrokeMedium.ink()

    // MARK: Reading

    /// Whether this medium reads the ground under the stroke, which is what
    /// asks the renderer to draw the frame once more without the wet marks.
    var readsGround: Bool { kind == .wet || kind == .oil }

    /// Whether a stroke in this medium lays one coat where it crosses itself
    /// (every medium but ink, which lays a second as a pen does), which is what
    /// asks the renderer for the coat stencil.
    var laysOneCoat: Bool { kind != .ink }

    /// How far past the nib's edge an ink stroke's ribbon is widened each side,
    /// in canvas points: room for the feather at its farthest, at rest and over
    /// a pool. The fragment takes it back off to find the nib's own edge.
    var ribbonSpread: Double { kind == .ink ? reach * Self.inkSpread : 0 }

    /// The feather's farthest reach over its reach at writing speed.
    static let inkSpread = 3.0

    /// The pen's pace at a recorded point: its speed over the writing speed, `1`
    /// for a point without timing.
    func pace(of sampleSpeed: Double?) -> Double {
        guard let sampleSpeed else { return 1 }
        return max(sampleSpeed, 0) / speed
    }

    /// The uniform block the medium fragment reads, for a pass whose canvas
    /// points are `pixelScale` attachment pixels each.
    func uniforms(pixelScale: SIMD2<Float>, hasGround: Bool) -> OllinStrokeMedium {
        var u = OllinStrokeMedium()
        u.kind = kind.rawValue
        u.paletteCount = UInt32(palette.count)
        u.hasGround = hasGround && readsGround ? 1 : 0
        u.streaks = Float(streaks)
        u.tooth = Float(tooth)
        u.softness = Float(softness)
        u.roughness = Float(roughness)
        u.amount = Float(amount)
        u.reach = Float(reach)
        u.relief = Float(relief)
        u.pooling = Float(pooling)
        switch cap {
        case .butt: u.cap = 0
        case .round: u.cap = 1
        case .square: u.cap = 2
        }
        // A seed past a float's exact integers would round several seeds to
        // one; folding it into the hashes' period keeps every seed distinct
        // there.
        u.seed = Float(UInt32(truncatingIfNeeded: seed) % 65_521)
        u.pixelScale = pixelScale
        u.second = second?.simd4 ?? SIMD4<Float>(-1, -1, -1, -1)
        withUnsafeMutableBytes(of: &u.palette) { raw in
            let slots = raw.bindMemory(to: SIMD4<Float>.self)
            for (i, c) in palette.prefix(Self.maxPalette).enumerated() {
                slots[i] = c.simd4
            }
        }
        return u
    }
}
