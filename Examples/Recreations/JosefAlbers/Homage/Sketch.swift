//  Recreation after Josef Albers - "Homage to the Square" (1950-1976), the
//  series of more than a thousand paintings and prints in which three or four
//  flat squares of color, nested and set low in the panel, are the whole
//  picture, so that nothing changes from one to the next but the colors and
//  what they do to each other. A homage, not a reproduction, and not
//  affiliated with or endorsed by the artist or the Josef and Anni Albers
//  Foundation.
//  https://albersfoundation.org
//
//  An original Ollin interpretation, written from the work and from the
//  published account of its format: a grid of ten units; squares of ten,
//  eight, six, and four units, centered across the panel, each smaller one
//  set half a unit lower than the one around it; and four arrangements, one
//  with all four squares and three that leave one of the inner three out (the
//  Albers Foundation's account, as reported in James Mai, "Planes and
//  Frames", Bridges 2016). Nothing was ported. The palettes are this sketch's
//  own rules, not his: he chose every color by eye, from the tube, and wrote
//  the paints down on the back of the panel.

import Foundation
import Ollin

/// "Homage to the Square" (Josef Albers, 1950-1976): the same square, placed
/// by the same rule, painted more than a thousand times, so that the only
/// thing left to look at is what the colors do to one another.
///
/// The format is fixed. On a grid of ten units the squares measure ten,
/// eight, six, and four. Each sits centered across the panel and low in it:
/// the band below an inner square is half the band at its sides, and the band
/// above is one and a half times it. Albers said the downward shift "gives
/// additional weight, but also enhanced movement", and kept it in every one.
/// He used four arrangements: all four squares, or three of them with one of
/// the inner three left out. `format` picks one, or lets each sheet roll its
/// own.
///
/// The colors are where the work is. He painted them flat, unmixed, straight
/// from the tube with a palette knife, and chose each set so the squares would
/// advance or recede, glow or dissolve, in ways the paint itself does not.
/// This sketch has no eye, so it has rules instead, five families it rolls a
/// sheet from, each a reading of one thing his palettes do: a **ramp** of one
/// hue stepping lighter or darker inward; a **glow**, three close dark squares
/// around one bright one; a **near-value** set, four hues at almost one
/// lightness, so the edges shimmer and dissolve; **grays** with one colored
/// square inside them; and a **counter**, warm and cool alternating at close
/// lightness. Every color is built in OKLCH so a step is a step the eye sees,
/// and `contrast` and `drift` scale the lightness and hue steps of the sheet
/// on the panel, live.
///
/// A painting holds still. Here a new sheet arrives every `seconds`, and the
/// change is a crossfade in OKLab over `fade` seconds, so the colors halfway
/// through are colors and not mud. Press the mouse to move on early.
/// `showGrid` draws the ten-unit grid the format sits on.
///
/// Try it: `variation` is the palette, so step the seed in the inspector and
/// keep the sheet you like, or `--export-grid sheets.png --seeds 36` for a
/// wall of them.
@main
final class HomageToTheSquare: Sketch {
    /// The four arrangements, named by the squares they keep, or any of them.
    enum Format: CaseIterable, ParamOption {
        case any, all, tenSixFour, tenEightFour, tenEightSix

        var optionLabel: String {
            switch self {
            case .any: "Any"
            case .all: "10 8 6 4"
            case .tenSixFour: "10 6 4"
            case .tenEightFour: "10 8 4"
            case .tenEightSix: "10 8 6"
            }
        }

        var sizes: [Int] {
            switch self {
            case .any, .all: [10, 8, 6, 4]
            case .tenSixFour: [10, 6, 4]
            case .tenEightFour: [10, 8, 4]
            case .tenEightSix: [10, 8, 6]
            }
        }
    }

    @Param(2 ... 30, icon: "clock") var seconds = 8.0
    @Param(0.2 ... 6, icon: "circle.lefthalf.filled") var fade = 2.5
    @Param(0 ... 2, icon: "sun.max") var contrast = 1.0
    @Param(0 ... 2, icon: "paintpalette") var drift = 1.0
    @Param(icon: "square.on.square") var format = Format.any
    @Param(icon: "grid") var showGrid = false

    /// The five palette rules, each a reading of one thing his sets do.
    private enum Climate: CaseIterable {
        case ramp, glow, nearValue, grays, counter
    }

    /// One sheet: which squares it keeps, and a color for each of the four
    /// sizes (outer to inner) whether or not the sheet shows it, so a
    /// three-square sheet keeps the family and leaves one member out.
    private struct Design {
        var sizes = [10, 8, 6, 4]
        var colors: [OKLCH] = []
    }

    private let allSizes = [10, 8, 6, 4]

    private var current = Design()
    private var next: Design?
    private var onSheet = -1
    private var shownAt = 0.0
    private var fadeBegan = 0.0

    override func setup() {
        noStroke()
    }

    override func draw() {
        // The first sheet is on the panel when you arrive, so frame zero of
        // any seed is a finished painting.
        if onSheet < 0 {
            current = compose(0)
            onSheet = 0
            shownAt = time
        }
        let hold = max(1.0, seconds)
        if next == nil, time - shownAt >= hold { beginFade() }

        var colors = paint(current)
        if let coming = next {
            let t = min(1, (time - fadeBegan) / max(0.1, fade))
            let eased = t * t * (3 - 2 * t)
            colors = zip(colors, paint(coming)).map { $0.mixed(with: $1, eased, in: .oklab) }
            if t >= 1 {
                current = coming
                next = nil
                shownAt = time
            }
        }

        // The panel is the largest square the canvas holds; the outer color
        // is the ground, so a wide window shows the panel's color to its edges.
        let side = min(width, height)
        let unit = side / 10
        let origin = Vector2((width - side) / 2, (height - side) / 2)
        background(colors[0])
        for (index, size) in allSizes.enumerated().dropFirst() {
            fill(colors[index])
            drawRect(rect(of: size, unit: unit, origin: origin))
        }
        if showGrid { drawGrid(unit: unit, origin: origin, over: colors[0]) }
    }

    override func mousePressed() {
        if next == nil { beginFade() }
    }

    private func beginFade() {
        onSheet += 1
        next = compose(onSheet)
        fadeBegan = time
    }

    /// The square of `size` units on the ten-unit grid: centered across, its
    /// band below half the band at its sides, the band above one and a half.
    private func rect(of size: Int, unit: Double, origin: Vector2) -> Rectangle {
        let margin = Double(10 - size) / 2
        return Rectangle(x: origin.x + margin * unit,
                         y: origin.y + 1.5 * margin * unit,
                         width: Double(size) * unit,
                         height: Double(size) * unit)
    }

    // MARK: Composing a sheet

    /// Roll a sheet. The seed is the sheet number and the variation, so any
    /// sheet of any seed comes back the same.
    private func compose(_ sheet: Int) -> Design {
        randomSeed(variation &* 7919 &+ sheet &* 104_729)
        var design = Design()

        if format == .any {
            // All four squares carry most of the series; the three-square
            // arrangements share the rest.
            let roll = random()
            design.sizes = roll < 0.46 ? [10, 8, 6, 4]
                : roll < 0.64 ? [10, 6, 4]
                : roll < 0.82 ? [10, 8, 4]
                : [10, 8, 6]
        } else {
            design.sizes = format.sizes
        }

        let hue = random()
        let climate = pick(Climate.allCases)
        // Inward is lighter on half the sheets and darker on the other half.
        let inward = random() < 0.5 ? 1.0 : -1.0
        switch climate {
        case .ramp:
            let start = inward > 0 ? random(0.34, 0.52) : random(0.64, 0.86)
            let step = random(0.09, 0.14) * inward
            let chroma = random(0.06, 0.15)
            let turn = random(-0.045, 0.045)
            for i in 0 ..< 4 {
                design.colors.append(OKLCH(l: start + step * Double(i),
                                           c: max(0.02, chroma + random(-0.02, 0.02)),
                                           h: hue + turn * Double(i)))
            }
        case .glow:
            let start = random(0.22, 0.38)
            let chroma = random(0.03, 0.07)
            for i in 0 ..< 3 {
                design.colors.append(OKLCH(l: start + 0.035 * Double(i),
                                           c: chroma,
                                           h: hue + random(-0.02, 0.02)))
            }
            design.colors.append(OKLCH(l: random(0.72, 0.86),
                                       c: random(0.14, 0.2),
                                       h: hue + random(-0.08, 0.08)))
        case .nearValue:
            let level = random(0.55, 0.72)
            let chroma = random(0.09, 0.14)
            let spread = random(0.05, 0.12) * (random() < 0.5 ? 1 : -1)
            for i in 0 ..< 4 {
                design.colors.append(OKLCH(l: level + random(-0.015, 0.015),
                                           c: chroma,
                                           h: hue + spread * Double(i)))
            }
        case .grays:
            let start = inward > 0 ? random(0.3, 0.45) : random(0.7, 0.88)
            let step = random(0.08, 0.12) * inward
            for i in 0 ..< 4 {
                design.colors.append(OKLCH(l: start + step * Double(i), c: random(0, 0.012), h: hue))
            }
            let colored = 1 + Int(random(0, 3)) % 3
            design.colors[colored].c = random(0.09, 0.15)
        case .counter:
            let start = random(0.45, 0.7)
            let step = random(-0.05, 0.05)
            for i in 0 ..< 4 {
                let opposite = i % 2 == 1
                design.colors.append(OKLCH(l: start + step * Double(i),
                                           c: random(0.06, 0.12),
                                           h: opposite ? hue + 0.5 + random(-0.06, 0.06) : hue))
            }
        }
        return design
    }

    private func pick<T>(_ choices: [T]) -> T {
        choices[min(choices.count - 1, Int(random(0, Double(choices.count))))]
    }

    /// The four colors the sheet paints, outer to inner. A size the sheet
    /// leaves out takes the color of the square around it, so it is not
    /// there, and a crossfade to a sheet that has it grows it from nothing.
    /// `contrast` scales every lightness step away from the outer square, and
    /// `drift` every hue step, so the sliders move the sheet on the panel.
    private func paint(_ design: Design) -> [Color] {
        let base = design.colors[0]
        var painted: [Color] = []
        var shown = base
        for (index, size) in allSizes.enumerated() {
            if design.sizes.contains(size) {
                let own = design.colors[index]
                shown = OKLCH(l: min(max(base.l + (own.l - base.l) * contrast, 0.02), 0.98),
                              c: own.c,
                              h: base.h + (own.h - base.h) * drift)
            }
            painted.append(Color(shown))
        }
        return painted
    }

    /// The ten-unit grid and the four squares' outlines, in whichever ink the
    /// ground can carry.
    private func drawGrid(unit: Double, origin: Vector2, over ground: Color) {
        let ink: Color = OKLCH(ground).l > 0.55 ? .black : .white
        withState {
            noFill()
            stroke(ink.withAlpha(0.3))
            strokeWeight(1)
            for i in 0 ... 10 {
                let at = Double(i) * unit
                drawLine(origin.x + at, origin.y, origin.x + at, origin.y + 10 * unit)
                drawLine(origin.x, origin.y + at, origin.x + 10 * unit, origin.y + at)
            }
            stroke(ink.withAlpha(0.8))
            strokeWeight(2)
            for size in allSizes {
                drawRect(rect(of: size, unit: unit, origin: origin))
            }
        }
    }
}
