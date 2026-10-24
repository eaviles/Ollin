//  Recreation after Jesús Rafael Soto - the Vibraciones (from 1957) and the
//  Escrituras (from 1962), read from Vibration (1961; acrylic on wood on
//  iron wire, 99 x 99.5 x 23 cm, Städel Museum, Frankfurt), Vibration jaune
//  (1965; acrylic paint on wood and metal, nylon threads, 106 x 106 x 20 cm,
//  Centre Pompidou, Paris), and Grande écriture (1972; wires, nylon threads,
//  wood, 150 x 300 x 27 cm, Kunstpalast, Düsseldorf), with the museums'
//  descriptions of them. A homage, not a reproduction, and not affiliated
//  with or endorsed by the artist or his estate.
//  https://sammlung.staedelmuseum.de/en/work/vibration
//  https://www.centrepompidou.fr/en/ressources/oeuvre/UJEzYfg
//  https://sammlung.kunstpalast.de/en/objects/41888/grande-ecriture
//
//  An original Ollin interpretation, written from the works and the accounts
//  of them. Nothing was ported: he bent the wires by hand and hung them on
//  nylon threads in front of a ground he painted in stripes.

import Foundation
import Ollin

/// A *Vibración* (Jesús Rafael Soto, Paris). **Move the pointer** to move
/// where you stand.
///
/// He painted a ground of fine black and white stripes and hung thin wires
/// and rods a hand's width in front of it, and the work does nothing until
/// you move. A dark wire over a black stripe is gone, over a white one it is
/// there, and as you step sideways every wire slides across the stripes by
/// its parallax, so it breaks into dashes that run along it, flickers, and
/// seems to come apart. "The vibration is purely optical," he told Guy
/// Brett, "without physical substance."
///
/// `work` picks the panel. **vibration** is the 1961 *Vibration*: a square
/// of vertical stripes in a black border, a row of straight wires hung from
/// the top like pendulums, and a tangle of bent wire in the middle with one
/// heavy rod through it. **yellow** is *Vibration jaune* (1965): a yellow
/// field over horizontal stripes, and yellow rods hung nearly level on one
/// nylon thread in front of the stripes. **escritura** is *Grande écriture*
/// (1972): a long panel striped between two white bands, and wire bent into
/// semicircles, curves, and straight strokes, hung over it and down past it,
/// the writing of the series' name.
///
/// The stripes are `stripePitch` pixels from one black stripe to the next,
/// and the panel holds a whole number of them. A wire hangs `depth`
/// centimeters in front of the ground at most, each at its own share of
/// that, and you stand `distance` centimeters away, so a wire seen from `v`
/// lands on the ground at `v + (p - v) * D / (D - d)`: near wires slide
/// farther than far ones, and the shadows a lamp up and to the left throws
/// on the ground stay where they are. The 1961 row is a second grating:
/// `rowWires` wires `rowSpacing` stripes apart, so the row and the stripes
/// beat against each other, a group of wires showing and the next group
/// gone, and a step to the side moves that beat many times farther than it
/// moves the wires. While the pointer rests you drift by `sway` and the
/// wires swing on their threads by `swing`.
///
/// `--export-svg` writes the stripes as rectangles at the declared pitch and
/// every wire and its shadow as a polyline, so the pitch, the counts, the
/// parallax, and the beat can be read back from the file.
@main
final class Vibracion: Sketch {
    enum Work: String, CaseIterable, ParamOption { case vibration, yellow, escritura }

    @Param(icon: "square.grid.3x3") var work = Work.vibration
    /// One black and one white stripe, in pixels.
    @Param(6 ... 16, icon: "line.3.horizontal") var stripePitch = 8
    /// How far in front of the ground the nearest wire hangs, in centimeters.
    @Param(4 ... 24, icon: "square.3.layers.3d") var depth = 14.0
    /// How far from the panel you stand, in centimeters.
    @Param(80 ... 400, icon: "figure.stand") var distance = 170.0
    /// Where you stand, left or right of the middle, in centimeters.
    @Param(-50 ... 50, icon: "arrow.left.and.right") var standX = 0.0
    /// Where your eyes are, above or below the middle, in centimeters.
    @Param(-30 ... 30, icon: "arrow.up.and.down") var standY = 0.0
    /// How far you drift while the pointer rests, in centimeters.
    @Param(0 ... 40, icon: "figure.walk") var sway = 18.0
    /// How far the hung wires swing on their threads, in degrees.
    @Param(0 ... 2, icon: "metronome") var swing = 0.35
    /// The 1961 row: how many straight wires, how many stripes apart.
    @Param(0 ... 16, icon: "line.3.horizontal") var rowWires = 9
    @Param(2 ... 8, icon: "arrow.left.and.right") var rowSpacing = 3.95
    /// The 1961 tangle: how many bent wires.
    @Param(4 ... 40, icon: "scribble") var tangle = 22
    /// The 1965 rods, and how far from level they hang, in degrees.
    @Param(8 ... 40, icon: "line.horizontal.3") var rods = 28
    @Param(0 ... 12, icon: "angle") var lean = 5.0
    /// The 1972 writing: how many wires.
    @Param(4 ... 36, icon: "pencil.and.scribble") var strokes = 24
    /// How dark the lamp's shadows are on the ground.
    @Param(0 ... 0.5, icon: "shadow") var shadow = 0.2

    override var canvasSize: CanvasSize { .square(1080) }
    override var loopDuration: Double? { Vibracion.loop }

    /// Every motion here comes back to its start after this many seconds.
    static let loop = 24.0
    /// Where the lamp throws a shadow: this far across the ground for every
    /// centimeter a wire hangs in front of it.
    static let lamp = Vector2(0.30, 0.44)

    /// A rectangle in centimeters from the middle of the panel, y down.
    struct Box {
        var x0, y0, x1, y1: Double
        var width: Double { x1 - x0 }
        var height: Double { y1 - y0 }
    }

    /// The painted panel: its outline and edge, the striped ground, and the
    /// flat fields.
    struct Panel {
        var outline: Box
        var edge: Color
        var stripes: Box
        var vertical: Bool
        /// The dark stripe's share of one pitch.
        var duty: Double
        var ink: Color
        var paper: Color
        var fields: [(Box, Color)]
        var wall: Color
        /// Where the middle of the panel sits on the canvas, and its scale.
        var center: Vector2
        var pxPerCm: Double
        /// How far the panel stands off the wall, in centimeters.
        var thickness: Double
    }

    /// One wire, rod, or thread, at rest, as if laid flat on the ground.
    struct Element {
        var points: [Vector2]
        /// Its share of `depth`.
        var depthShare: Double
        /// Where it hangs from, which it swings about.
        var pivot: Vector2
        var weight: Double
        var ink: Color
        /// Whole swings in one loop, its phase, and its share of `swing`.
        var cycles: Int
        var phase: Double
        var reach: Double
        var castsShadow = true
    }

    private var panel: Panel?
    private var elements: [Element] = []
    private var built: [Double] = []
    private var viewer = Vector2(0, 0)
    private var viewerReady = false
    private var lastMoved = -100.0

    // MARK: - Drawing

    override func draw() {
        let signature: [Double] = [Double(variation), Double(Work.allCases.firstIndex(of: work) ?? 0),
                                   Double(stripePitch), Double(rowWires), rowSpacing, Double(tangle),
                                   Double(rods), lean, Double(strokes)]
        if signature != built || panel == nil {
            panel = makePanel()
            elements = makeElements()
            built = signature
        }
        guard let panel else { return }
        moveTheViewer()

        background(panel.wall)
        drawPanel(panel)
        drawShadows(panel)
        drawElements(panel)
        if !isVectorExporting {
            drawText("move the pointer: where you stand", width / 2, height - 26, size: 14,
                     color: panel.wall.luminance > 0.5 ? Color(white: 0, alpha: 0.4) : Color(white: 1, alpha: 0.4),
                     align: .center, .bottom)
        }
    }

    /// The pointer stands for you while it moves; when it rests you drift on
    /// your own, side to side and a little up and down, around where you
    /// stand.
    private func moveTheViewer() {
        if mouse != previousMouse { lastMoved = time }
        let reach = Vector2(48, 30)
        let target: Vector2
        if time - lastMoved < 4 {
            target = Vector2((mouseX / width - 0.5) * 2 * reach.x, (mouseY / height - 0.5) * 2 * reach.y)
        } else {
            let turn = 2 * Double.pi * time / Vibracion.loop
            target = Vector2(standX + sway * sin(turn), standY + sway * 0.35 * sin(2 * turn + 0.7))
        }
        if !viewerReady {
            viewer = target
            viewerReady = true
        } else {
            viewer = viewer + (target - viewer) * (1 - exp(-deltaTime * 5))
        }
    }

    private func toCanvas(_ p: Vector2, _ panel: Panel) -> Vector2 {
        panel.center + p * panel.pxPerCm
    }

    /// Where a point hanging `d` centimeters in front of the ground lands on
    /// the ground, seen from where you stand.
    private func seen(_ p: Vector2, hanging d: Double, _ panel: Panel) -> Vector2 {
        let k = distance / (distance - d)
        return toCanvas(viewer + (p - viewer) * k, panel)
    }

    /// Where the lamp throws that point's shadow on the ground.
    private func shadowOf(_ p: Vector2, hanging d: Double, _ panel: Panel) -> Vector2 {
        toCanvas(p + Vibracion.lamp * d, panel)
    }

    /// An element as it hangs right now, swung about its pivot.
    private func swung(_ e: Element) -> [Vector2] {
        let turn = 2 * Double.pi * Double(e.cycles) * time / Vibracion.loop + e.phase
        let angle = swing * e.reach * (sin(turn) + 0.3 * sin(3 * turn + 1.1)) * Double.pi / 180
        guard angle != 0 else { return e.points }
        return e.points.map { e.pivot + ($0 - e.pivot).rotated(by: angle) }
    }

    private func drawPanel(_ panel: Panel) {
        noStroke()
        // The panel stands off the wall; its shadow falls down and right.
        let off = Vibracion.lamp * panel.thickness
        for (i, spread) in [1.6, 0.9, 0.3].enumerated() {
            fill(Color(white: 0, alpha: 0.06 + 0.04 * Double(i)))
            let o = panel.outline
            let a = toCanvas(Vector2(o.x0 + off.x - spread, o.y0 + off.y - spread), panel)
            let b = toCanvas(Vector2(o.x1 + off.x + spread, o.y1 + off.y + spread), panel)
            drawRect(a.x, a.y, b.x - a.x, b.y - a.y)
        }
        fill(panel.edge)
        let a = toCanvas(Vector2(panel.outline.x0, panel.outline.y0), panel)
        let b = toCanvas(Vector2(panel.outline.x1, panel.outline.y1), panel)
        drawRect(a.x, a.y, b.x - a.x, b.y - a.y)
        for (box, color) in panel.fields {
            fill(color)
            let p = toCanvas(Vector2(box.x0, box.y0), panel)
            let q = toCanvas(Vector2(box.x1, box.y1), panel)
            drawRect(p.x, p.y, q.x - p.x, q.y - p.y)
        }

        // The stripes, a whole number of pitches, the paper first and then
        // every dark stripe at its own multiple of the pitch.
        let s0 = toCanvas(Vector2(panel.stripes.x0, panel.stripes.y0), panel)
        let s1 = toCanvas(Vector2(panel.stripes.x1, panel.stripes.y1), panel)
        fill(panel.paper)
        drawRect(s0.x, s0.y, s1.x - s0.x, s1.y - s0.y)
        fill(panel.ink)
        let pitch = Double(stripePitch)
        let band = pitch * panel.duty
        if panel.vertical {
            let count = Int(((s1.x - s0.x) / pitch).rounded())
            for i in 0 ..< count {
                drawRect(s0.x + Double(i) * pitch, s0.y, band, s1.y - s0.y)
            }
        } else {
            let count = Int(((s1.y - s0.y) / pitch).rounded())
            for i in 0 ..< count {
                drawRect(s0.x, s0.y + Double(i) * pitch, s1.x - s0.x, band)
            }
        }
    }

    private func drawShadows(_ panel: Panel) {
        guard shadow > 0 else { return }
        noFill()
        strokeCap(.round)
        strokeJoin(.round)
        for e in elements where e.castsShadow {
            let d = depth * e.depthShare
            stroke(Color(white: 0, alpha: shadow))
            strokeWeight(e.weight * 1.4)
            drawPolyline(swung(e).map { shadowOf($0, hanging: d, panel) })
        }
    }

    private func drawElements(_ panel: Panel) {
        noFill()
        strokeCap(.round)
        strokeJoin(.round)
        // The farthest first, so a near wire crosses over a far one.
        let order = elements.indices.sorted {
            (elements[$0].depthShare, $0) < (elements[$1].depthShare, $1)
        }
        for e in order.map({ elements[$0] }) {
            let d = depth * e.depthShare
            stroke(e.ink)
            strokeWeight(e.weight)
            drawPolyline(swung(e).map { seen($0, hanging: d, panel) })
        }
    }

    // MARK: - The three panels

    private func makePanel() -> Panel {
        let pitch = Double(stripePitch)
        switch work {
        case .vibration:
            // A square in a black painted border, striped top to bottom.
            let half = Vector2(99 / 2, 99.5 / 2)
            let scale = 930 / 99.5
            let inner = Box(x0: -half.x + 5.6, y0: -half.y + 5.6, x1: half.x - 5.6, y1: half.y - 5.6)
            return Panel(outline: Box(x0: -half.x, y0: -half.y, x1: half.x, y1: half.y),
                         edge: Color(hex: 0x19191B),
                         stripes: wholePitches(inner, vertical: true, pitch: pitch, scale: scale, center: Vector2(540, 528)),
                         vertical: true, duty: 0.5,
                         ink: Color(hex: 0x141414), paper: Color(hex: 0xECEAE4), fields: [],
                         wall: Color(hex: 0xD7D6D2), center: Vector2(540, 528), pxPerCm: scale, thickness: 4)
        case .yellow:
            // A white frame, a yellow field over a field of level stripes.
            let half = 53.0
            let scale = 900 / 106.0
            let inner = 49.2
            let center = Vector2(540, 548)
            let stripes = Box(x0: -inner, y0: 0.6, x1: inner, y1: inner)
            return Panel(outline: Box(x0: -half, y0: -half, x1: half, y1: half),
                         edge: Color(hex: 0xEFEEE9),
                         stripes: wholePitches(stripes, vertical: false, pitch: pitch, scale: scale, center: center),
                         vertical: false, duty: 0.42,
                         ink: Color(hex: 0x86847F), paper: Color(hex: 0xF3F2EE),
                         fields: [(Box(x0: -inner, y0: -inner, x1: inner, y1: -0.6), Color(hex: 0xE6CF1E))],
                         wall: Color(hex: 0x2F3032), center: center, pxPerCm: scale, thickness: 4)
        case .escritura:
            // A long panel: white above and below, striped between.
            let scale = 1000 / 300.0
            let center = Vector2(540, 400)
            let stripes = Box(x0: -148, y0: -51, x1: 148, y1: 47)
            return Panel(outline: Box(x0: -150, y0: -75, x1: 150, y1: 75),
                         edge: Color(hex: 0xF0EFEB),
                         stripes: wholePitches(stripes, vertical: true, pitch: pitch, scale: scale, center: center),
                         vertical: true, duty: 0.62,
                         ink: Color(hex: 0x1B1B1C), paper: Color(hex: 0xEEEDE9), fields: [],
                         wall: Color(hex: 0xF5F5F3), center: center, pxPerCm: scale, thickness: 7)
        }
    }

    /// The striped area trimmed to a whole number of pitches across the
    /// stripes, its first edge on a whole pixel.
    private func wholePitches(_ box: Box, vertical: Bool, pitch: Double, scale: Double, center: Vector2) -> Box {
        var b = box
        if vertical {
            let count = (box.width * scale / pitch).rounded(.down)
            let left = (center.x + box.x0 * scale + (box.width * scale - count * pitch) / 2).rounded()
            b.x0 = (left - center.x) / scale
            b.x1 = b.x0 + count * pitch / scale
        } else {
            let count = (box.height * scale / pitch).rounded(.down)
            let top = (center.y + box.y0 * scale + (box.height * scale - count * pitch) / 2).rounded()
            b.y0 = (top - center.y) / scale
            b.y1 = b.y0 + count * pitch / scale
        }
        return b
    }

    // MARK: - What hangs in front

    private func makeElements() -> [Element] {
        var rng = SplitMix64(seed: UInt64(bitPattern: Int64(variation &* 1_000_003 &+ 41)))
        switch work {
        case .vibration: return vibrationElements(&rng)
        case .yellow: return yellowElements(&rng)
        case .escritura: return escrituraElements(&rng)
        }
    }

    /// Whole swings in a loop for a wire hanging `length` centimeters from
    /// its pivot: a rod swinging from one end, about its own period.
    private func swings(length: Double) -> Int {
        let period = 2 * Double.pi * (2 * length / 100 / (3 * 9.81)).squareRoot()
        return max(1, Int((Vibracion.loop / period).rounded()))
    }

    private func vibrationElements(_ rng: inout SplitMix64) -> [Element] {
        var out: [Element] = []
        let wire = Color(hex: 0x161617)
        guard let panel else { return out }
        let pitchCm = Double(stripePitch) / panel.pxPerCm

        // The row of straight wires hung from the top like pendulums, a
        // second grating `rowSpacing` stripes apart.
        for i in 0 ..< rowWires {
            let x = (Double(i) - Double(rowWires - 1) / 2) * rowSpacing * pitchCm
            let top = -36 + Double.random(in: -3 ... 3, using: &rng)
            let length = Double.random(in: 44 ... 70, using: &rng)
            let pivot = Vector2(x, top)
            out.append(Element(points: [pivot, Vector2(x, top + length)], depthShare: 0.62,
                               pivot: pivot, weight: 1.8, ink: wire,
                               cycles: swings(length: length), phase: Double.random(in: 0 ... 6.283, using: &rng),
                               reach: Double.random(in: 0.5 ... 1, using: &rng)))
        }

        // The tangle: wire bent by hand into loops, long hairpins, arcs, and
        // straight lengths, gathered in the middle and hung from the top.
        for _ in 0 ..< tangle {
            let center = Vector2(gather(&rng) * 15, -6 + gather(&rng) * 26)
            let tilt = Double.random(in: -0.6 ... 0.6, using: &rng)
            var points: [Vector2] = []
            switch Int.random(in: 0 ... 9, using: &rng) {
            case 0 ... 2:
                // A loop, not quite round, not always closed, often drawn
                // out long like a paper clip.
                let long = Double.random(in: 1 ... 3.2, using: &rng)
                let r = Vector2(Double.random(in: 3 ... 8, using: &rng), Double.random(in: 4 ... 9, using: &rng) * long)
                let sweep = Double.random(in: 1.4 ... 2.0, using: &rng) * Double.pi
                let start = Double.random(in: 0 ... 6.283, using: &rng)
                let wobble = Double.random(in: 0 ... 100, using: &rng)
                for j in 0 ... 72 {
                    let a = start + sweep * Double(j) / 72
                    let bend = 1 + 0.08 * signedNoise(wobble + Double(j) * 0.06)
                    points.append(Vector2(cos(a) * r.x * bend, sin(a) * r.y * bend))
                }
            case 3 ... 5:
                // A long hairpin, its bend at the top.
                let w = Double.random(in: 1.2 ... 3.5, using: &rng)
                let l = Double.random(in: 14 ... 34, using: &rng)
                let splay = Double.random(in: 0 ... 0.12, using: &rng)
                for j in 0 ... 16 { points.append(Vector2(-w - splay * l * (1 - Double(j) / 16), l * (1 - Double(j) / 16))) }
                for j in 1 ... 23 {
                    let a = Double.pi + Double.pi * Double(j) / 24
                    points.append(Vector2(cos(a) * w, sin(a) * w))
                }
                for j in 0 ... 16 { points.append(Vector2(w + splay * l * Double(j) / 16 * 0.5, l * Double(j) / 16)) }
            case 6 ... 7:
                // An arc of a wider circle.
                let r = Double.random(in: 9 ... 18, using: &rng)
                let sweep = Double.random(in: 0.5 ... 1.1, using: &rng) * Double.pi
                let start = Double.random(in: 0 ... 6.283, using: &rng)
                for j in 0 ... 48 {
                    let a = start + sweep * Double(j) / 48
                    points.append(Vector2(cos(a) * r, sin(a) * r))
                }
            default:
                // A straight length, mostly hanging down.
                let l = Double.random(in: 22 ... 52, using: &rng)
                points = [Vector2(0, -l / 2), Vector2(0, l / 2)]
            }
            let placed = points.map { center + $0.rotated(by: tilt) }
            let pivot = placed.min(by: { $0.y < $1.y }) ?? center
            out.append(Element(points: placed, depthShare: Double.random(in: 0.35 ... 0.95, using: &rng),
                               pivot: pivot, weight: Double.random(in: 1.4 ... 2.6, using: &rng), ink: wire,
                               cycles: swings(length: 30), phase: Double.random(in: 0 ... 6.283, using: &rng),
                               reach: Double.random(in: 0.3 ... 0.8, using: &rng)))
        }

        // One heavy rod through the middle, the nearest thing on the panel.
        let a = Vector2(-13 + gather(&rng) * 3, -22 + gather(&rng) * 3)
        let b = Vector2(-1 + gather(&rng) * 3, 4 + gather(&rng) * 3)
        out.append(Element(points: [a, b], depthShare: 1, pivot: a, weight: 8.5, ink: Color(hex: 0x232325),
                           cycles: swings(length: 30), phase: Double.random(in: 0 ... 6.283, using: &rng), reach: 0.2))
        return out
    }

    private func yellowElements(_ rng: inout SplitMix64) -> [Element] {
        var out: [Element] = []
        let yellow = Color(hex: 0xEAD31F)
        let threadDepth = 0.7

        // The rods, each tied to the one thread down the middle at its own
        // height, a little off its middle, and hanging nearly level.
        var lowest = 0.0
        for _ in 0 ..< rods {
            let y = Double.random(in: 4 ... 50, using: &rng)
            lowest = max(lowest, y)
            let tilt = Double.random(in: -lean ... lean, using: &rng) * Double.pi / 180
            let length = Double.random(in: 64 ... 104, using: &rng)
            let offset = Double.random(in: -9 ... 9, using: &rng)
            let tie = Vector2(0, y)
            let dir = Vector2(cos(tilt), sin(tilt))
            let a = tie + dir * (offset - length / 2)
            let b = tie + dir * (offset + length / 2)
            out.append(Element(points: [a, tie, b], depthShare: threadDepth,
                               pivot: tie, weight: 2.6, ink: yellow,
                               cycles: Int.random(in: 4 ... 9, using: &rng), phase: Double.random(in: 0 ... 6.283, using: &rng),
                               reach: Double.random(in: 0.5 ... 1, using: &rng)))
        }
        // The thread from its bracket above the panel down to the lowest rod,
        // and the bracket.
        let top = Vector2(0, -56)
        out.append(Element(points: [top, Vector2(0, lowest)], depthShare: threadDepth, pivot: top,
                           weight: 0.8, ink: Color(white: 0.75, alpha: 0.7), cycles: 1, phase: 0, reach: 0,
                           castsShadow: false))
        out.append(Element(points: [Vector2(0, -57.5), Vector2(0, -53.2)], depthShare: threadDepth, pivot: top,
                           weight: 9, ink: Color(hex: 0xA9AAAD), cycles: 1, phase: 0, reach: 0,
                           castsShadow: false))
        return out
    }

    private func escrituraElements(_ rng: inout SplitMix64) -> [Element] {
        var out: [Element] = []
        let wire = Color(hex: 0x1C1C1D)
        for i in 0 ..< strokes {
            var points: [Vector2] = []
            let x = -138 + 276 * (Double(i) + Double.random(in: 0.1 ... 0.9, using: &rng)) / Double(strokes)
            switch Int.random(in: 0 ... 9, using: &rng) {
            case 0 ... 4:
                // A long curve hung from the top of the stripes, bent as it
                // goes down, often out past the panel.
                var p = Vector2(x, -50)
                var heading = Double.pi / 2 + Double.random(in: -0.4 ... 0.4, using: &rng)
                let length = Double.random(in: 70 ... 175, using: &rng)
                let seed = Double.random(in: 0 ... 100, using: &rng)
                let bend = Double.random(in: 0.012 ... 0.03, using: &rng)
                points.append(p)
                var s = 0.0
                while s < length {
                    heading += bend * signedNoise(seed + s * 0.025) * 2.2
                    // Gravity pulls the free end back toward hanging.
                    heading += (Double.pi / 2 - heading) * 0.02
                    p = p + Vector2(cos(heading), sin(heading)) * 0.8
                    points.append(p)
                    s += 0.8
                }
            case 5 ... 7:
                // A semicircle, low on the panel.
                let r = Double.random(in: 6 ... 22, using: &rng)
                let c = Vector2(x, Double.random(in: 10 ... 62, using: &rng))
                let up = Bool.random(using: &rng)
                let start = Double.random(in: -0.3 ... 0.3, using: &rng)
                for j in 0 ... 48 {
                    let a = start + Double.pi * Double(j) / 48
                    points.append(c + Vector2(cos(a) * r, (up ? -1 : 1) * sin(a) * r))
                }
            default:
                // A short straight stroke.
                let l = Double.random(in: 10 ... 34, using: &rng)
                let c = Vector2(x, Double.random(in: 20 ... 66, using: &rng))
                let a = Double.random(in: -0.8 ... 0.8, using: &rng) + (Bool.random(using: &rng) ? 0 : Double.pi / 2)
                let dir = Vector2(cos(a), sin(a)) * (l / 2)
                points = [c - dir, c + dir]
            }
            let pivot = points.min(by: { $0.y < $1.y }) ?? points[0]
            out.append(Element(points: points, depthShare: Double.random(in: 0.45 ... 1, using: &rng),
                               pivot: pivot, weight: 1.5, ink: wire,
                               cycles: swings(length: 60), phase: Double.random(in: 0 ... 6.283, using: &rng),
                               reach: Double.random(in: 0.4 ... 1, using: &rng)))
        }
        return out
    }

    /// A number in -1...1 that gathers toward the middle, the mean of three.
    private func gather(_ rng: inout SplitMix64) -> Double {
        (Double.random(in: -1 ... 1, using: &rng) + Double.random(in: -1 ... 1, using: &rng)
            + Double.random(in: -1 ... 1, using: &rng)) / 3
    }
}
