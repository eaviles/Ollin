import Testing
import CoreGraphics
import Foundation
import ImageIO
@testable import Ollin

/// Fill media (`fillMedium(_:)`): a fill shaded as what it is made of, from its
/// distance to its own edge. Every probe renders headless and reads the frame back.
@Suite(.enabled(if: Snapshot.hasMetal))
@MainActor
struct FillMediumTests {

    /// The frame `draw` makes on a `size`-point canvas over `ground`.
    func render(size: Int = 256, ground: Color = .white,
                _ draw: @escaping @MainActor (Sketch) -> Void) throws -> Pixels {
        Pixels(try OllinApp.image(of: FillSketch(size: size, ground: ground, draw), frame: 1))
    }

    /// Writes a frame to a folder when `OLLIN_FILL_LOOK` names one, for looking
    /// at a medium while it is tuned.
    func look(_ name: String, size: Int = 256, _ draw: @escaping @MainActor (Sketch) -> Void) throws {
        guard let folder = ProcessInfo.processInfo.environment["OLLIN_FILL_LOOK"] else { return }
        let image = try OllinApp.image(of: FillSketch(size: size, ground: Color(white: 0.95), draw), frame: 1)
        let url = URL(fileURLWithPath: folder).appendingPathComponent("\(name).png")
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }

    /// A rounded blob around `center`, its radius wandering by a few sines.
    nonisolated static func blob(_ center: Vector2, radius: Double, phase: Double = 0) -> Shape {
        let points = (0..<160).map { i -> Vector2 in
            let a = Double(i) / 160 * 2 * .pi
            let r = radius * (1 + 0.12 * sin(3 * a + phase) + 0.07 * sin(5 * a + 2 * phase))
            return center + Vector2(cos(a), sin(a)) * r
        }
        return Shape(contours: [Contour(points, closed: true)])
    }

    /// Stripes and dots for a ground, so a glass has something to bend.
    static func stripes(_ s: Sketch, size: Double) {
        // A medium set on the last frame is still set on this one, as a fill is.
        s.noFillMedium()
        s.noStroke()
        for i in 0..<Int(size / 16) {
            s.fill(i % 2 == 0 ? Color(hex: 0x1D3557) : Color(hex: 0xF1FAEE))
            s.drawRect(Double(i) * 16, 0, 16, size)
        }
        s.fill(Color(hex: 0xE63946))
        for j in 0..<6 {
            s.drawCircle(size * 0.15 + Double(j) * size * 0.14, size * 0.5 + 30 * sin(Double(j)), 10)
        }
    }

    // MARK: Reading the frame

    /// A pixel's light, 0...1, linear, averaged over its three channels.
    func light(_ p: Pixels, _ x: Int, _ y: Int) -> Double {
        (linear(UInt8(p.channel(0, x, y))) + linear(UInt8(p.channel(1, x, y))) + linear(UInt8(p.channel(2, x, y)))) / 3
    }

    /// The mean light of the box `x0..<x1` by `y0..<y1`.
    func meanLight(_ p: Pixels, x0: Int, x1: Int, y0: Int, y1: Int) -> Double {
        var sum = 0.0
        for y in y0..<y1 { for x in x0..<x1 { sum += light(p, x, y) } }
        return sum / Double((x1 - x0) * (y1 - y0))
    }

    /// The column profile of the box, each column's light averaged down it.
    func columns(_ p: Pixels, x0: Int, x1: Int, y0: Int, y1: Int) -> [Double] {
        (x0..<x1).map { x in (y0..<y1).reduce(0.0) { $0 + light(p, x, $1) } / Double(y1 - y0) }
    }

    /// The shift, within `-span...span` columns, at which `b` best matches `a`
    /// (b[i] against a[i + lag]), by the correlation of their deviations.
    func bestLag(_ a: [Double], _ b: [Double], span: Int) -> Int {
        let ma = a.reduce(0, +) / Double(a.count), mb = b.reduce(0, +) / Double(b.count)
        var best = 0, bestScore = -Double.infinity
        for lag in -span...span {
            var score = 0.0, n = 0
            for i in b.indices where i + lag >= 0 && i + lag < a.count {
                score += (a[i + lag] - ma) * (b[i] - mb)
                n += 1
            }
            score /= Double(max(n, 1))
            if score > bestScore { bestScore = score; best = lag }
        }
        return best
    }

    /// Vertical bars of seeded widths, dark on white, across the canvas: a ground
    /// with no period, so a shift of it has one answer.
    static func bars(_ s: Sketch, size: Double) {
        s.noFillMedium()
        s.noStroke()
        var x = 0.0, i = 0
        var rng = SplitMix64(seed: 7)
        while x < size {
            let w = 4 + Double(rng.next() % 9)
            s.fill(i % 2 == 0 ? Color(white: 0.15) : Color(white: 0.92))
            s.drawRect(x, 0, w, size)
            x += w
            i += 1
        }
    }

    // MARK: The bands

    @Test func theBandsCarryEachCornersDistanceToTheOutline() {
        // A disc: the distance to its outline is the radius less the distance
        // from its center, and the way out is straight away from the center.
        let radius = 80.0
        let disc = Shape(contours: [Contour((0..<256).map { i in
            let a = Double(i) / 256 * 2 * .pi
            return Vector2(cos(a), sin(a)) * radius
        }, closed: true)])
        let rings = FillRings.make(disc, reach: 20, step: 2)
        #expect(!rings.positions.isEmpty)
        var worst = 0.0, worstTurn = 1.0, area = 0.0
        for i in rings.positions.indices {
            let p = rings.positions[i]
            let r = (p.x * p.x + p.y * p.y).squareRoot()
            let truth = min(radius - r, 20)
            worst = max(worst, abs(Double(rings.distances[i]) - truth))
            if r > 1 {
                let o = rings.outward[i]
                worstTurn = min(worstTurn, (Double(o.x) * p.x + Double(o.y) * p.y) / r)
            }
        }
        for t in stride(from: 0, to: rings.positions.count, by: 3) {
            let a = rings.positions[t], b = rings.positions[t + 1], c = rings.positions[t + 2]
            area += abs((b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)) / 2
        }
        let polygon = Shape.signedArea(disc.contours[0].points)
        // A corner on an inset sits that inset's distance in, within the
        // polygon's own chord error.
        #expect(worst < 0.05, "a corner's distance is off by \(worst)")
        #expect(worstTurn > 0.99, "a corner's way out turns \(acos(worstTurn)) radians from the radius")
        // The bands tile the disc: no gap, no overlap.
        #expect(abs(area - abs(polygon)) < abs(polygon) * 1e-3, "the bands cover \(area) of \(abs(polygon))")
    }

    // MARK: Paint

    @Test func thickPaintLitFromTheLeftReadsBrighterOnItsLeftFlank() throws {
        // Only the rise along the edge: no swells, no detail, one color. The light
        // comes from the upper left, so the flank that rises toward the right
        // faces it.
        let p = try render(ground: .white) { s in
            s.fill(Color(white: 0.5)); s.noStroke()
            s.fillMedium(.impasto(edge: 20, swell: 0, detail: 0, mottle: 0))
            s.drawCircle(128, 128, 90)
        }
        let left = meanLight(p, x0: 41, x1: 54, y0: 120, y1: 136)
        let right = meanLight(p, x0: 202, x1: 215, y0: 120, y1: 136)
        let middle = meanLight(p, x0: 118, x1: 138, y0: 118, y1: 138)
        #expect(left > middle * 1.15, "the left flank reads \(left) against the flat middle's \(middle)")
        #expect(right < middle * 0.85, "the right flank reads \(right) against the flat middle's \(middle)")
    }

    @Test func thePaintMeetsItsFlatInsideWithNoCrease() throws {
        // Along a row from the left edge in, the light bends smoothly from the
        // lit flank into the flat middle: the rise is a smoothstep whose slope
        // falls to nothing where it ends, so the light's second difference
        // stays small there. A rise that ended in a corner would step the light
        // by the flank's whole lift in one pixel. The relief is kept low enough
        // that the flank never turns into the highlight, whose narrow lobe would
        // bend the light sharply with no corner in the paint at all.
        let p = try render(ground: .white) { s in
            s.fill(Color(white: 0.5)); s.noStroke()
            s.fillMedium(.impasto(edge: 20, relief: 0.4, swell: 0, detail: 0, mottle: 0))
            s.drawCircle(128, 128, 90)
        }
        // Rows averaged down a band, which also averages the present pass's dither.
        let profile = columns(p, x0: 40, x1: 90, y0: 112, y1: 144).map { linearToSRGB($0) * 255 }
        var worst = 0.0
        // From past the edge's antialiasing to the middle.
        for i in 4..<(profile.count - 1) {
            worst = max(worst, abs(profile[i + 1] - 2 * profile[i] + profile[i - 1]))
        }
        let lift = profile[4...].max()! - profile.last!
        #expect(lift > 4, "the flank lifts \(lift) levels over the middle")
        // Measured: 1.3 here. A straight rise that ends in a corner reads 5.3,
        // and the cubic smoothstep 2.3: its slope falls to 0 where it ends but
        // the slope's rate of change does not, and the light follows the slope.
        #expect(worst < 2, "the light bends by up to \(worst) levels a pixel")
    }

    // MARK: The wash

    @Test func aWetWashNeverLightensTheGroundAndADryOneCoversIt() throws {
        let ground = try render { s in Self.stripes(s, size: 256) }
        let wet = try render { s in
            Self.stripes(s, size: 256)
            s.fill(Color(hex: 0x9FC2E0)); s.fillMedium(.wash(water: 1, flow: 0)); s.drawRect(40, 40, 176, 176)
        }
        var lighter = 0, darker = 0
        for y in 44..<212 {
            for x in 44..<212 {
                for c in 0..<3 {
                    let g = ground.channel(c, x, y), w = wet.channel(c, x, y)
                    if w > g + 1 { lighter += 1 }
                    if w < g - 4 { darker += 1 }
                }
            }
        }
        #expect(lighter == 0, "\(lighter) channels came out lighter than the ground")
        #expect(darker > 168 * 168, "the wash darkened \(darker) channels")

        let pigment = Color(hex: 0x3A6EA5)
        let flat = try render { s in
            Self.stripes(s, size: 256)
            s.fill(pigment); s.drawRect(40, 40, 176, 176)
        }
        let dry = try render { s in
            Self.stripes(s, size: 256)
            s.fill(pigment); s.fillMedium(.wash(water: 0, flow: 0)); s.drawRect(40, 40, 176, 176)
        }
        var off = 0
        for y in 44..<212 { for x in 44..<212 { for c in 0..<3 where abs(dry.channel(c, x, y) - flat.channel(c, x, y)) > 1 { off += 1 } } }
        #expect(off == 0, "\(off) channels of the dry wash differ from the pigment by more than a level")
    }

    @Test func gouacheDragsTheGroundFartherThanAWash() throws {
        // One dark bar under a white pigment flowing to the right: what shows of
        // the bar in the paint was pulled from its left, so it trails to the
        // right of where the bar lies. The wash shows the ground through it and
        // the gouache only where it picked it up, so each trail is read by where
        // its darkness sits, whatever its strength.
        func bar(_ s: Sketch) {
            s.noFillMedium(); s.noStroke()
            s.fill(Color(white: 0.1)); s.drawRect(100, 0, 12, 256)
        }
        func centroid(_ p: Pixels) -> Double {
            let dark = columns(p, x0: 60, x1: 220, y0: 40, y1: 216).map { 1 - $0 }
            let total = dark.reduce(0, +)
            return dark.enumerated().reduce(0.0) { $0 + Double($1.offset) * $1.element } / max(total, 1e-9) + 60
        }
        let ground = centroid(try render { s in bar(s) })
        func trail(water: Double) throws -> Double {
            centroid(try render { s in
                bar(s)
                s.fill(.white); s.fillMedium(.wash(water: water, flow: 1, angle: 0, reach: 28))
                s.drawRect(20, 20, 216, 216)
            }) - ground
        }
        let wash = try trail(water: 1)
        let gouache = try trail(water: 0)
        #expect(wash > 0.5, "the wash's trail sits \(wash) columns right of the bar")
        #expect(gouache > wash * 2.5, "the gouache's trail sits \(gouache) columns right, the wash's \(wash)")
    }

    // MARK: Glass

    @Test func glassShowsTheGroundStraightAtItsMiddleAndBentAtItsRim() throws {
        // Over bars of no period, the flat middle shows the ground where it lies
        // (its columns follow the ground's, unshifted), and the rim shows it
        // pulled in from beside, so its columns no longer follow it.
        let ground = try render { s in Self.bars(s, size: 256) }
        let glass = try render { s in
            Self.bars(s, size: 256)
            s.fill(.white); s.noStroke(); s.fillMedium(.glass(edge: 40)); s.drawCircle(128, 128, 110)
        }
        func agreement(x0: Int, x1: Int) -> Double {
            correlation(columns(ground, x0: x0, x1: x1, y0: 118, y1: 138),
                        columns(glass, x0: x0, x1: x1, y0: 118, y1: 138))
        }
        let middle = agreement(x0: 88, x1: 168)
        let rim = agreement(x0: 22, x1: 46)
        #expect(middle > 0.98, "the middle follows the ground by \(middle)")
        #expect(bestLag(columns(ground, x0: 88, x1: 168, y0: 118, y1: 138),
                        columns(glass, x0: 88, x1: 168, y0: 118, y1: 138), span: 6) == 0)
        #expect(rim < 0.5, "the rim follows the ground by \(rim)")
    }

    /// The correlation of two profiles of one length, `1` when one is the other
    /// scaled and lifted.
    func correlation(_ a: [Double], _ b: [Double]) -> Double {
        let ma = a.reduce(0, +) / Double(a.count), mb = b.reduce(0, +) / Double(b.count)
        var ab = 0.0, aa = 0.0, bb = 0.0
        for i in a.indices {
            ab += (a[i] - ma) * (b[i] - mb); aa += (a[i] - ma) * (a[i] - ma); bb += (b[i] - mb) * (b[i] - mb)
        }
        return ab / max((aa * bb).squareRoot(), 1e-12)
    }

    // MARK: Seeds, motion, and the routes

    @Test func theSeedPicksThePaintAndAMovedShapeCarriesIt() throws {
        func paint(seed: Int, at x: Double) throws -> Pixels {
            try render(ground: .white) { s in
                s.fill(Color(hex: 0xC8553D)); s.noStroke()
                s.fillMedium(.impasto(swell: 1, detail: 0.6, size: 30, mottle: 0.5, seed: seed))
                s.translate(x, 128)
                s.drawShape(Self.blob(.zero, radius: 50))
            }
        }
        let a = try paint(seed: 1, at: 80), again = try paint(seed: 1, at: 80)
        let other = try paint(seed: 2, at: 80)
        #expect(a.bytes == again.bytes)
        #expect(a.bytes != other.bytes)
        // Moved, the shape takes its swells along: the same pixels, shifted.
        let moved = try paint(seed: 1, at: 176)
        var off = 0, n = 0
        for y in 88..<168 {
            for x in 50..<110 {
                n += 1
                if abs(a.gray(x, y) - moved.gray(x + 96, y)) > 2 { off += 1 }
            }
        }
        #expect(Double(off) / Double(n) < 0.01, "\(off) of \(n) pixels changed when the shape moved")
    }

    @Test func aMirroredCopyIsLitFromTheSameSide() throws {
        // A copy folded half a turn around the middle has its outline turned
        // too: its own left flank still faces the light.
        let p = try render(ground: .white) { s in
            s.fill(Color(white: 0.5)); s.noStroke()
            s.fillMedium(.impasto(edge: 14, swell: 0, detail: 0, mottle: 0))
            s.translate(128, 128)
            s.symmetry(2)
            s.drawCircle(-64, 0, 46)
        }
        for cx in [64, 192] {
            let left = meanLight(p, x0: cx - 44, x1: cx - 36, y0: 122, y1: 134)
            let right = meanLight(p, x0: cx + 36, x1: cx + 44, y0: 122, y1: 134)
            #expect(left > right * 1.3, "the disc at \(cx) reads \(left) on its left flank and \(right) on its right")
        }
    }

    @Test func aRetainedBatchReplaysAMediumFillAsDrawn() throws {
        let direct = try render { s in
            s.fill(Color(hex: 0x8A7F72)); s.noStroke(); s.fillMedium(.rock)
            s.drawShape(Self.blob(Vector2(128, 128), radius: 90))
        }
        let replayed = try render { s in
            let batch = s.makeBatch {
                s.fill(Color(hex: 0x8A7F72)); s.noStroke(); s.fillMedium(.rock)
                s.drawShape(Self.blob(Vector2(128, 128), radius: 90))
            }
            s.drawBatch(batch)
        }
        #expect(direct.bytes == replayed.bytes)
    }

    @Test func aVectorFileWritesTheFillFlat() throws {
        let shaded = FillSketch(size: 256, ground: .white) { s in
            s.fill(.red); s.fillMedium(.marble); s.drawShape(Self.blob(Vector2(128, 128), radius: 80))
        }
        let plain = FillSketch(size: 256, ground: .white) { s in
            s.fill(.red); s.drawShape(Self.blob(Vector2(128, 128), radius: 80))
        }
        func body(_ svg: String) -> [Substring] { svg.split(separator: "\n").filter { !$0.contains("<!--") } }
        #expect(body(try OllinApp.svg(of: shaded)) == body(try OllinApp.svg(of: plain)))
    }

    @Test func theWebPageNamesTheFillMedium() throws {
        let sketch = FillSketch(size: 128, ground: .white) { s in
            s.fill(.red); s.fillMedium(.sand); s.drawCircle(64, 64, 40)
        }
        let refusal = #expect(throws: WebExportRefusal.self) {
            _ = try OllinApp.recordWebFrames(of: sketch, frames: 1, fps: 30)
        }
        #expect(refusal?.call.contains("fillMedium") == true)
    }

    // MARK: The look sheet

    @Test func theLookSheet() throws {
        let looks: [(String, FillMedium, Color)] = [
            ("impasto", .impasto, Color(hex: 0xC8553D)),
            ("knife", .knife, Color(hex: 0x2E86AB)),
            ("wash", .wash, Color(hex: 0x3A6EA5)),
            ("gouache", .gouache, Color(hex: 0xF4D35E)),
            ("chrome", .chrome, .white),
            ("glass", .glass, Color(hex: 0xBFE3F0)),
            ("faceted", .facetedGlass, .white),
            ("rock", .rock, Color(hex: 0x8A7F72)),
            ("marble", .marble, Color(hex: 0xEDE8E0)),
            ("sand", .sand, Color(hex: 0xD9B77E)),
        ]
        for (name, medium, color) in looks {
            try look("fill-\(name)", size: 320) { s in
                Self.stripes(s, size: 320)
                s.fill(color)
                s.noStroke()
                s.fillMedium(medium)
                s.drawShape(Self.blob(Vector2(160, 160), radius: 110))
            }
        }
    }
}

/// A linear-light level as the sRGB component that encodes it.
private func linearToSRGB(_ v: Double) -> Double {
    v <= 0.0031308 ? v * 12.92 : 1.055 * pow(v, 1 / 2.4) - 0.055
}

private final class FillSketch: Sketch {
    var size = 256
    var ground: Color = .white
    var body: @MainActor (Sketch) -> Void = { _ in }

    convenience init(size: Int, ground: Color, _ body: @escaping @MainActor (Sketch) -> Void) {
        self.init()
        self.size = size
        self.ground = ground
        self.body = body
    }

    override var canvasSize: CanvasSize { .square(size) }

    override func draw() {
        background(ground)
        body(self)
    }
}
