import Foundation
import Testing
@testable import Ollin

/// The line textures, on the CPU: wood grain's strokes never cross and each
/// sits on one level of the ring coordinate, closing around a knot; a frost
/// needle's barbs follow the barb law and the needles stand on the outline
/// pointing the way asked; crackle veins stay inside their cell, never cross,
/// fork from a point on their parent, and crowd along a crease; an ikat edge
/// steps once per bundle and is the band itself when nothing bled; every
/// emitter repeats from its seed; and all four come back from the SVG a
/// sketch writes.
@Suite struct LineTextureTests {

    static let region = Rectangle(x: 0, y: 0, width: 300, height: 200)

    /// Whether two segments cross strictly (a shared endpoint is not a cross).
    static func cross(_ a: Vector2, _ b: Vector2, _ c: Vector2, _ d: Vector2) -> Bool {
        let r = b - a, s = d - c
        let denominator = r.cross(s)
        guard abs(denominator) > 1e-12 else { return false }
        let t = (c - a).cross(s) / denominator
        let u = (c - a).cross(r) / denominator
        let eps = 1e-6
        return t > eps && t < 1 - eps && u > eps && u < 1 - eps
    }

    /// How many pairs of segments cross among `lines`, segments of one line
    /// that share a point excluded.
    static func crossings(in lines: [[Vector2]]) -> Int {
        var segments: [(Vector2, Vector2, Int)] = []
        for (i, line) in lines.enumerated() where line.count > 1 {
            for j in 1 ..< line.count { segments.append((line[j - 1], line[j], i)) }
        }
        var count = 0
        for i in 0 ..< segments.count {
            let (a, b, la) = segments[i]
            let box = LineSegment(a, b).bounds
            for j in (i + 1) ..< segments.count {
                let (c, d, lb) = segments[j]
                if la == lb && (a == d || b == c) { continue }
                let other = LineSegment(c, d).bounds
                if box.x + box.width < other.x || other.x + other.width < box.x
                    || box.y + box.height < other.y || other.y + other.height < box.y { continue }
                if cross(a, b, c, d) { count += 1 }
            }
        }
        return count
    }

    // MARK: Wood grain

    /// The strokes are evenly spaced streamlines, so no two ever cross, and
    /// the region fills: strokes cover its height.
    @Test func woodGrainStrokesNeverCross() {
        let grain = WoodGrain.trace(in: Self.region, spacing: 10, knots: 1, seed: 3)
        #expect(grain.strokes.count >= 12, "\(grain.strokes.count) strokes")
        #expect(Self.crossings(in: grain.lines) == 0)
        let ys = grain.strokes.flatMap { $0.points.map(\.y) }
        #expect(ys.min()! < 15 && ys.max()! > 185, "the strokes do not span the region")
        for stroke in grain.strokes {
            for p in stroke.points { #expect(Self.region.contains(p)) }
        }
    }

    /// Every stroke is a level curve of the ring coordinate: `across` reads
    /// the same along its whole length, and its tone is the tone there.
    @Test func aStrokeSitsOnOneLevel() {
        let grain = WoodGrain.trace(in: Self.region, direction: 0.2, spacing: 8, knots: 2, seed: 5)
        for stroke in grain.strokes {
            let level = grain.across(stroke.points[0])
            for p in stroke.points {
                #expect(abs(grain.across(p) - level) < grain.ringSpacing * 0.01, "a stroke left its level")
            }
            // The stroke's tone is read at its seed, so a point a hundredth
            // of a ring off its level reads within a few hundredths of it.
            #expect(abs(grain.tone(at: stroke.points[0]) - stroke.tone) < 0.05)
            #expect(stroke.tone >= 0 && stroke.tone <= 1)
        }
    }

    /// A knot high enough closes rings around itself: some strokes close,
    /// each circles the knot (its centroid within a radius of the knot's
    /// center, which the grain's own slope shifts the rings' center off),
    /// and with no knot none closes.
    @Test func ringsCloseAroundAKnot() {
        let knot = WoodGrain.Knot(center: Vector2(150, 100), radius: 28, height: 4)
        let grain = WoodGrain.trace(in: Self.region, spacing: 6, knots: [knot], wobble: 0, seed: 1)
        let closed = grain.strokes.filter(\.isClosed)
        #expect(closed.count >= 3, "\(closed.count) closed strokes")
        for ring in closed {
            let centroid = ring.points.reduce(.zero, +) / Double(ring.points.count)
            #expect(centroid.distance(to: knot.center) < knot.radius, "a ring that does not circle the knot")
            #expect(Self.region.contains(centroid))
        }
        let plain = WoodGrain.trace(in: Self.region, spacing: 6, knots: [], wobble: 0, seed: 1)
        #expect(plain.strokes.allSatisfy { !$0.isClosed })
        #expect(WoodGrain.Knot.closingHeight > 1.6 && WoodGrain.Knot.closingHeight < 1.7)
    }

    /// The rings show as density: on a dark ring the strokes sit closer than
    /// on the light wood between rings.
    @Test func strokesCrowdOnTheRings() {
        let grain = WoodGrain.trace(in: Rectangle(x: 0, y: 0, width: 200, height: 300), spacing: 6, knots: [],
                                    ringSpacing: 60, ringContrast: 1, wobble: 0, seed: 2)
        // With no wobble and no knot the strokes are horizontal lines: read
        // each one's y and tone, sort by y, and compare the gaps.
        let rows = grain.strokes.map { (y: $0.points[0].y, tone: $0.tone) }.sorted { $0.y < $1.y }
        var darkGaps: [Double] = [], lightGaps: [Double] = []
        for i in 1 ..< rows.count {
            let gap = rows[i].y - rows[i - 1].y
            let tone = (rows[i].tone + rows[i - 1].tone) / 2
            if tone > 0.7 { darkGaps.append(gap) } else if tone < 0.1 { lightGaps.append(gap) }
        }
        #expect(darkGaps.count >= 3 && lightGaps.count >= 3)
        let dark = darkGaps.reduce(0, +) / Double(darkGaps.count)
        let light = lightGaps.reduce(0, +) / Double(lightGaps.count)
        #expect(light > dark * 1.8, "light gaps \(light) against dark gaps \(dark)")
    }

    @Test func woodGrainRepeatsFromItsSeed() {
        let a = WoodGrain.trace(in: Self.region, spacing: 7, knots: 2, seed: 9)
        let b = WoodGrain.trace(in: Self.region, spacing: 7, knots: 2, seed: 9)
        let c = WoodGrain.trace(in: Self.region, spacing: 7, knots: 2, seed: 10)
        #expect(a == b)
        #expect(a != c)
        #expect(WoodGrain.Knot.scatter(in: Self.region, count: 3, seed: 4) == WoodGrain.Knot.scatter(in: Self.region, count: 3, seed: 4))
    }

    // MARK: Frost

    /// Every needle's barbs follow the barb law: a pair at every station the
    /// law names, leaning forward on both sides, shorter toward the tip and
    /// never past the cap.
    @Test func barbsFollowTheBarbLaw() {
        let outline = Circle(center: Vector2(150, 100), radius: 60).contour
        let frost = Frost.grow(along: outline, spacing: 8, length: 50, barbSpacing: 5, seed: 3)
        #expect(frost.needles.count >= 40)
        var withBarbs = 0
        for needle in frost.needles {
            let stations = Frost.barbStations(length: needle.length, spacing: 5)
            #expect(needle.barbs.count == stations.count * 2, "\(needle.barbs.count) barbs for \(stations.count) stations")
            let axis = Vector2(angle: needle.angle)
            var previous = Double.infinity
            for (k, station) in stations.enumerated() {
                let pair = Array(needle.barbs[(k * 2) ..< (k * 2 + 2)])
                #expect(pair[0].side == 1 && pair[1].side == -1)
                for barb in pair {
                    #expect(barb.base.distance(to: needle.root + axis * station) < 1e-9)
                    #expect(abs(barb.station - station / needle.length) < 1e-9)
                    let cap = min(needle.length * Frost.barbReach, 5 * Frost.barbCap) * (1 - barb.station)
                    #expect(barb.length <= cap + 1e-9 && barb.length >= cap * 0.8 - 1e-9)
                    // Leaning forward: the barb's tip is farther along the spine than its base.
                    #expect((barb.tip - barb.base).dot(axis) > 0)
                }
                let longest = max(pair[0].length, pair[1].length)
                #expect(longest <= previous / 0.8 + 1e-9)
                previous = longest
            }
            if !needle.barbs.isEmpty { withBarbs += 1 }
        }
        #expect(withBarbs > frost.needles.count / 2)
    }

    /// The needles stand on the outline, `spacing` apart, and point the way
    /// asked: out of a closed outline, into it, or both.
    @Test func needlesStandOnTheOutlineAndPointOut() {
        let circle = Circle(center: Vector2(150, 100), radius: 60)
        let outline = circle.contour
        let out = Frost.grow(along: outline, spacing: 8, length: 30, side: .outside, seed: 1)
        for needle in out.needles {
            #expect(abs(needle.root.distance(to: circle.center) - 60) < 0.5, "a root off the circle")
            #expect(!circle.contains(needle.root + Vector2(angle: needle.angle, length: 3)), "a needle pointing in")
            #expect(needle.length >= 30 * 0.15 - 1e-9 && needle.length <= 30 + 1e-9)
        }
        let roots = out.roots
        for i in 1 ..< roots.count {
            #expect(abs(roots[i].distance(to: roots[i - 1]) - 8) < 0.6)
        }
        let within = Frost.grow(along: outline, spacing: 8, length: 30, side: .inside, seed: 1)
        for needle in within.needles {
            #expect(circle.contains(needle.root + Vector2(angle: needle.angle, length: 3)), "a needle pointing out")
        }
        let both = Frost.grow(along: outline, spacing: 8, length: 30, side: .both, seed: 1)
        #expect(both.needles.count == out.needles.count * 2)
        // A shape grows along every contour, out of the shape as a whole.
        let ring = Shape(contours: [outline, Circle(center: circle.center, radius: 30).contour])
        let shaped = Frost.grow(along: ring, spacing: 8, length: 10, seed: 1)
        #expect(shaped.needles.count > out.needles.count)
        for needle in shaped.needles {
            #expect(!ring.contains(needle.root + Vector2(angle: needle.angle, length: 2)))
        }
    }

    @Test func frostRepeatsFromItsSeed() {
        let outline = Circle(center: Vector2(150, 100), radius: 60).contour
        let a = Frost.grow(along: outline, seed: 7), b = Frost.grow(along: outline, seed: 7)
        let c = Frost.grow(along: outline, seed: 8)
        #expect(a == b)
        #expect(a != c)
        #expect(a.strokes.count == a.needles.reduce(0) { $0 + 1 + $1.barbs.count })
    }

    // MARK: Crackle

    /// Every point of every vein lies inside the cell, veins never cross, and
    /// a vein ends on the rim or on another vein.
    @Test func veinsStayInsideTheCellAndNeverCross() {
        let cell = Shape(Circle(center: Vector2(150, 100), radius: 90).contour.points)
        let crackle = Crackle.grow(in: cell, spacing: 24, seed: 4)
        #expect(crackle.veins.count >= 10, "\(crackle.veins.count) veins")
        let inner = Circle(center: Vector2(150, 100), radius: 90 + 1e-6)
        for vein in crackle.veins {
            #expect(vein.points.count >= 3)
            for p in vein.points { #expect(inner.contains(p), "a vein point outside the cell") }
        }
        #expect(Self.crossings(in: crackle.lines) == 0)
        // Over a rectangle too, with the convenience form.
        let boxed = Crackle.grow(in: Self.region, spacing: 30, seed: 2)
        for vein in boxed.veins {
            for p in vein.points { #expect(Self.region.contains(p)) }
        }
        #expect(Self.crossings(in: boxed.lines) == 0)
    }

    /// A fork starts on a point of its parent, between a third and two
    /// thirds along it, and no vein is deeper than `maxOrder`.
    @Test func forksLeaveTheirParentNearItsMiddle() {
        let crackle = Crackle.grow(in: Self.region, spacing: 20, forkChance: 1, seed: 6)
        let forks = crackle.veins.filter { $0.parent != nil }
        #expect(forks.count >= 5, "\(forks.count) forks")
        for fork in forks {
            let parent = crackle.veins[fork.parent!]
            #expect(fork.order == parent.order + 1)
            #expect(fork.order <= Crackle.maxOrder)
            let at = parent.points.firstIndex(of: fork.points[0])
            #expect(at != nil, "a fork that does not start on its parent")
            if let at {
                let t = Double(at) / Double(parent.points.count - 1)
                #expect(t >= 0.3 && t <= 0.7, "a fork at \(t) along its parent (\(at) of \(parent.points.count), order \(parent.order), both \(parent.points.count))")
            }
        }
        let never = Crackle.grow(in: Self.region, spacing: 20, forkChance: 0, seed: 6)
        #expect(never.veins.allSatisfy { $0.parent == nil && $0.order == 0 })
    }

    /// Veins crowd along a crease: more vein points within a spacing of the
    /// crease line than of a line the same length elsewhere.
    @Test func veinsCrowdAlongACrease() {
        let crease: [Vector2] = [Vector2(20, 60), Vector2(280, 60)]
        let crackle = Crackle.grow(in: Self.region, spacing: 30, creases: [crease], seed: 3)
        func near(_ y: Double) -> Int {
            crackle.veins.reduce(0) { $0 + $1.points.filter { abs($0.y - y) < 15 && $0.x > 20 && $0.x < 280 }.count }
        }
        #expect(near(60) > near(140) * 3 / 2, "\(near(60)) points by the crease against \(near(140)) away from it")
        for vein in crackle.veins { for p in vein.points { #expect(Self.region.contains(p)) } }
    }

    @Test func crackleRepeatsFromItsSeed() {
        let a = Crackle.grow(in: Self.region, spacing: 25, seed: 11)
        let b = Crackle.grow(in: Self.region, spacing: 25, seed: 11)
        let c = Crackle.grow(in: Self.region, spacing: 25, seed: 12)
        #expect(a == b)
        #expect(a != c)
    }

    // MARK: Ikat

    /// Each edge is a stair: two points per bundle at one height along the
    /// warp, the risers between them straight across, one bundle per bundle
    /// width of the band.
    @Test func anIkatEdgeStepsOncePerBundle() {
        let band = Rectangle(x: 10, y: 50, width: 250, height: 60)
        let stripe = Ikat.stripe(across: band, bundle: 12, bleed: 20, seed: 2)
        #expect(stripe.bundles == 21)
        for edge in stripe.edges {
            #expect(edge.count == stripe.bundles * 2)
            for b in 0 ..< stripe.bundles {
                #expect(edge[2 * b].y == edge[2 * b + 1].y, "a tread that is not level")
                #expect(abs(edge[2 * b].x - (10 + Double(b) * 12)) < 1e-9)
                #expect(abs(edge[2 * b + 1].x - min(10 + Double(b + 1) * 12, 260)) < 1e-9)
                if b > 0 { #expect(edge[2 * b].x == edge[2 * b - 1].x, "a riser that leans") }
            }
        }
        for b in 0 ..< stripe.bundles {
            #expect(stripe.trailingEdge[2 * b].y > stripe.leadingEdge[2 * b].y, "a bundle pinched shut")
        }
        #expect(stripe.shape.contours.count == 1 && stripe.shape.contours[0].points.count == stripe.bundles * 4)
        // A horizontal warp swaps the axes.
        let sideways = Ikat.stripe(across: Rectangle(x: 50, y: 10, width: 60, height: 250), bundle: 12, bleed: 20,
                                   warp: .horizontal, seed: 2)
        for edge in sideways.edges {
            for b in 0 ..< sideways.bundles { #expect(edge[2 * b].x == edge[2 * b + 1].x) }
        }
    }

    /// With nothing bled and no skew the stripe is the band itself, and with
    /// only a flare every offset stays within half a bleed.
    @Test func anUnbledStripeIsItsBand() {
        let band = Rectangle(x: 10, y: 50, width: 240, height: 60)
        let crisp = Ikat.stripe(across: band, bundle: 12, bleed: 0, skew: 0, seed: 5)
        #expect(crisp.leading.allSatisfy { $0 == 0 } && crisp.trailing.allSatisfy { $0 == 0 })
        #expect(abs(crisp.shape.area - band.area) < 1e-6)
        let flared = Ikat.stripe(across: band, bundle: 12, bleed: 20, spikes: 0, intrusions: 0, skew: 0, seed: 5)
        for offset in flared.leading + flared.trailing {
            // A slip of up to 0.35 and a flare of up to 0.5 of the bleed.
            #expect(abs(offset) <= 20 * 0.85 + 1e-9)
        }
        #expect(flared.leading.contains { $0 != 0 })
    }

    @Test func ikatRepeatsFromItsSeed() {
        let region = Rectangle(x: 0, y: 0, width: 300, height: 300)
        let a = Ikat.stripes(in: region, count: 4, seed: 3), b = Ikat.stripes(in: region, count: 4, seed: 3)
        let c = Ikat.stripes(in: region, count: 4, seed: 4)
        #expect(a == b)
        #expect(a != c)
        #expect(a.stripes.count == 4 && a.shapes.count == 4 && a.edges.count == 8)
        for (i, stripe) in a.stripes.enumerated() {
            #expect(abs(stripe.band.y - (75 * Double(i) + 18.75)) < 1e-9 && abs(stripe.band.height - 37.5) < 1e-9)
        }
    }

    // MARK: SVG

    /// The strokes a sketch draws from all four come back from the SVG it
    /// writes, one path each, so a plotter gets exactly the geometry.
    @Test @MainActor func theLinesRoundTripThroughSVG() throws {
        final class Plate: Sketch {
            let canvas = Rectangle(x: 0, y: 0, width: 240, height: 240)
            lazy var grain = WoodGrain.trace(in: Rectangle(x: 10, y: 10, width: 100, height: 100), spacing: 9, knots: 1, seed: 1)
            lazy var frost = Frost.grow(along: Circle(center: Vector2(170, 60), radius: 30).contour, spacing: 9, length: 16, seed: 1)
            lazy var crackle = Crackle.grow(in: Rectangle(x: 10, y: 130, width: 100, height: 100), spacing: 30, seed: 1)
            lazy var ikat = Ikat.stripes(in: Rectangle(x: 130, y: 130, width: 100, height: 100), count: 2, bundle: 10, seed: 1)
            var lines: [[Vector2]] { grain.lines + frost.strokes + crackle.lines + ikat.edges }
            override var canvasSize: CanvasSize { .square(240) }
            override func draw() {
                background(.white)
                stroke(.black); strokeWeight(1); noFill()
                for line in lines { drawPolyline(line) }
            }
        }
        let sketch = Plate()
        let text = try OllinApp.svg(of: sketch)
        let parsed = try SVG(data: Data(text.utf8))
        let drawn = sketch.lines
        #expect(drawn.count > 40)
        // One path per line, plus the background's rectangle.
        #expect(parsed.contours.count == drawn.count + 1, "\(parsed.contours.count) paths for \(drawn.count) lines")
        var missing = 0
        for line in drawn {
            let found = parsed.contours.contains { c in
                c.points.count == line.count && zip(c.points, line).allSatisfy { $0.distance(to: $1) < 0.01 }
            }
            if !found { missing += 1 }
        }
        #expect(missing == 0, "\(missing) lines did not come back")
    }
}
