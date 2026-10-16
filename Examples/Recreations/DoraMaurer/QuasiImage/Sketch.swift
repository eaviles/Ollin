//  Recreation after Dóra Maurer - the Quasi-images of 1977 on, read from Quasi
//  Image No. 1 (1977, acrylic on pressboard) in the Ludwig Museum, Budapest,
//  and Relative Quasi-Image (1996, acrylic on canvas and wood, 100 x 100 cm),
//  shown at Tate Modern in 2019. A homage, not a reproduction, and not
//  affiliated with or endorsed by the artist or her estate.
//  https://www.ludwigmuseum.hu/en/node/11730
//  https://www.ludwigmuseum.hu/en/node/847
//
//  An original Ollin interpretation, written from the paintings and from the
//  system of her Displacements as she stated it, quoted in László Beke's
//  essay "Objective Tenderness" (1994), with the selection she described: a
//  detail of one step, chosen by random numbers, enlarged. Nothing was ported.
//  The paths the parts take between the corners, the sizes of the windows,
//  the looks, and the motion are this sketch's own.

import Foundation
import Ollin

/// Quasi-image (Dóra Maurer, from 1977). Her Displacements are a system: a
/// grid of 10 by 10 units on a surface of 4:5, and on it eight parts, four
/// warm and four cold, each displaced one unit a step, the cold ones
/// diagonally and the warm ones vertically and horizontally. From 1976 she
/// stopped painting the whole system and painted details of it instead,
/// chosen first by random numbers and later by eye, enlarged until a cell or
/// two filled the canvas and every thin ruled line was a band of flat color.
/// She called them quasi-images, because they fail to comply with the
/// requirements of an image: they show nothing but a frozen moment of the
/// system. In 1986 she began cutting the white fields out, so the bands hung
/// on the wall as a lattice, and in the 1990s she painted the same details
/// again in broken and glowing colors as relative quasi-images, a homage to
/// Monet's series of one motif under changing light.
///
/// This sketch runs the system of the Displacements sketch beside it: the
/// parts are quarters of the grid, a warm and a cold one starting together in
/// each corner as a contrasting pair, every part ruled with one diagonal a
/// cell and kept in a lane of its own, a warm part moving one unit a step
/// along the border and a cold one along the diagonal, so twenty steps bring
/// them all home. The seed deals the system the same way, then picks a window
/// by random numbers, one and a quarter, nearly two, or two and a half cells
/// wide, its middle on a quarter cell within the four units around the grid's
/// own middle, where the overlaps are, and the canvas is that window. Each
/// part's edges and diagonals are bands a tenth of a cell wide, the warm
/// plane over the cold one, and over a cycle the system steps through all
/// twenty steps, so the bands slide through the window and come back. `look`
/// picks the system's own colors on white, the broken colors of a relative
/// quasi-image, or the white cut away and the bands hung on the wall. A press
/// deals the next.
///
/// `--export-svg` gives every part back as a rectangle and its diagonals as
/// lines, so the window and the step can be read from the file: every part
/// is 5 by 5 cells of one size, apart from its lane, where the rule puts it,
/// and one unit from where it was a step before.
@main
final class QuasiImage: Sketch {
    /// The paints, after three kinds of quasi-image.
    enum Look: String, CaseIterable, ParamOption {
        /// From 1977: the system's own industrial colors on white.
        case quasi
        /// The 1990s: the relative quasi-image, broken and glowing colors on gray.
        case relative
        /// From 1986: the white fields cut away and the bands hung on the wall.
        case cut
    }

    @Param(icon: "paintpalette") var look = Look.quasi
    @Param(0.3 ... 4, icon: "clock") var seconds = 1.2

    override var canvasSize: CanvasSize { .square(1080) }
    override var loopDuration: Double? { Double(System.period) * seconds }

    /// The scene and the rule, as the Displacements sketch states them.
    struct System {
        static let units = 10
        static let side = 5
        static let period = 20
        static let corners = [Vector2(0, 0), Vector2(5, 0), Vector2(5, 5), Vector2(0, 5)]

        struct Part {
            var corner: Int
            var isWarm: Bool
            var pair: Int
            var lane: Double
        }

        var parts: [Part] = []
        var turn = 1

        /// The top left corner of a part after `step` steps, in units.
        func origin(of part: Part, at step: Double) -> Vector2 {
            let corners = Self.corners
            if part.isWarm {
                let s = Self.wrapped(step, Double(Self.period))
                let leg = min(3, Int(s / Double(Self.side)))
                let from = corners[(part.corner + turn * leg + 8) % 4]
                let to = corners[(part.corner + turn * (leg + 1) + 8) % 4]
                return from + (to - from) * ((s - Double(leg * Self.side)) / Double(Self.side))
            }
            let s = Self.wrapped(step, Double(2 * Self.side))
            let across = s <= Double(Self.side) ? s : Double(2 * Self.side) - s
            let from = corners[part.corner], to = corners[(part.corner + 2) % 4]
            return from + (to - from) * (across / Double(Self.side))
        }

        static func diagonals(from origin: Vector2) -> [(Vector2, Vector2)] {
            let n = Double(side)
            return (1 ..< 2 * side).map { m in
                let m = Double(m)
                return m <= n
                    ? (origin + Vector2(0, m), origin + Vector2(m, 0))
                    : (origin + Vector2(m - n, n), origin + Vector2(n, m - n))
            }
        }

        static func wrapped(_ value: Double, _ period: Double) -> Double {
            let r = value.truncatingRemainder(dividingBy: period)
            return r < 0 ? r + period : r
        }
    }

    /// The contrasting pairs, warm first: the system's colors, and the broken
    /// ones of a relative quasi-image.
    static let systemPairs: [(warm: Color, cold: Color)] = [
        (Color(hex: 0xD9281C), Color(hex: 0x1D8A48)),
        (Color(hex: 0xEE7B1E), Color(hex: 0x1E5FD8)),
        (Color(hex: 0xF0BE14), Color(hex: 0x5B3A9A)),
        (Color(hex: 0x6E4B26), Color(hex: 0x169BA8)),
    ]
    static let relativePairs: [(warm: Color, cold: Color)] = [
        (Color(hex: 0xBC2B12), Color(hex: 0x3A3880)),
        (Color(hex: 0xD6611E), Color(hex: 0x294BC3)),
        (Color(hex: 0xC99A34), Color(hex: 0x4F8C98)),
        (Color(hex: 0x6B2E58), Color(hex: 0x5E8A62)),
    ]

    private struct Dealt: Equatable { var seed: Int }
    private var dealtFor: Dealt?
    private var system = System()
    /// The window, in units: its top left corner and its width (its height is
    /// four fifths of that, so the cells keep their 4:5 on a square canvas).
    private var windowOrigin = Vector2(0, 0)
    private var windowWidth = 2.5
    private var pressed = false

    override func mousePressed() {
        pressed = true
    }

    override func draw() {
        if pressed {
            pressed = false
            seed(variation + 1)
        }
        let wanted = Dealt(seed: variation)
        if dealtFor != wanted {
            dealtFor = wanted
            deal()
        }

        let raw = time / max(0.1, seconds)
        let whole = (raw + 1e-9).rounded(.down)
        let rest = 0.4
        let glide = max(0, min(1, (raw - whole - rest) / (1 - rest)))
        let step = whole + glide * glide * (3 - 2 * glide)

        switch look {
        case .quasi:
            background(Color(hex: 0xF4F2EA))
            paintBands(at: step, pairs: Self.systemPairs)
        case .relative:
            background(Color(hex: 0xDCDBD6))
            paintBands(at: step, pairs: Self.relativePairs)
        case .cut:
            background(Color(hex: 0xE9E7E2))
            let lattice = makeRenderTarget()
            withTarget(lattice) {
                paintBands(at: step, pairs: Self.systemPairs)
            }
            let shadow = Filter.dropShadow(offset: Vector2(width * 0.009, width * 0.014),
                                           radius: width * 0.008, color: Color(white: 0, alpha: 0.32))
            drawImage(lattice.filtered(shadow).image, 0, 0)
        }
    }

    /// Every part's edges and diagonals as bands of its color, the lower plane
    /// first, each band in the part's lane.
    private func paintBands(at step: Double, pairs: [(warm: Color, cold: Color)]) {
        let cell = Vector2(width / windowWidth, width / windowWidth * 1.25)
        let band = cell.x / 10
        let diagonal = band * (cell.x + cell.y) / (cell.x * cell.x + cell.y * cell.y).squareRoot()
        func pixel(_ unit: Vector2) -> Vector2 {
            Vector2((unit.x - windowOrigin.x) * cell.x, (unit.y - windowOrigin.y) * cell.y)
        }
        noFill()
        strokeCap(.butt)
        strokeJoin(.miter)
        let order = system.parts.filter { !$0.isWarm }.sorted { $0.lane < $1.lane }
            + system.parts.filter { $0.isWarm }.sorted { $0.lane < $1.lane }
        for part in order {
            let origin = system.origin(of: part, at: step)
            let offset = Vector2(part.lane * band, part.lane * band)
            let topLeft = pixel(origin) + offset
            let reach = Rectangle(x: topLeft.x - band / 2, y: topLeft.y - band / 2,
                                  width: 5 * cell.x + band, height: 5 * cell.y + band)
            stroke(part.isWarm ? pairs[part.pair].warm : pairs[part.pair].cold)
            withClip(reach) {
                strokeWeight(diagonal)
                for (a, b) in System.diagonals(from: origin) {
                    let p = pixel(a) + offset, q = pixel(b) + offset
                    let along = (q - p).normalized * band
                    drawLine(p - along, q + along)
                }
            }
            // A polygon, so the corners are mitered square as painted.
            strokeWeight(band)
            drawPolygon([topLeft, topLeft + Vector2(5 * cell.x, 0),
                         topLeft + Vector2(5 * cell.x, 5 * cell.y), topLeft + Vector2(0, 5 * cell.y)])
        }
    }

    /// Deals the system as the Displacements sketch does, then the window.
    private func deal() {
        randomSeed(variation)
        let corners = shuffled([0, 1, 2, 3])
        system.parts = []
        for p in 0 ..< 4 {
            system.parts.append(.init(corner: corners[p], isWarm: true, pair: p, lane: Double(2 * p) - 3.5))
            system.parts.append(.init(corner: corners[p], isWarm: false, pair: p, lane: Double(2 * p + 1) - 3.5))
        }
        system.turn = random() < 0.5 ? 1 : -1

        // The window, by random numbers: a width, then a middle on the quarter
        // cell within the four units around the grid's own middle, where the
        // parts always overlap (a warm part's inner edges never leave it, and
        // the cold ones cross it every five steps).
        windowWidth = randomChoice([1.25, 1.875, 2.5])
        let windowHeight = windowWidth * 0.8
        let middle = Vector2(Double(randomChoice(Array(12 ... 28))) / 4,
                             Double(randomChoice(Array(12 ... 28))) / 4)
        windowOrigin = middle - Vector2(windowWidth, windowHeight) / 2
    }
}
