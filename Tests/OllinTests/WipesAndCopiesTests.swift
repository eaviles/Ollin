import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import Ollin

/// Wipes, copies, and a glowing edge. A wipe at progress 0 and 1 is each layer
/// byte for byte, halfway along a straight edge it holds one layer on each half
/// with the front centered and as wide as its feather, and bands that are
/// shuffled go whole in the order the seed drew; copies of a layer are counted
/// exactly, shrink by the stated ratio, fade by the stated ratio, and turn their
/// hue by the stated step; the edge glow at width 0 is the layer, never darkens
/// a pixel, lights the edge, and moves its spots by a quarter turn a unit of
/// phase.
@Suite
@MainActor
struct WipesAndCopiesTests {

    static let side = 240

    /// Two scenes that differ everywhere: warm stripes and cool rings.
    static func warm(_ s: Sketch) {
        s.noStroke()
        for row in 0 ..< 12 {
            s.fill(Color(red: 0.75, green: 0.35 + 0.03 * Double(row), blue: 0.2))
            s.drawRect(0, Double(row) * 20, 240, 20)
        }
        s.fill(Color(red: 0.95, green: 0.85, blue: 0.4)); s.drawCircle(80, 120, 40)
    }

    static func cool(_ s: Sketch) {
        s.noStroke()
        s.fill(Color(red: 0.12, green: 0.2, blue: 0.4)); s.drawRect(0, 0, 240, 240)
        for r in stride(from: 110.0, to: 10, by: -20) {
            s.fill(Color(red: 0.2, green: 0.45 + r / 400, blue: 0.7)); s.drawCircle(150, 110, r)
            s.fill(Color(red: 0.12, green: 0.2, blue: 0.4)); s.drawCircle(150, 110, r - 8)
        }
    }

    /// Up to three layers on the canvas: the warm scene, the cool scene, or the
    /// warm one wiped into the cool one; or one layer through a filter.
    final class Wiped: Sketch {
        enum Shot { case warm, cool, wipe(WipeOrder, Double, Double), reveal(WipeOrder, Double) }
        var shot: Shot = .warm
        override var canvasSize: CanvasSize { .square(WipesAndCopiesTests.side) }
        override func draw() {
            background(.black)
            let a = makeRenderTarget(), b = makeRenderTarget()
            withTarget(a) { WipesAndCopiesTests.warm(self) }
            withTarget(b) { WipesAndCopiesTests.cool(self) }
            switch shot {
            case .warm: drawImage(a.image, 0, 0)
            case .cool: drawImage(b.image, 0, 0)
            case let .wipe(order, progress, feather):
                drawImage(a.combined(with: b, .wipe(order, progress: progress, feather: feather)).image, 0, 0)
            case let .reveal(order, progress):
                drawImage(b.filtered(.wipe(order, progress: progress)).image, 0, 0)
            }
        }
    }

    private func render(_ shot: Wiped.Shot) throws -> Pixels {
        let s = Wiped(); s.shot = shot
        let image = try OllinApp.image(of: s, frame: 1)
        Self.dump(image, "wipe")
        return Pixels(image)
    }

    static func dump(_ image: CGImage, _ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["OLLIN_EFFECT_DUMP"] else { return }
        let url = URL(fileURLWithPath: "\(dir)/\(name)-\(UUID().uuidString.prefix(6)).png")
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }

    private func identical(_ a: Pixels, _ b: Pixels) -> Bool { a.bytes == b.bytes }

    /// 0 where `p` reads as the warm scene's pixel, 1 where the cool one's, and
    /// between where it is a blend (measured on the channel they differ most in).
    private func share(_ p: Pixels, _ warm: Pixels, _ cool: Pixels, _ x: Int, _ y: Int) -> Double {
        var best = 0, bestSpan = 0
        for c in 0 ..< 3 {
            let span = abs(cool.channel(c, x, y) - warm.channel(c, x, y))
            if span > bestSpan { bestSpan = span; best = c }
        }
        guard bestSpan > 8 else { return -1 }
        // In linear light, where the two layers are mixed.
        let w = linear(UInt8(warm.channel(best, x, y))), c = linear(UInt8(cool.channel(best, x, y)))
        return (linear(UInt8(p.channel(best, x, y))) - w) / (c - w)
    }

    // MARK: Wipes

    @Test(.enabled(if: Snapshot.hasMetal))
    func aWipeAtItsEndsIsEachLayerExactly() throws {
        let warm = try render(.warm), cool = try render(.cool)
        for order in [WipeOrder.directional(angle: 0.3), .radial().bands(5).shuffled(seed: 2),
                      .cells(columns: 6, rows: 4).checker().diamond(), .noise(size: 0.15, seed: 4)] {
            #expect(identical(try render(.wipe(order, 0, 0.05)), warm), "progress 0 is the base, \(order)")
            #expect(identical(try render(.wipe(order, 1, 0.05)), cool), "progress 1 is the aux, \(order)")
            #expect(identical(try render(.reveal(order, 1)), cool), "a reveal at 1 is the layer, \(order)")
        }
        // A reveal at 0 is nothing over the black ground.
        let none = try render(.reveal(.radial(), 0))
        #expect(none.bytes.enumerated().allSatisfy { $0.offset % 4 == 3 || $0.element <= 1 })
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func halfwayAStraightEdgeHoldsOneLayerOnEachHalf() throws {
        let warm = try render(.warm), cool = try render(.cool)
        let feather = 0.1
        let half = try render(.wipe(.directional(), 0.5, feather))
        // The run is the layer's width, so the front is 24 pixels wide, centered.
        let front = feather * Double(Self.side)
        var mixedColumns = 0
        for x in 0 ..< Self.side {
            var shares: [Double] = []
            for y in stride(from: 3, to: Self.side, by: 7) {
                let s = share(half, warm, cool, x, y)
                if s >= 0 { shares.append(s) }
            }
            guard !shares.isEmpty else { continue }
            let mean = shares.reduce(0, +) / Double(shares.count)
            let center = Double(x) + 0.5
            if center < 120 - front / 2 - 1 { #expect(mean > 0.97, "column \(x) is the cool layer: \(mean)") }
            if center > 120 + front / 2 + 1 { #expect(mean < 0.03, "column \(x) is the warm layer: \(mean)") }
            if mean > 0.03 && mean < 0.97 { mixedColumns += 1 }
            if abs(center - 120) < 1 { #expect(abs(mean - 0.5) < 0.1, "the front is centered: \(mean)") }
        }
        // The front is a smoothstep across the feather, which leaves 0.03 a tenth
        // of the way in (3x^2 - 2x^3 = 0.03 at x = 0.1015) and passes 0.97 as far
        // from the other end.
        let expected = front * (1 - 2 * 0.1015)
        #expect(abs(Double(mixedColumns) - expected) <= 2, "the front is the feather wide: \(mixedColumns) columns of \(expected)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func shuffledBandsGoWholeInTheSeededOrder() throws {
        let warm = try render(.warm), cool = try render(.cool)
        let order = WipeOrder.directional().bands(4).shuffled(seed: 7)
        let slots = order.permutation.map { Int($0.x) }
        #expect(Set(slots) == Set(0 ..< 4), "every band has a slot: \(slots)")
        #expect(slots != [0, 1, 2, 3], "the seed reorders them")
        #expect(WipeOrder.directional().bands(4).shuffled(seed: 8).permutation.map { Int($0.x) } != slots
                || WipeOrder.directional().bands(4).shuffled(seed: 9).permutation.map { Int($0.x) } != slots,
                "another seed, another order")
        // Band b goes in slot slots[b], so after k slots the bands whose slot is
        // under k are cool and the rest warm, each one whole.
        for k in 0 ... 4 {
            let p = try render(.wipe(order, (Double(k) + 0.5) / 4.5, 0.001))
            for band in 0 ..< 4 {
                let gone = slots[band] < k
                let x0 = band * 60
                for x in stride(from: x0 + 2, to: x0 + 58, by: 4) {
                    for y in stride(from: 5, to: Self.side, by: 13) {
                        let s = share(p, warm, cool, x, y)
                        guard s >= 0 else { continue }
                        #expect(gone ? s > 0.97 : s < 0.03,
                                "after \(k) slots band \(band) (slot \(slots[band])) is \(gone ? "cool" : "warm"): \(s) at \(x),\(y)")
                    }
                }
            }
        }
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aCheckerTakesEveryOtherCellFirst() throws {
        let warm = try render(.warm), cool = try render(.cool)
        let p = try render(.wipe(.cells(columns: 4, rows: 4).checker(), 0.5, 0.001))
        for row in 0 ..< 4 {
            for column in 0 ..< 4 {
                let s = share(p, warm, cool, column * 60 + 30, row * 60 + 30)
                guard s >= 0 else { continue }
                #expect((row + column) % 2 == 0 ? s > 0.97 : s < 0.03, "cell \(column),\(row): \(s)")
            }
        }
    }

    // MARK: Copies

    /// A small disc (or a square) in the middle of a clear layer, copied.
    final class Copied: Sketch {
        var filter: Filter?
        var color = Color.white
        var size = 40.0
        override var canvasSize: CanvasSize { .square(WipesAndCopiesTests.side) }
        override func draw() {
            background(.black)
            let mark = makeRenderTarget()
            withTarget(mark) {
                noStroke(); fill(color)
                drawRect(center: Vector2(120, 120), width: size, height: size)
            }
            drawImage((filter.map { mark.filtered($0) } ?? mark).image, 0, 0)
        }
    }

    private func copies(_ filter: Filter, color: Color = .white, size: Double = 40) throws -> Pixels {
        let s = Copied(); s.filter = filter; s.color = color; s.size = size
        let image = try OllinApp.image(of: s, frame: 1)
        Self.dump(image, "copies")
        return Pixels(image)
    }

    /// The lit regions (any channel past `threshold`), each as its pixels, by a
    /// four-way flood.
    private func regions(_ p: Pixels, threshold: Int = 24) -> [[(Int, Int)]] {
        var seen = [Bool](repeating: false, count: p.width * p.height)
        var found: [[(Int, Int)]] = []
        func lit(_ x: Int, _ y: Int) -> Bool {
            (0 ..< 3).contains { p.channel($0, x, y) > threshold }
        }
        for y in 0 ..< p.height {
            for x in 0 ..< p.width where !seen[y * p.width + x] && lit(x, y) {
                var stack = [(x, y)], region: [(Int, Int)] = []
                seen[y * p.width + x] = true
                while let (cx, cy) = stack.popLast() {
                    region.append((cx, cy))
                    for (nx, ny) in [(cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)]
                    where nx >= 0 && ny >= 0 && nx < p.width && ny < p.height
                        && !seen[ny * p.width + nx] && lit(nx, ny) {
                        seen[ny * p.width + nx] = true
                        stack.append((nx, ny))
                    }
                }
                found.append(region)
            }
        }
        return found
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theCopiesAreCountedExactly() throws {
        for count in [1, 5, 7, 12] {
            let p = try copies(.repeated(.ring(radius: 0.36), count: count, scale: 0.95, opacity: 1), size: 20)
            #expect(regions(p).count == count, "\(count) copies around a ring")
        }
        let grid = try copies(.repeated(.grid(columns: 4), count: 10, scale: 1, opacity: 1))
        #expect(regions(grid).count == 10, "ten copies in a grid four wide")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func eachCopyShrinksAndFadesByItsRatio() throws {
        let p = try copies(.repeated(.line(from: Vector2(0.15, 0.5), to: Vector2(0.85, 0.5)),
                                     count: 4, scale: 0.8, opacity: 0.7))
        let found = regions(p, threshold: 8).sorted { $0.map(\.0).min()! < $1.map(\.0).min()! }
        try #require(found.count == 4)
        // Each copy's width as the light summed along the row through its middle
        // over the light inside it, so the antialiased edges count by coverage.
        let widths = found.map { r -> Double in
            let ys = r.map(\.1), xs = r.map(\.0)
            let cy = (ys.min()! + ys.max()!) / 2, cx = (xs.min()! + xs.max()!) / 2
            let inside = linear(UInt8(p.channel(1, cx, cy)))
            let row = (xs.min()! - 2 ... xs.max()! + 2).reduce(0.0) { $0 + linear(UInt8(p.channel(1, $1, cy))) }
            return row / inside
        }
        for i in 1 ..< 4 {
            #expect(abs(widths[i] / widths[0] - pow(0.8, Double(i))) < 0.02, "copy \(i) is 0.8 to the power \(i) of the first: \(widths)")
        }
        // A white square over black: each copy's middle is its opacity in light.
        for (i, region) in found.enumerated() {
            let xs = region.map(\.0), ys = region.map(\.1)
            let cx = (xs.min()! + xs.max()!) / 2, cy = (ys.min()! + ys.max()!) / 2
            let light = linear(UInt8(p.channel(1, cx, cy)))
            #expect(abs(light - pow(0.7, Double(i))) < 0.02, "copy \(i) at opacity 0.7^\(i): \(light)")
        }
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func eachCopyTurnsItsHueByTheStep() throws {
        let base = Color(red: 0.62, green: 0.45, blue: 0.38)
        let step = 0.5
        let p = try copies(.repeated(.line(from: Vector2(0.15, 0.5), to: Vector2(0.85, 0.5)),
                                     count: 3, scale: 1, opacity: 1, hueShift: step), color: base)
        let found = regions(p, threshold: 8).sorted { $0.map(\.0).min()! < $1.map(\.0).min()! }
        try #require(found.count == 3)
        var hues: [Double] = []
        for region in found {
            let xs = region.map(\.0), ys = region.map(\.1)
            let cx = (xs.min()! + xs.max()!) / 2, cy = (ys.min()! + ys.max()!) / 2
            let c = Color(red: Double(p.channel(0, cx, cy)) / 255, green: Double(p.channel(1, cx, cy)) / 255,
                          blue: Double(p.channel(2, cx, cy)) / 255)
            let lab = OKLab(c)
            hues.append(atan2(lab.b, lab.a))
        }
        for i in 1 ..< 3 {
            var turn = hues[i] - hues[0]
            while turn < 0 { turn += 2 * .pi }
            #expect(abs(turn - step * Double(i)) < 0.05, "copy \(i) turned \(turn) of \(step * Double(i))")
        }
    }

    // MARK: Edge glow

    /// A white disc in the middle of a clear layer over a dark ground.
    final class Glowing: Sketch {
        var filter: Filter?
        override var canvasSize: CanvasSize { .square(WipesAndCopiesTests.side) }
        override func draw() {
            background(Color(white: 0.1))
            let mark = makeRenderTarget()
            withTarget(mark) { noStroke(); fill(Color(white: 0.5)); drawCircle(120, 120, 60) }
            drawImage((filter.map { mark.filtered($0) } ?? mark).image, 0, 0)
        }
    }

    private func glow(_ filter: Filter?) throws -> Pixels {
        let s = Glowing(); s.filter = filter
        let image = try OllinApp.image(of: s, frame: 1)
        Self.dump(image, "glow")
        return Pixels(image)
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func anEdgeGlowOfNoWidthOrNoColorIsTheLayer() throws {
        let plain = try glow(nil)
        #expect(try glow(.edgeGlow(width: 0)).bytes == plain.bytes)
        #expect(try glow(.edgeGlow(width: 20, colors: [])).bytes == plain.bytes)
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theGlowNeverDarkensAndLightsTheEdge() throws {
        let plain = try glow(nil)
        let lit = try glow(.edgeGlow(width: 14, colors: [.magenta, .cyan], spots: 3, phase: 0.4))
        var darker = 0
        for y in 0 ..< Self.side {
            for x in 0 ..< Self.side {
                for c in 0 ..< 3 where lit.channel(c, x, y) < plain.channel(c, x, y) - 1 { darker += 1 }
            }
        }
        #expect(darker == 0, "\(darker) channels went darker")
        // Around the rim (just outside the disc) the band is lit everywhere; far
        // outside it is the ground.
        var rim = 0.0, far = 0.0
        for k in 0 ..< 72 {
            let a = Double(k) / 72 * 2 * .pi
            let rx = Int(120 + 63 * cos(a)), ry = Int(120 + 63 * sin(a))
            let fx = Int(120 + 112 * cos(a)), fy = Int(120 + 112 * sin(a))
            rim += Double((0 ..< 3).map { lit.channel($0, rx, ry) - plain.channel($0, rx, ry) }.max()!)
            far += Double((0 ..< 3).map { lit.channel($0, fx, fy) - plain.channel($0, fx, fy) }.max()!)
        }
        #expect(rim / 72 > 30, "the rim is lit: \(rim / 72) levels")
        #expect(far / 72 < 2, "far outside is the ground: \(far / 72) levels")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theSpotsGoAQuarterTurnAUnitOfPhase() throws {
        func brightest(_ phase: Double) throws -> Double {
            // A dim color, so the spot's peak never clips into a flat top.
            let p = try glow(.edgeGlow(width: 10, colors: [Color(red: 0, green: 0.25, blue: 0.25)],
                                       spots: 1, spotSize: 0.04, phase: phase))
            var best = -1, angle = 0.0
            for k in 0 ..< 360 {
                let a = Double(k) / 360 * 2 * .pi
                let x = Int(120 + 66 * cos(a)), y = Int(120 + 66 * sin(a))
                let v = p.channel(1, x, y) + p.channel(2, x, y)
                if v > best { best = v; angle = Double(k) / 360 }
            }
            return angle
        }
        let start = try brightest(0), later = try brightest(1)
        var moved = later - start
        while moved < 0 { moved += 1 }
        #expect(abs(moved - 0.25) < 0.02, "a quarter turn clockwise: \(moved)")
    }
}
