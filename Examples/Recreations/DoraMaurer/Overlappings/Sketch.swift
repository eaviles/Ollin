//  Recreation after Dóra Maurer - the Overlappings, from the late 1990s,
//  read from Overlappings 38 (2007, acrylic on canvas and wood, 91 x 240 cm),
//  Overlappings 45 (2010, 123 x 104 cm), and Overlappings 47 (Double-Double)
//  (2012, 117 x 124 cm), as the artist's catalog photographs them. A homage,
//  not a reproduction, and not affiliated with or endorsed by the artist or
//  her estate.
//  https://doramaurer.com/artists/maurer-dora/works
//  https://www.whitecube.com/artists/d%C3%B3ra-maurer
//
//  An original Ollin interpretation, written from the paintings and from what
//  she and the critics around her said of them: that she bends the fields and
//  thrusts them against each other, that the colors merge where the shapes
//  overlap because she applies them in transparent layers, and that the
//  fields seem to lie on one curved surface (Új Művészet, 2016; White Cube's
//  notes). Nothing was ported. The surfaces, the step from sheet to sheet, the
//  mixing rule, and the motion are this sketch's own.

import Foundation
import Ollin

/// Overlappings (Dóra Maurer, from 1999). After decades of displacing
/// colored fields across a flat grid, Maurer bent the grid: her later
/// paintings are shaped canvases on wood whose fields of flat color look like
/// sheets curved over one surface and laid across one another, each overlap a
/// third color painted where two fields meet, so that the opaque paint reads
/// as layers of colored film. She had translated Josef Albers's *Interaction
/// of Color* into Hungarian, and the overlaps are his illusion of
/// transparency: a mixed color between two others reads as one of them seen
/// through the other.
///
/// This sketch keeps that in rules. Every work is one bent surface, a patch
/// whose four sides are curves, and on it congruent sheets, each the one
/// below it moved by one step: shifted by the same distance in the same
/// direction across the surface and turned by the same angle about its own
/// middle, as the fields of the *Displacements* moved by one unit a step.
/// Where sheets overlap, the color is mixed as paint mixes (yellow and blue
/// make green, and every mix darkens a little, as pigment does), each sheet
/// laid over the mix below it taking `share` of the new mix, so the upper
/// sheet reads as lying on top. Over a lap the sheets slide apart and back
/// along their step, and the surface flexes. `look` picks the work: the two
/// sheets of Overlappings 38 bent along one S, the two turned sheets of
/// Overlappings 45, or the five squares across one swelling of Overlappings
/// 47. The seed deals the step, around each work's own, and a press deals
/// the next.
///
/// `--export-svg` gives every sheet and every overlap back as a filled path
/// on the surface, so the rule can be read from the file: carried back onto
/// the flat surface, every sheet is the same rectangle, each the one below it
/// moved by the same step, every overlap is exactly the part its sheets
/// share, and its color is their paint mix in order.
@main
final class Overlappings: Sketch {
    /// The three works.
    enum Look: String, CaseIterable, ParamOption {
        /// Overlappings 38 (2007): yellow and blue sheets bent along one S.
        case ribbons
        /// Overlappings 45 (2010): red and turquoise, the upper sheet turned.
        case fan
        /// Overlappings 47 (Double-Double) (2012): five squares on a swelling.
        case cushion
    }

    @Param(icon: "paintpalette") var look = Look.ribbons
    @Param(0.5 ... 0.9, icon: "drop") var share = 0.6
    @Param(4 ... 40, icon: "clock") var seconds = 14.0

    override var loopDuration: Double? { seconds }

    /// One work: the flat surface the sheets are laid out on, the bent
    /// surface it becomes, and the sheets.
    struct Work {
        /// The surface before it bends, in its own units.
        var flat: Rectangle
        /// Each sheet's width and height on the flat surface.
        var sheet: Vector2
        /// The sheets' colors, the lowest first.
        var colors: [Color]
        /// The work's own step from one sheet to the next: a shift across the
        /// flat surface and a turn about the sheet's middle, in radians.
        var shift: Vector2
        var turn: Double
        /// The bent surface's four sides at a given bend, 1 the work's own.
        var sides: (Double) -> (top: [Vector2], right: [Vector2], bottom: [Vector2], left: [Vector2])
    }

    /// The points a side is drawn through.
    static let sideSteps = 96

    static func work(_ look: Look) -> Work {
        switch look {
        case .ribbons:
            // One S, falling from the upper left to the lower right; the top
            // and the bottom side follow the same wave a band apart, so the
            // band thins where it falls steeply, as a sheet seen edge on.
            return Work(
                flat: Rectangle(x: 0, y: 0, width: 1000, height: 400),
                sheet: Vector2(780, 240),
                colors: [Color(hex: 0xE9B10F), Color(hex: 0x1448DA)],
                shift: Vector2(-50, -120), turn: 0,
                sides: { bend in
                    func wave(_ s: Double, _ dy: Double, _ dx: Double) -> Vector2 {
                        Vector2(110 + 860 * s + dx, 470 + 170 * s - 190 * bend * sin(2 * .pi * s) + dy)
                    }
                    let top = (0 ... sideSteps).map { wave(Double($0) / Double(sideSteps), -150, -10) }
                    let bottom = (0 ... sideSteps).map { wave(Double($0) / Double(sideSteps), 150, 20) }
                    return (top, [top.last!, bottom.last!], bottom, [top[0], bottom[0]])
                })
        case .fan:
            // A tall field whose sides bow: the top up, the right side in, the
            // bottom down, and the left side out, more as it bends.
            return Work(
                flat: Rectangle(x: 0, y: 0, width: 600, height: 720),
                sheet: Vector2(420, 430),
                colors: [Color(hex: 0xE11A1F), Color(hex: 0x29DDB8)],
                shift: Vector2(-40, -230), turn: -0.2,
                sides: { bend in
                    let tl = Vector2(320, 170), tr = Vector2(800, 150)
                    let br = Vector2(770, 920), bl = Vector2(290, 880)
                    return (bowed(tl, tr, 60 * bend), bowed(tr, br, -50 * bend),
                            bowed(bl, br, -45 * bend), bowed(tl, bl, -40 * bend))
                })
        case .cushion:
            // A square swelling on every side, and on it five squares, the
            // last a pale one that lightens whatever it lies over.
            return Work(
                flat: Rectangle(x: 0, y: 0, width: 600, height: 600),
                sheet: Vector2(340, 340),
                colors: [Color(hex: 0xF29A0B), Color(hex: 0x1A9CC4), Color(hex: 0x9B4A1B),
                         Color(hex: 0x1B3FA6), Color(hex: 0xF1EEDC)],
                shift: Vector2(48, 40), turn: 0.035,
                sides: { bend in
                    let tl = Vector2(220, 230), tr = Vector2(860, 210)
                    let br = Vector2(850, 860), bl = Vector2(230, 850)
                    return (bowed(tl, tr, 55 * bend), bowed(tr, br, -55 * bend),
                            bowed(bl, br, -55 * bend), bowed(tl, bl, -55 * bend))
                })
        }
    }

    /// A side from `a` to `b` bowed `sag` to the left of its travel at its
    /// middle (to the right for a negative sag), as half a sine wave.
    static func bowed(_ a: Vector2, _ b: Vector2, _ sag: Double) -> [Vector2] {
        let d = b - a
        let left = Vector2(d.y, -d.x).normalized
        return (0 ... sideSteps).map { i in
            let s = Double(i) / Double(sideSteps)
            return a + d * s + left * (sag * sin(.pi * s))
        }
    }

    private var step = (shift: Vector2.zero, turn: 0.0)
    private var dealtFor: (look: Look, seed: Int)?
    private var pressed = false

    override func mousePressed() {
        pressed = true
    }

    override func draw() {
        if pressed {
            pressed = false
            seed(variation + 1)
        }
        let work = Self.work(look)
        if dealtFor?.look != look || dealtFor?.seed != variation {
            dealtFor = (look, variation)
            deal(work)
        }

        // The lap: the sheets slide apart and back along their step while the
        // surface flexes.
        let phase = 2 * Double.pi * time / max(0.5, seconds)
        let reach = 0.82 + 0.18 * cos(phase)
        let bend = 1 + 0.16 * sin(phase)
        let s = work.sides(bend)
        let surface = CoonsPatch(top: Contour(s.top, closed: false), right: Contour(s.right, closed: false),
                                 bottom: Contour(s.bottom, closed: false), left: Contour(s.left, closed: false))

        // The sheets on the flat surface, centered on it, each the one below
        // it moved by the step.
        let count = work.colors.count
        let middle = Vector2(work.flat.x + work.flat.width / 2, work.flat.y + work.flat.height / 2)
        let sheets: [Shape] = (0 ..< count).map { k in
            let m = Double(k) - Double(count - 1) / 2
            return Self.sheet(work.sheet, center: middle + step.shift * (m * reach), angle: step.turn * m * reach)
        }
        let bent = { (shape: Shape) in shape.warped(from: work.flat, into: surface, spacing: 3) }

        background(Color(hex: 0xECEBE6))
        noStroke()

        // The shaped canvas stands off the wall: a soft shadow below it.
        let outline = bent(sheets.dropFirst().reduce(sheets[0]) { $0.union($1) })
        let lift = Vector2(9, 14)
        for (i, grow) in [-4.0, 0, 4, 8, 12].enumerated() {
            fill(Color(white: 0.1, alpha: 0.05 - 0.006 * Double(i)))
            withState {
                translate(lift)
                drawShape(outline.offset(by: grow, join: .round))
            }
        }

        // Every sheet in its own color, the lowest first, and then every
        // overlap in the paint mix of the sheets over it, the smaller sets
        // first, so each place ends in the color of every sheet that covers it.
        for k in 0 ..< count {
            fill(work.colors[k])
            drawShape(bent(sheets[k]))
        }
        let sets = (1 ..< (1 << count)).filter { $0.nonzeroBitCount >= 2 }
            .sorted { ($0.nonzeroBitCount, $0) < ($1.nonzeroBitCount, $1) }
        for set in sets {
            let members = (0 ..< count).filter { set & (1 << $0) != 0 }
            let shared = members.dropFirst().reduce(sheets[members[0]]) { $0.intersection(sheets[$1]) }
            guard shared.area > 1 else { continue }
            fill(mix(members.map { work.colors[$0] }))
            drawShape(bent(shared))
        }
    }

    /// The paint mix of `colors`, the lowest first: each laid over the mix
    /// below it takes `share` of the new mix.
    private func mix(_ colors: [Color]) -> Color {
        colors.dropFirst().reduce(colors[0]) { below, over in below.mixed(with: over, share, in: .paint) }
    }

    /// A `size` sheet with its middle at `center`, turned by `angle`.
    static func sheet(_ size: Vector2, center: Vector2, angle: Double) -> Shape {
        let half = size * 0.5
        let corners = [Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
                       Vector2(half.x, half.y), Vector2(-half.x, half.y)]
        let c = cos(angle), s = sin(angle)
        return Shape(contours: [Contour(corners.map { p in
            center + Vector2(p.x * c - p.y * s, p.x * s + p.y * c)
        }, closed: true)])
    }

    /// Deals the step from the seed: the work's own shift turned by up to 20
    /// degrees and scaled by 0.85 to 1.15, and its turn scaled by 0.6 to 1.4.
    private func deal(_ work: Work) {
        randomSeed(variation)
        let angle = random(-1, 1) * 20 * Double.pi / 180
        let length = random(0.85, 1.15)
        let c = cos(angle), s = sin(angle)
        let shift = Vector2(work.shift.x * c - work.shift.y * s, work.shift.x * s + work.shift.y * c) * length
        step = (shift, work.turn * random(0.6, 1.4))
    }
}
