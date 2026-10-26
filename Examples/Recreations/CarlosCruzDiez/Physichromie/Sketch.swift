//  Recreation after Carlos Cruz-Diez - the Physichromies (from 1959) and
//  the Couleur Additive (from 1959), read from the Cruz-Diez Foundation's
//  pages on both series, from Tate's paper on the Physichromies, and from
//  Tate's records of Physichromie No. 113 (1963, reconstructed 1976) and
//  Physichromie No. 123 (1964; perspex, paper and board). A homage, not a
//  reproduction, and not affiliated with or endorsed by the artist, his
//  family, the Cruz-Diez Foundation, the Atelier Cruz-Diez, or Articruz.
//  https://cruz-diez.com/works/physichromie-1959-2019/
//  https://cruz-diez.com/works/couleur-additive/
//  https://www.tate.org.uk/research/tate-papers/32/carlos-cruz-diez-physichromies
//  https://www.tate.org.uk/art/artworks/cruz-diez-physichromie-no-113-t02094
//
//  An original Ollin interpretation, written from the works and the accounts
//  of them. Nothing was ported: he laid the strips and stood the blades by
//  hand, and the color program here is this sketch's own.

import Foundation
import Ollin

/// A *Physichromie* (Carlos Cruz-Diez, Paris). **Move the pointer** to move
/// where you stand: left and right, and up for farther away.
///
/// From 1959 he built pictures out of narrow strips of color laid flat on a
/// ground, with thin blades of cardboard, later of plastic or metal,
/// standing upright between them. Seen head-on you see the strips and the
/// painted edges of the blades. Step to one side and each blade hides the
/// ground beside it and shows you its own face instead, so the picture you
/// see is never the one on the wall: it is made where you stand, and it
/// changes as you walk past. The foundation that keeps his work calls a
/// Physichromie a "light trap." The same year he made the *Couleur
/// Additive* pictures: flat planes of color that meet along an edge, and
/// fine lines of the two colors beside the joint that the eye adds into a
/// third color the panel does not hold.
///
/// `work` picks the panel. **physichromie** is a panel of modules at a
/// declared `pitch`, each a blade standing at its left edge and `strips`
/// fine strips of color on the ground up to the next blade. The ground
/// alternates two colors, each blade carries one color on its left face and
/// another on its right, and the picture is laid out in regions: a base and
/// a few forms, each with its own set of colors, so a square that is there
/// from the left is gone from the right. **additive** is a *Couleur
/// Additive*: vertical planes of flat color, and across every joint a band
/// `joint` centimeters wide of fine lines in the two neighbors' colors,
/// which mix as you step back.
///
/// The geometry is the stated one. A blade `blade` centimeters tall stands
/// at `x` on a panel you look at from `distance` centimeters away, standing
/// `v` centimeters to the right of its middle. Its top lands on the ground
/// at `x - (v - x) * blade / (distance - blade)`, so the blade hides that
/// much ground on the side away from you and shows its face toward you over
/// the same width; its edge, `thickness` millimeters thick, lands at the far
/// end of that face. A blade nearer to you covers a farther one. The panel
/// is drawn at the size it subtends from `distance`, so stepping back in the
/// *Couleur Additive* brings the fine lines down toward a pixel, where they
/// begin to merge on the screen. While the pointer rests you drift from
/// side to side by `sway`.
///
/// `--export-svg` writes every strip, face, and edge as a rectangle, so the
/// pitch, the counts, the occlusion, and the order can be read back from the
/// file.
@main
final class Physichromie: Sketch {
    enum Work: String, CaseIterable, ParamOption { case physichromie, additive }

    @Param(icon: "square.grid.3x3") var work = Work.physichromie
    /// One module, a blade and the ground up to the next blade, in pixels
    /// at the resting distance.
    @Param(6 ... 20, icon: "line.3.horizontal") var pitch = 10
    /// How many fine strips of color lie on the ground of each module.
    @Param(2 ... 6, icon: "line.3.horizontal.decrease") var strips = 4
    /// How tall the blades stand off the ground, in centimeters.
    @Param(0.5 ... 4, icon: "square.3.layers.3d") var blade = 1.8
    /// How thick a blade is, in millimeters: the edge you see head-on.
    @Param(0.5 ... 3, icon: "ruler") var thickness = 1.2
    /// How far from the panel you stand while the pointer rests, in
    /// centimeters.
    @Param(60 ... 400, icon: "figure.stand") var distance = 160.0
    /// Where you stand, left or right of the middle, in centimeters.
    @Param(-60 ... 60, icon: "arrow.left.and.right") var standX = 0.0
    /// How far you drift while the pointer rests, in centimeters.
    @Param(0 ... 60, icon: "figure.walk") var sway = 40.0
    /// The *Couleur Additive*: how wide the band of fine lines at each joint
    /// is, in centimeters.
    @Param(0.5 ... 8, icon: "rectangle.split.2x1") var joint = 3.0

    override var canvasSize: CanvasSize { .square(1080) }
    override var loopDuration: Double? { Physichromie.loop }

    /// The drift comes back to its start after this many seconds.
    nonisolated static let loop = 24.0
    /// The panel, in centimeters, and where its middle sits on the canvas.
    nonisolated static let panelWidth = 100.0
    nonisolated static let panelHeight = 70.0
    nonisolated static let center = Vector2(540, 516)
    /// Pixels per centimeter at the resting distance the pitch is declared
    /// for.
    nonisolated static let pxPerCm = 9.4
    nonisolated static let restingDistance = 160.0

    // MARK: - The color program

    /// The colors one region of the panel is built from.
    struct Palette {
        /// The two colors the ground's fine strips alternate between.
        var ground: (Color, Color)
        /// What a blade shows on its left face, on its right face, and on
        /// its edge.
        var left: Color
        var right: Color
        var edge: Color
    }

    /// A form on the panel, in centimeters from its middle, y down.
    enum Form {
        case rect(x0: Double, y0: Double, x1: Double, y1: Double)
        /// A band running from `top` at the top edge to `bottom` at the
        /// bottom edge, `width` wide across.
        case diagonal(top: Double, bottom: Double, width: Double)

        /// Where a vertical line at `x` enters and leaves the form, or nil
        /// when it misses.
        func span(atX x: Double) -> ClosedRange<Double>? {
            let half = Physichromie.panelHeight / 2
            switch self {
            case let .rect(x0, y0, x1, y1):
                return x >= x0 && x < x1 ? y0 ... y1 : nil
            case let .diagonal(top, bottom, width):
                // The band's middle at height y is top + (bottom - top) * f,
                // f from 0 at the top edge to 1 at the bottom.
                let slope = (bottom - top) / Physichromie.panelHeight
                guard abs(slope) > 1e-9 else {
                    return abs(x - top) < width / 2 ? -half ... half : nil
                }
                let fa = ((x - width / 2) - top) / slope / Physichromie.panelHeight
                let fb = ((x + width / 2) - top) / slope / Physichromie.panelHeight
                let f0 = max(0, min(fa, fb)), f1 = min(1, max(fa, fb))
                guard f1 > f0 else { return nil }
                return (-half + f0 * Physichromie.panelHeight) ... (-half + f1 * Physichromie.panelHeight)
            }
        }
    }

    struct Region {
        var form: Form?
        var palette: Palette
    }

    nonisolated static let red = Color(hex: 0xE3242B)
    nonisolated static let green = Color(hex: 0x1E9E48)
    nonisolated static let blue = Color(hex: 0x1D52C4)
    nonisolated static let yellow = Color(hex: 0xF4D53A)
    nonisolated static let orange = Color(hex: 0xF07A1C)
    nonisolated static let violet = Color(hex: 0x6E2C9C)
    nonisolated static let black = Color(hex: 0x151515)
    nonisolated static let white = Color(hex: 0xF2F1EC)

    /// The base and the four sets a form can take.
    nonisolated static let palettes: [Palette] = [
        Palette(ground: (red, green), left: green, right: red, edge: white),
        Palette(ground: (blue, red), left: blue, right: yellow, edge: black),
        Palette(ground: (green, blue), left: white, right: black, edge: red),
        Palette(ground: (yellow, violet), left: black, right: white, edge: green),
        Palette(ground: (orange, blue), left: violet, right: orange, edge: white),
    ]

    /// A *Couleur Additive* plane.
    struct Plane {
        var x0, x1: Double
        var color: Color
    }

    private var regions: [Region] = []
    private var planes: [Plane] = []
    private var built = -1
    private var viewer = Vector2(0, Physichromie.restingDistance)
    private var viewerReady = false
    private var lastMoved = -100.0

    // MARK: - Drawing

    override func draw() {
        if built != variation {
            var rng = SplitMix64(seed: UInt64(bitPattern: Int64(variation &* 1_000_003 &+ 23)))
            regions = Physichromie.makeRegions(&rng)
            planes = Physichromie.makePlanes(&rng)
            built = variation
        }
        moveTheViewer()

        background(Color(hex: 0xD9D8D3))
        let scale = Physichromie.pxPerCm * Physichromie.restingDistance / viewer.y
        drawFrame(scale)
        switch work {
        case .physichromie: drawPhysichromie(scale)
        case .additive: drawAdditive(scale)
        }
        if !isVectorExporting {
            drawText("move the pointer: where you stand", width / 2, height - 26, size: 14,
                     color: Color(white: 0, alpha: 0.4), align: .center, .bottom)
        }
    }

    /// The pointer stands for you while it moves, left and right across the
    /// panel and up for farther away; when it rests you drift from side to
    /// side at the resting distance.
    private func moveTheViewer() {
        if mouse != previousMouse { lastMoved = time }
        let target: Vector2
        if time - lastMoved < 4 {
            target = Vector2((mouseX / width - 0.5) * 2 * 60, 60 + (1 - mouseY / height) * 340)
        } else {
            let turn = 2 * Double.pi * time / Physichromie.loop
            target = Vector2(standX + sway * sin(turn), distance)
        }
        if !viewerReady {
            viewer = target
            viewerReady = true
        } else {
            viewer = viewer + (target - viewer) * (1 - exp(-deltaTime * 5))
        }
    }

    /// A rectangle in centimeters from the panel's middle, drawn at `scale`
    /// pixels per centimeter and held inside the panel.
    private func rect(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ scale: Double) {
        let hw = Physichromie.panelWidth / 2, hh = Physichromie.panelHeight / 2
        let a = max(x0, -hw), b = min(x1, hw)
        let c = max(y0, -hh), d = min(y1, hh)
        guard b > a, d > c else { return }
        let p = Physichromie.center + Vector2(a, c) * scale
        drawRect(p.x, p.y, (b - a) * scale, (d - c) * scale)
    }

    private func drawFrame(_ scale: Double) {
        noStroke()
        let hw = Physichromie.panelWidth / 2, hh = Physichromie.panelHeight / 2
        // The panel stands off the wall; its shadow falls down and right.
        for (i, spread) in [1.8, 1.0, 0.4].enumerated() {
            fill(Color(white: 0, alpha: 0.05 + 0.04 * Double(i)))
            let p = Physichromie.center + Vector2(-hw - 1.2 + 0.5 - spread, -hh - 1.2 + 0.7 - spread) * scale
            drawRect(p.x, p.y, (Physichromie.panelWidth + 2.4 + 2 * spread) * scale,
                     (Physichromie.panelHeight + 2.4 + 2 * spread) * scale)
        }
        fill(Color(hex: 0x2A2B2E))
        let p = Physichromie.center + Vector2(-hw - 1.2, -hh - 1.2) * scale
        drawRect(p.x, p.y, (Physichromie.panelWidth + 2.4) * scale, (Physichromie.panelHeight + 2.4) * scale)
    }

    // MARK: - The Physichromie

    /// The runs of one vertical line at `x` down the panel: where each
    /// starts and ends, and which region it is in. A later form lies over an
    /// earlier one.
    private func runs(atX x: Double) -> [(y0: Double, y1: Double, region: Int)] {
        let hh = Physichromie.panelHeight / 2
        var cuts: [Double] = [-hh, hh]
        var spans: [(ClosedRange<Double>, Int)] = []
        for (r, region) in regions.enumerated() {
            guard let form = region.form, let span = form.span(atX: x) else { continue }
            spans.append((span, r))
            cuts.append(span.lowerBound)
            cuts.append(span.upperBound)
        }
        cuts = Array(Set(cuts.map { max(-hh, min(hh, $0)) })).sorted()
        var out: [(Double, Double, Int)] = []
        for k in 0 ..< cuts.count - 1 where cuts[k + 1] > cuts[k] {
            let mid = (cuts[k] + cuts[k + 1]) / 2
            var region = 0
            for (span, r) in spans where span.contains(mid) { region = r }
            if let last = out.last, last.2 == region {
                out[out.count - 1].1 = cuts[k + 1]
            } else {
                out.append((cuts[k], cuts[k + 1], region))
            }
        }
        return out.map { (y0: $0.0, y1: $0.1, region: $0.2) }
    }

    private func drawPhysichromie(_ scale: Double) {
        let pitchCm = Double(pitch) / Physichromie.pxPerCm
        let modules = Int((Physichromie.panelWidth / pitchCm).rounded(.down))
        let x0 = -Double(modules) * pitchCm / 2
        let stripWidth = pitchCm / Double(strips)
        let hw = Physichromie.panelWidth / 2, hh = Physichromie.panelHeight / 2

        // The ground: the gap left of the first blade and right of the last
        // in the base ground, then every module's fine strips, each run of
        // a strip in its region's two colors.
        fill(regions[0].palette.ground.0)
        rect(-hw, -hh, hw, hh, scale)
        for i in 0 ..< modules {
            let xb = x0 + Double(i) * pitchCm
            for j in 0 ..< strips {
                let sx = xb + Double(j) * stripWidth
                for run in runs(atX: sx + stripWidth / 2) {
                    let ground = regions[run.region].palette.ground
                    fill(j % 2 == 0 ? ground.0 : ground.1)
                    rect(sx, run.y0, sx + stripWidth, run.y1, scale)
                }
            }
        }

        // The blades: each hides the ground on the side away from you and
        // shows its face toward you over the same width, with its edge at
        // the far end. The ones nearer to you are drawn last, so a near
        // blade covers a far one.
        let v = viewer.x, d = viewer.y
        let k = blade / (d - blade)
        let edgeWidth = thickness / 10 * d / (d - blade)
        let order = (0 ... modules).sorted { a, b in
            let xa = x0 + Double(a) * pitchCm, xbb = x0 + Double(b) * pitchCm
            return abs(xa - v) > abs(xbb - v)
        }
        for i in order {
            let xb = x0 + Double(i) * pitchCm
            let offset = v - xb
            let w = abs(offset) * k
            for run in runs(atX: xb) {
                let palette = regions[run.region].palette
                if offset > 0 {
                    fill(palette.right)
                    rect(xb - w, run.y0, xb, run.y1, scale)
                    fill(palette.edge)
                    rect(xb - w - edgeWidth, run.y0, xb - w, run.y1, scale)
                } else if offset < 0 {
                    fill(palette.left)
                    rect(xb, run.y0, xb + w, run.y1, scale)
                    fill(palette.edge)
                    rect(xb + w, run.y0, xb + w + edgeWidth, run.y1, scale)
                } else {
                    fill(palette.edge)
                    rect(xb - edgeWidth / 2, run.y0, xb + edgeWidth / 2, run.y1, scale)
                }
            }
        }
    }

    // MARK: - The Couleur Additive

    private func drawAdditive(_ scale: Double) {
        let hh = Physichromie.panelHeight / 2
        for plane in planes {
            fill(plane.color)
            rect(plane.x0, -hh, plane.x1, hh, scale)
        }
        // Across every joint, fine lines of the two neighbors' colors, the
        // left one's first, as wide as a Physichromie's strips.
        let lineWidth = Double(pitch) / Double(strips) / Physichromie.pxPerCm
        for k in 1 ..< planes.count {
            let x = planes[k].x0
            let lines = Int((joint / lineWidth).rounded(.down) / 2) * 2
            let start = x - Double(lines) * lineWidth / 2
            for n in 0 ..< lines {
                fill(n % 2 == 0 ? planes[k - 1].color : planes[k].color)
                rect(start + Double(n) * lineWidth, -hh, start + Double(n + 1) * lineWidth, hh, scale)
            }
        }
    }

    // MARK: - Laying out a panel

    /// The base and two to four forms, each with a set of colors of its own,
    /// placed by the seed.
    static func makeRegions(_ rng: inout SplitMix64) -> [Region] {
        var out = [Region(form: nil, palette: palettes[0])]
        var sets = Array(1 ..< palettes.count)
        let count = Int.random(in: 2 ... 4, using: &rng)
        let hw = panelWidth / 2, hh = panelHeight / 2
        for n in 0 ..< count {
            let pick = Int.random(in: 0 ..< sets.count, using: &rng)
            let palette = palettes[sets.remove(at: pick)]
            let form: Form
            switch n == 0 ? 0 : Int.random(in: 0 ... 3, using: &rng) {
            case 0:
                // A square, the form a Physichromie carries most often.
                let side = Double.random(in: 18 ... 34, using: &rng)
                let x = Double.random(in: -hw + 6 ... hw - 6 - side, using: &rng)
                let y = Double.random(in: -hh + 5 ... hh - 5 - side, using: &rng)
                form = .rect(x0: x, y0: y, x1: x + side, y1: y + side)
            case 1:
                // A bar standing the panel's full height.
                let w = Double.random(in: 5 ... 14, using: &rng)
                let x = Double.random(in: -hw + 4 ... hw - 4 - w, using: &rng)
                form = .rect(x0: x, y0: -hh, x1: x + w, y1: hh)
            case 2:
                // A low wide rectangle.
                let w = Double.random(in: 24 ... 48, using: &rng)
                let h = Double.random(in: 8 ... 16, using: &rng)
                let x = Double.random(in: -hw + 4 ... hw - 4 - w, using: &rng)
                let y = Double.random(in: -hh + 4 ... hh - 4 - h, using: &rng)
                form = .rect(x0: x, y0: y, x1: x + w, y1: y + h)
            default:
                // A band running from one edge to the other at a slant.
                let top = Double.random(in: -hw + 10 ... hw - 10, using: &rng)
                let slant = Double.random(in: 14 ... 40, using: &rng) * (Bool.random(using: &rng) ? 1 : -1)
                form = .diagonal(top: top, bottom: top + slant, width: Double.random(in: 6 ... 14, using: &rng))
            }
            out.append(Region(form: form, palette: palette))
        }
        return out
    }

    /// Five to eight planes of flat color across the panel, no two neighbors
    /// alike, their widths by the seed.
    static func makePlanes(_ rng: inout SplitMix64) -> [Plane] {
        let colors = [red, green, blue, yellow, orange, violet, black, white]
        let count = Int.random(in: 5 ... 8, using: &rng)
        var widths = (0 ..< count).map { _ in Double.random(in: 1 ... 3, using: &rng) }
        let total = widths.reduce(0, +)
        widths = widths.map { $0 / total * panelWidth }
        var out: [Plane] = []
        var x = -panelWidth / 2
        var last = -1
        for w in widths {
            var pick = Int.random(in: 0 ..< colors.count, using: &rng)
            while pick == last { pick = Int.random(in: 0 ..< colors.count, using: &rng) }
            out.append(Plane(x0: x, x1: x + w, color: colors[pick]))
            last = pick
            x += w
        }
        out[out.count - 1].x1 = panelWidth / 2
        return out
    }
}
