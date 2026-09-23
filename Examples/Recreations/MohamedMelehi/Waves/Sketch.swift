//  Recreation after Mohamed Melehi - the hard-edge wave paintings of the
//  1970s, read from the two untitled panels of 1975 shown in New Waves at
//  The Mosaic Rooms, London (2019; cellulose paint on wood, 110 x 95 cm and
//  110 x 94 cm), from Waves (1970) and the untitled panels of 1970 and 1972
//  Lawrie Shabibi shows, and from the room of his waves at the Biennale Arte
//  2024. A homage, not a reproduction, and not affiliated with or endorsed
//  by the artist or his estate.
//  https://www.lawrieshabibi.com/exhibitions/78-new-waves-mohamed-melehi-and-the-casablanca-art-mohamed-melehi-at-the-mosaic-rooms-london/overview/
//  https://www.lawrieshabibi.com/artists/167-mohamed-melehi/
//  https://www.labiennale.org/en/art/2024/abstractions/mohamed-melehi
//
//  An original Ollin interpretation, written from the paintings. Nothing was
//  ported: the work is cellulose paint laid flat on a wooden panel, one color
//  up to the next with no edge between them.

import Foundation
import Ollin

/// The wave (Mohamed Melehi, Casablanca and Asilah). From the mid 1960s on
/// he painted one motif: a band that runs straight and then undulates, laid
/// beside itself in cellulose paint on wood, every edge hard, every color
/// flat. A picture is a few bands of one wave set side by side, each the
/// same curve as its neighbor moved over by the band's width, in an order of
/// colors he kept coming back to, yellow into ochre into red into blue into
/// green, or two colors turn and turn about. The bands enter a panel
/// straight, from a corner or an edge, and somewhere on the way they break
/// into the wave and run off the other side. He called the wave his
/// handwriting, and he wrote it across panels, murals, posters and the walls
/// of Asilah for fifty years.
///
/// This sketch keeps the rule and deals the numbers. One ribbon of `bands`
/// bands, each `bandWidth` wide, crosses the panel along `angle`. The ribbon
/// enters straight and becomes the wave `straight` of the way across, the
/// amplitude rising over one wavelength, so the bend is the same for every
/// band. Every band edge is one curve: the run along the axis plus the wave
/// across it, and edge `j` is edge `0` moved over by `j` band widths, so
/// neighbors share their edge point for point and the fills meet with
/// nothing between them. `look` picks the palette, and the palette hands
/// its colors out by declared shares: every color gets its share of the
/// bands in each cycle, spread as evenly as the counts allow and in the
/// palette's own order, the way his rainbows run. The seed turns the cycle
/// and moves the ribbon.
///
/// The wave travels because the phase is the clock: one wavelength per
/// `seconds`, which is also the export loop, while the straight run and the
/// bend hold still.
///
/// Every band exports as one closed outline, so `--export-svg` gives the
/// panel back as the regions the paint covers.
@main
final class Waves: Sketch {
    enum Look: String, CaseIterable, ParamOption { case spectrum, asilah, flame, volcanic }

    @Param(icon: "paintpalette") var look = Look.spectrum
    @Param(2 ... 40, icon: "rectangle.split.3x1") var bands = 9
    @Param(16 ... 160, icon: "arrow.left.and.right") var bandWidth = 48.0
    @Param(0 ... 120, icon: "water.waves") var amplitude = 44.0
    @Param(80 ... 900, icon: "ruler") var wavelength = 190.0
    @Param(0 ... 1, icon: "line.diagonal") var straight = 0.35
    @Param(20 ... 160, icon: "angle") var angle = 58.0
    @Param(4 ... 60, icon: "clock") var seconds = 14.0

    override var canvasSize: CanvasSize { .size(940, 1080) }
    override var loopDuration: Double? { seconds }

    /// Edge points are this far apart along the run.
    private let step = 2.5

    /// One color and how many bands of every cycle it gets.
    private struct Share {
        var color: Color
        var count: Int
    }

    /// A ground and the colors laid over it.
    private struct Paints {
        var ground: Color
        var shares: [Share]
    }

    private func paints(for look: Look) -> Paints {
        switch look {
        case .spectrum:
            // The rainbow order of the 1975 panels: yellow, ochre, red, blue, green on grey.
            return Paints(ground: Color(hex: 0x9AA1AD), shares: [
                Share(color: Color(hex: 0xF2C11C), count: 3),
                Share(color: Color(hex: 0xD79A1E), count: 2),
                Share(color: Color(hex: 0xE84A1E), count: 2),
                Share(color: Color(hex: 0x3A3FA6), count: 2),
                Share(color: Color(hex: 0x3DB24C), count: 1),
            ])
        case .asilah:
            // Green and pink turn and turn about, on the night blue of the corners.
            return Paints(ground: Color(hex: 0x11194A), shares: [
                Share(color: Color(hex: 0x4EBF57), count: 1),
                Share(color: Color(hex: 0xE27E99), count: 1),
            ])
        case .flame:
            // Pink and navy on sage.
            return Paints(ground: Color(hex: 0x4E9C8C), shares: [
                Share(color: Color(hex: 0xF08FB1), count: 1),
                Share(color: Color(hex: 0x1E2A6A), count: 1),
            ])
        case .volcanic:
            // Orange, white and grey under a sky.
            return Paints(ground: Color(hex: 0x6FB6E8), shares: [
                Share(color: Color(hex: 0xF07A1A), count: 2),
                Share(color: Color(hex: 0xF4EFE4), count: 2),
                Share(color: Color(hex: 0xA8A5A0), count: 1),
            ])
        }
    }

    /// Hands the palette out by its shares. Each step every color earns its
    /// share and the richest is dealt and pays the whole cycle, so over one
    /// cycle every color is dealt exactly its share, spread as evenly as the
    /// counts allow, ties going to the palette's order. `start` is how many
    /// bands into the cycle the ribbon begins.
    private static func deal(_ shares: [Share], count: Int, start: Int) -> [Color] {
        let total = shares.reduce(0) { $0 + $1.count }
        var credit = [Int](repeating: 0, count: shares.count)
        var dealt: [Color] = []
        for _ in 0 ..< start + count {
            var pick = 0
            for i in shares.indices {
                credit[i] += shares[i].count
                if credit[i] > credit[pick] { pick = i }
            }
            credit[pick] -= total
            dealt.append(shares[pick].color)
        }
        return Array(dealt.dropFirst(start))
    }

    override func draw() {
        let paint = paints(for: look)
        background(paint.ground)
        noStroke()
        randomSeed(variation)

        // 1. Deal the panel: where the ribbon sits, and where its cycle begins.
        let total = paint.shares.reduce(0) { $0 + $1.count }
        let start = Int(random(Double(total)))
        let shift = random(-0.15, 0.15) * min(width, height)
        let colors = Self.deal(paint.shares, count: bands, start: start)

        // 2. The axis. `u` runs along the ribbon into the panel, `n` across it.
        let theta = angle * .pi / 180
        let u = Vector2(cos(theta), sin(theta))
        let n = Vector2(-u.y, u.x)
        let center = Vector2(width / 2, height / 2)
        // The run reaches past every corner, so the ribbon's ends fall outside.
        let half = (center.length + amplitude + 4).rounded(.up)
        let ribbon = Double(bands) * bandWidth
        let phase = (time / seconds).truncatingRemainder(dividingBy: 1)

        // The straight run ends here, and the wave is full one wavelength on.
        let bend = -half + straight * 2 * half
        func envelope(_ t: Double) -> Double {
            if straight == 0 { return 1 }
            let s = min(max((t - bend) / wavelength, 0), 1)
            return s * s * (3 - 2 * s)
        }

        // 3. Every edge is the one curve moved over by its offset across.
        let stations = Int((2 * half / step).rounded(.up))
        func edge(_ j: Int) -> [Vector2] {
            let offset = shift - ribbon / 2 + Double(j) * bandWidth
            var points: [Vector2] = []
            points.reserveCapacity(stations + 1)
            for k in 0 ... stations {
                let t = -half + Double(k) * (2 * half) / Double(stations)
                let across = offset + amplitude * envelope(t) * sin(2 * .pi * (t / wavelength - phase))
                points.append(center + u * t + n * across)
            }
            return points
        }

        // 4. The bands, each the region between two neighboring edges.
        var lower = edge(0)
        for j in 0 ..< bands {
            let upper = edge(j + 1)
            fill(colors[j])
            // A band is concave wherever the wave turns, so it is a shape
            // that is triangulated, never a fan.
            drawShape(Shape(outer: lower + upper.reversed(), holes: []))
            lower = upper
        }
    }
}
