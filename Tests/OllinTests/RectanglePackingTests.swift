import Testing
import Foundation
import Ollin

/// The rectangle packer, pinned by what it promises: a packing never
/// overlaps and never leaves its bin, keeps every size, accounts for every
/// rectangle once, places what a plain global search places, places a
/// known set in its known arrangement, weighs every waiting rectangle
/// rather than the next in the list, turns a
/// rectangle only when allowed, leaves the gap between neighbors and not at
/// the edges, and never places a size with no area.
@Suite
struct RectanglePackingTests {

    /// Seeded sizes between `low` and `high` on each side.
    static func sizes(seed: Int, count: Int, low: Double, high: Double) -> [Vector2] {
        var rng = SplitMix64(seed: UInt64(seed))
        return (0 ..< count).map { _ in
            Vector2(Double.random(in: low ... high, using: &rng), Double.random(in: low ... high, using: &rng))
        }
    }

    /// Every promise a packing makes about its own result.
    static func check(_ packing: RectanglePacking, sizes: [Vector2], padding: Double, rotation: Bool) {
        let bin = packing.bin
        let slack = 1e-9
        // Every rectangle once, placed or not.
        let indices = packing.placed.map(\.index) + packing.unplaced
        #expect(indices.sorted() == Array(sizes.indices))
        #expect(packing.placed.map(\.index) == packing.placed.map(\.index).sorted())
        for place in packing.placed {
            let r = place.rectangle, s = sizes[place.index]
            // Its own size, or turned when that is allowed.
            if place.isRotated {
                #expect(rotation)
                #expect(r.width == s.y && r.height == s.x)
            } else {
                #expect(r.width == s.x && r.height == s.y)
            }
            // Inside the bin.
            #expect(r.x >= bin.x - slack && r.y >= bin.y - slack)
            #expect(r.x + r.width <= bin.x + bin.width + slack)
            #expect(r.y + r.height <= bin.y + bin.height + slack)
        }
        // No two overlap, and neighbors keep the gap.
        let rects = packing.placed.map(\.rectangle)
        for i in rects.indices {
            for j in rects.indices where j > i {
                let a = rects[i], b = rects[j]
                let gapX = Swift.max(b.x - (a.x + a.width), a.x - (b.x + b.width))
                let gapY = Swift.max(b.y - (a.y + a.height), a.y - (b.y + b.height))
                #expect(Swift.max(gapX, gapY) >= padding - slack,
                        "rectangles \(packing.placed[i].index) and \(packing.placed[j].index) are \(Swift.max(gapX, gapY)) apart")
            }
        }
        let area = rects.reduce(0) { $0 + $1.width * $1.height }
        #expect(abs(packing.occupancy - area / (bin.width * bin.height)) < 1e-12)
    }

    @Test func aPackingNeverOverlapsAndNeverLeavesItsBin() {
        let bin = Rectangle(x: 30, y: -20, width: 1000, height: 700)
        for seed in 1 ... 8 {
            let sizes = Self.sizes(seed: seed, count: 60, low: 20, high: 260)
            for rotation in [false, true] {
                for padding in [0.0, 7.5] {
                    let packing = packRectangles(sizes, in: bin, padding: padding, allowsRotation: rotation)
                    Self.check(packing, sizes: sizes, padding: padding, rotation: rotation)
                    #expect(!packing.placed.isEmpty && !packing.unplaced.isEmpty)
                    // The same input always lands the same way.
                    #expect(packRectangles(sizes, in: bin, padding: padding, allowsRotation: rotation) == packing)
                }
            }
        }
    }

    @Test func theRememberedFitsPlaceExactlyWhatThePlainSearchPlaces() {
        // The packer keeps each rectangle's best fit between steps and
        // weighs it again only when its region is cut. The plain search
        // below weighs every rectangle against every free rectangle at
        // every step and prunes the whole list; both must place every
        // rectangle in the same place.
        for trial in 0 ..< 24 {
            let sizes = Self.sizes(seed: 500 + trial, count: 20 + trial * 4, low: 5, high: 65)
            let side = (Double(sizes.count) * 35 * 35 / 0.9).squareRoot()
            let bin = Rectangle(x: 3, y: -7, width: side, height: side * 0.8)
            let padding = trial % 3 == 0 ? 0 : Double(trial % 5) * 0.75
            let rotation = trial.isMultiple(of: 2)
            let packing = packRectangles(sizes, in: bin, padding: padding, allowsRotation: rotation)
            let plain = Self.plainSearch(sizes, in: bin, padding: padding, rotation: rotation)
            #expect(packing.placed.map(\.index) == plain.map(\.index), "trial \(trial)")
            #expect(packing.placed.map(\.rectangle) == plain.map(\.rectangle), "trial \(trial)")
        }
    }

    /// The global best-short-side-fit search written plainly, as the oracle:
    /// ties by the long side, then the earlier size, then the higher and
    /// further-left place, then upright.
    static func plainSearch(_ sizes: [Vector2], in bin: Rectangle, padding gap: Double,
                            rotation: Bool) -> [(index: Int, rectangle: Rectangle)] {
        typealias Free = (x: Double, y: Double, w: Double, h: Double)
        func inside(_ c: Free, _ a: Free) -> Bool {
            let slack = 1e-9 * Swift.max(1, Swift.max(a.w, a.h))
            return c.x >= a.x - slack && c.y >= a.y - slack
                && c.x + c.w <= a.x + a.w + slack && c.y + c.h <= a.y + a.h + slack
        }
        var free: [Free] = [(bin.x, bin.y, bin.width + gap, bin.height + gap)]
        var waiting = Array(sizes.indices)
        var out: [(index: Int, rectangle: Rectangle)] = []
        while true {
            var best: (s: Double, l: Double, i: Int, y: Double, x: Double, r: Bool)? = nil
            for i in waiting {
                let w0 = sizes[i].x + gap, h0 = sizes[i].y + gap
                for f in free {
                    for r in rotation && w0 != h0 ? [false, true] : [false] {
                        let (w, h) = r ? (h0, w0) : (w0, h0)
                        let slack = 1e-9 * Swift.max(1, Swift.max(f.w, f.h))
                        guard w <= f.w + slack, h <= f.h + slack else { continue }
                        let dx = Swift.max(f.w - w, 0), dy = Swift.max(f.h - h, 0)
                        let c = (s: Swift.min(dx, dy), l: Swift.max(dx, dy), i: i, y: f.y, x: f.x, r: r)
                        if let b = best {
                            let better = c.s != b.s ? c.s < b.s : c.l != b.l ? c.l < b.l : c.i != b.i ? c.i < b.i
                                : c.y != b.y ? c.y < b.y : c.x != b.x ? c.x < b.x : (!c.r && b.r)
                            if !better { continue }
                        }
                        best = c
                    }
                }
            }
            guard let b = best else { break }
            waiting.removeAll { $0 == b.i }
            let (pw, ph) = b.r ? (sizes[b.i].y, sizes[b.i].x) : (sizes[b.i].x, sizes[b.i].y)
            let u: Free = (b.x, b.y, pw + gap, ph + gap)
            out.append((b.i, Rectangle(x: b.x, y: b.y, width: pw, height: ph)))
            var next: [Free] = []
            for f in free {
                guard u.x < f.x + f.w, u.x + u.w > f.x, u.y < f.y + f.h, u.y + u.h > f.y else {
                    next.append(f)
                    continue
                }
                if u.y > f.y { next.append((f.x, f.y, f.w, u.y - f.y)) }
                if u.y + u.h < f.y + f.h { next.append((f.x, u.y + u.h, f.w, f.y + f.h - (u.y + u.h))) }
                if u.x > f.x { next.append((f.x, f.y, u.x - f.x, f.h)) }
                if u.x + u.w < f.x + f.w { next.append((u.x + u.w, f.y, f.x + f.w - (u.x + u.w), f.h)) }
            }
            next.removeAll { $0.w <= 1e-9 || $0.h <= 1e-9 }
            var keep = [Bool](repeating: true, count: next.count)
            for i in next.indices where keep[i] {
                for j in next.indices where j != i && keep[j] {
                    let equal = next[i] == next[j]
                    if inside(next[i], next[j]) && (!equal || j < i) {
                        keep[i] = false
                        break
                    }
                }
            }
            free = next.indices.filter { keep[$0] }.map { next[$0] }
        }
        return out.sorted { $0.index < $1.index }
    }

    @Test func aKnownSetLandsInItsKnownArrangement() {
        // Four rectangles that tile the bin exactly, given in an order that
        // is not the order they tile in.
        let sizes = [Vector2(40, 40), Vector2(60, 40), Vector2(40, 60), Vector2(60, 60)]
        let packing = packRectangles(sizes, in: Rectangle(x: 0, y: 0, width: 100, height: 100))
        #expect(packing.unplaced.isEmpty)
        #expect(packing.placed.map(\.rectangle) == [
            Rectangle(x: 60, y: 60, width: 40, height: 40),
            Rectangle(x: 0, y: 60, width: 60, height: 40),
            Rectangle(x: 60, y: 0, width: 40, height: 60),
            Rectangle(x: 0, y: 0, width: 60, height: 60),
        ])
        #expect(packing.occupancy == 1)
        // A grid of equal squares that exactly fills the bin fills it.
        let squares = Array(repeating: Vector2(25, 25), count: 16)
        let grid = packRectangles(squares, in: Rectangle(x: 0, y: 0, width: 100, height: 100))
        #expect(grid.unplaced.isEmpty && grid.occupancy == 1)
        #expect(Set(grid.placed.map { "\($0.rectangle.x),\($0.rectangle.y)" }).count == 16)
    }

    @Test func theSnuggestFitIsPlacedFirstWhereverItIsInTheList() {
        // The strip fills the bin's width exactly, so it goes first, into
        // the top-left corner, although it is listed last.
        let packing = packRectangles([Vector2(10, 10), Vector2(30, 30), Vector2(100, 20)],
                                     in: Rectangle(x: 0, y: 0, width: 100, height: 100))
        #expect(packing.placed[2].rectangle.corner == Vector2(0, 0))
        // The strip taken alone in the order given would have had to go
        // below the others; here they sit on it.
        #expect(packing.placed[0].rectangle.y >= 20 && packing.placed[1].rectangle.y >= 20)
    }

    @Test func rotationLetsATallRectangleIntoAWideBin() {
        let bin = Rectangle(x: 0, y: 0, width: 100, height: 40)
        let tall = [Vector2(30, 90)]
        let upright = packRectangles(tall, in: bin)
        #expect(upright.placed.isEmpty && upright.unplaced == [0])
        let turned = packRectangles(tall, in: bin, allowsRotation: true)
        #expect(turned.unplaced.isEmpty)
        #expect(turned.placed[0].isRotated)
        #expect(turned.placed[0].rectangle == Rectangle(x: 0, y: 0, width: 90, height: 30))
        // A square is never turned, and neither is a rectangle that fits
        // as well upright.
        let packing = packRectangles([Vector2(20, 20), Vector2(100, 10)], in: bin, allowsRotation: true)
        #expect(packing.placed.allSatisfy { !$0.isRotated })
    }

    @Test func paddingIsBetweenNeighborsAndNotAtTheEdges() {
        let bin = Rectangle(x: 0, y: 0, width: 100, height: 30)
        // Two 47s and a gap of 6 make exactly 100: both fit, touching the
        // bin's two sides.
        let two = packRectangles([Vector2(47, 30), Vector2(47, 30)], in: bin, padding: 6)
        #expect(two.unplaced.isEmpty)
        let xs = two.placed.map(\.rectangle.x).sorted()
        #expect(xs == [0, 53])
        // Three 30s need 102 with their gaps, so one waits.
        let three = packRectangles(Array(repeating: Vector2(30, 30), count: 3), in: bin, padding: 6)
        #expect(three.placed.count == 2 && three.unplaced == [2])
        // Without the gap all three fit.
        #expect(packRectangles(Array(repeating: Vector2(30, 30), count: 3), in: bin).unplaced.isEmpty)
    }

    @Test func aSizeWithNoAreaIsNeverPlaced() {
        let bin = Rectangle(x: 0, y: 0, width: 100, height: 100)
        let sizes = [Vector2(10, 10), Vector2(0, 10), Vector2(10, -5), Vector2(.nan, 10),
                     Vector2(10, .infinity), Vector2(20, 20)]
        let packing = packRectangles(sizes, in: bin, padding: .nan, allowsRotation: true)
        #expect(packing.placed.map(\.index) == [0, 5])
        #expect(packing.unplaced == [1, 2, 3, 4])
        // A bin with no area places nothing, and says so for every size.
        let none = packRectangles(sizes, in: Rectangle(x: 0, y: 0, width: 0, height: 100))
        #expect(none.placed.isEmpty && none.unplaced == Array(sizes.indices))
        #expect(none.occupancy == 0)
        // Nothing to pack is an empty packing.
        #expect(packRectangles([], in: bin).placed.isEmpty)
    }
}
