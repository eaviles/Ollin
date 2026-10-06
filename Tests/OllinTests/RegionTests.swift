import Testing
import Foundation
import Ollin

/// The regions a drawing encloses, pinned by what must hold whatever the
/// arrangement does: the regions' areas sum to the union of the closed
/// outlines, no two overlap, every region boundary lies on the input, a grid
/// of lines gives exactly its cells, a region inside another is a hole in it,
/// loose ends wall nothing off, and the same drawing gives the same regions
/// in the same order. No GPU.
@Suite struct RegionTests {

    /// A region's area read straight off its outline, the first contour
    /// less its holes, so a region with a hole measures exactly rather than
    /// through the boolean library, which rounds at about a ten-thousandth.
    private func exactArea(_ region: Shape) -> Double {
        region.contours.enumerated().reduce(0) { $0 + ($1.offset == 0 ? 1 : -1) * abs(shoelace($1.element.points)) }
    }

    /// The sum of a region list's areas.
    private func totalArea(_ regions: [Shape]) -> Double {
        regions.reduce(0) { $0 + exactArea($1) }
    }

    /// What a comparison against the boolean library may be off by: it
    /// works on rounded coordinates, so a union's area carries about a
    /// ten-thousandth of error.
    private let booleanSlack = 1e-2

    /// The union of a set of closed outlines, through the shape booleans.
    private func union(of contours: [Contour]) -> Shape {
        contours.filter(\.isClosed).reduce(Shape(contours: [])) { $0.union(Shape(contours: [$1])) }
    }

    /// The area a union's outer boundaries enclose, its holes filled in: a
    /// patch of page ringed by outlines is walled off too, so the regions
    /// cover the union and every hole in it.
    private func enclosedArea(_ contours: [Contour]) -> Double {
        union(of: contours).separated().reduce(0) { $0 + abs(shoelace($1.contours[0].points)) }
    }

    private func shoelace(_ points: [Vector2]) -> Double {
        var sum = 0.0
        for i in points.indices {
            let a = points[i], b = points[(i + 1) % points.count]
            sum += a.x * b.y - b.x * a.y
        }
        return sum / 2
    }

    /// The largest area any two regions share.
    private func largestOverlap(_ regions: [Shape]) -> Double {
        var worst = 0.0
        for i in regions.indices {
            for j in regions.indices where j > i {
                worst = max(worst, regions[i].intersection(regions[j]).area)
            }
        }
        return worst
    }

    /// How far the farthest vertex or edge midpoint of any region's outline
    /// is from the nearest input line.
    private func farthestFromInput(_ regions: [Shape], _ input: [Contour]) -> Double {
        var worst = 0.0
        for region in regions {
            for contour in region.contours {
                let points = contour.points
                for i in points.indices {
                    let a = points[i], b = points[(i + 1) % points.count]
                    for probe in [a, (a + b) / 2] {
                        let near = input.map { $0.distance(to: probe) }.min() ?? .infinity
                        worst = max(worst, near)
                    }
                }
            }
        }
        return worst
    }

    private func line(_ a: Vector2, _ b: Vector2) -> Contour { Contour([a, b], closed: false) }

    // MARK: A grid of lines

    @Test func aGridOfLinesGivesExactlyItsCells() {
        var lines: [Contour] = []
        for row in 0 ... 4 { lines.append(line(Vector2(0, Double(row) * 100), Vector2(500, Double(row) * 100))) }
        for column in 0 ... 5 { lines.append(line(Vector2(Double(column) * 100, 0), Vector2(Double(column) * 100, 400))) }
        let cells = regions(enclosedBy: lines)
        #expect(cells.count == 20)
        for cell in cells {
            #expect(cell.contours.count == 1)
            #expect(cell.contours[0].points.count == 4)
            #expect(abs(cell.area - 10_000) < 1e-6)
        }
        // Reading order: the first cell is the top-left one, the last the
        // bottom-right one, and the rows run left to right.
        #expect(cells[0].bounds?.topLeft == Vector2(0, 0))
        #expect(cells[4].bounds?.topLeft == Vector2(400, 0))
        #expect(cells[19].bounds?.topLeft == Vector2(400, 300))
        #expect(abs(totalArea(cells) - 500 * 400) < 1e-6)
    }

    // MARK: Overlapping circles

    @Test func twoCirclesGiveThreeRegionsAndThreeGiveSeven() {
        let a = Circle(center: Vector2(300, 300), radius: 200).contour()
        let b = Circle(center: Vector2(500, 300), radius: 200).contour()
        let c = Circle(center: Vector2(400, 470), radius: 200).contour()
        #expect(regions(enclosedBy: [a, b]).count == 3)
        #expect(regions(enclosedBy: [a, b, c]).count == 7)
    }

    @Test func regionAreasSumToTheUnionAndNeverOverlap() {
        var rng = SplitMix64(seed: 11)
        var outlines: [Contour] = []
        for _ in 0 ..< 7 {
            let center = Vector2(Double.random(in: 200 ... 800, using: &rng),
                                 Double.random(in: 200 ... 800, using: &rng))
            outlines.append(Circle(center: center, radius: Double.random(in: 90 ... 260, using: &rng)).contour())
        }
        outlines.append(Rectangle(x: 150, y: 400, width: 700, height: 180).contour)
        let found = regions(enclosedBy: outlines)
        let covered = union(of: outlines)
        let enclosed = enclosedArea(outlines)
        #expect(found.count > 20)
        #expect(abs(totalArea(found) - enclosed) < booleanSlack)
        #expect(largestOverlap(found) < booleanSlack)
        #expect(farthestFromInput(found, outlines) < 1e-6)
        // This drawing rings one patch of bare page with circles: the union
        // has a hole, and that hole is a region like any other.
        #expect(covered.contours.count == 2)
        #expect(enclosed - covered.area > 100)
    }

    @Test func aPatchOfPageRingedByOutlinesIsARegion() {
        // Three circles at the corners of a triangle, each pair overlapping,
        // the middle left bare: three crescents, three lenses, and the gap.
        let side = 190.0
        let corners = (0 ..< 3).map { i in
            Vector2(400, 400) + Vector2(angle: Double(i) / 3 * .tau - .tau / 4, length: side / 3.0.squareRoot())
        }
        let discs = corners.map { Circle(center: $0, radius: 100).contour() }
        let found = regions(enclosedBy: discs)
        #expect(found.count == 7)
        let gap = found.first { $0.contains(Vector2(400, 400)) }
        #expect(gap != nil)
        #expect(gap.map { g in discs.allSatisfy { !Shape(contours: [$0]).contains(g.centroid) } } == true)
        #expect(abs(totalArea(found) - enclosedArea(discs)) < booleanSlack)
        #expect(abs(totalArea(found) - union(of: discs).area - (gap?.area ?? 0)) < booleanSlack)
    }

    // MARK: Every boundary on the input

    @Test func aRandomTangleInsideABoxTilesTheBox() {
        var rng = SplitMix64(seed: 3)
        let box = Rectangle(x: 0, y: 0, width: 800, height: 600)
        let edge = box.contour
        var lines = [edge]
        // Forty chords, each end exactly on the box's edge, so every line
        // meets the frame in a T and nothing floats loose inside.
        for _ in 0 ..< 40 {
            lines.append(line(edge.point(at: Double.random(in: 0 ..< 1, using: &rng)),
                              edge.point(at: Double.random(in: 0 ..< 1, using: &rng))))
        }
        let found = regions(enclosedBy: lines)
        #expect(found.count > 100)
        #expect(abs(totalArea(found) - 800 * 600) < 1e-6)
        #expect(largestOverlap(found) < booleanSlack)
        #expect(farthestFromInput(found, lines) < 1e-6)
        for region in found { #expect(region.contours.count == 1) }
        // Lines that may end anywhere can ring an island of their own, which
        // is then a region and a hole in the region around it: the tiling
        // still holds.
        var loose = [edge]
        for _ in 0 ..< 40 {
            loose.append(line(Vector2(Double.random(in: 0 ... 800, using: &rng),
                                      Double.random(in: 0 ... 600, using: &rng)),
                              Vector2(Double.random(in: 0 ... 800, using: &rng),
                                      Double.random(in: 0 ... 600, using: &rng))))
        }
        let tangle = regions(enclosedBy: loose)
        #expect(abs(totalArea(tangle) - 800 * 600) < 1e-6)
        #expect(tangle.contains { $0.contours.count > 1 })
        #expect(largestOverlap(tangle) < booleanSlack)
        #expect(farthestFromInput(tangle, loose) < 1e-6)
    }

    // MARK: Loose ends and crossings

    @Test func aLooseEndWallsNothingOffAndACrossingCutsInTwo() {
        let disc = Circle(center: Vector2(400, 400), radius: 150).contour()
        // A stroke that starts outside and ends inside the circle.
        let hanging = line(Vector2(100, 400), Vector2(400, 400))
        let one = regions(enclosedBy: [disc, hanging])
        #expect(one.count == 1)
        #expect(abs(one[0].area - disc.length * 0 - Shape(contours: [disc]).area) < 1e-6)
        // A line clean through it.
        let through = line(Vector2(100, 400), Vector2(700, 400))
        let two = regions(enclosedBy: [disc, through])
        #expect(two.count == 2)
        #expect(abs(two[0].area - two[1].area) < 1e-6)
        #expect(abs(two[0].area + two[1].area - Shape(contours: [disc]).area) < 1e-6)
        // A stroke that crosses nothing encloses nothing.
        #expect(regions(enclosedBy: [through]).isEmpty)
        #expect(regions(enclosedBy: [hanging, through]).isEmpty)
    }

    @Test func anOutlineCrossingItselfGivesEachLobe() {
        let bowtie = Contour([Vector2(0, 0), Vector2(200, 200), Vector2(200, 0), Vector2(0, 200)], closed: true)
        let lobes = regions(enclosedBy: [bowtie])
        #expect(lobes.count == 2)
        for lobe in lobes {
            #expect(abs(lobe.area - 10_000) < 1e-9)
            #expect(lobe.contours[0].points.count == 3)
        }
        #expect(farthestFromInput(lobes, [bowtie]) < 1e-9)
    }

    @Test func aLoneClosedOutlineIsItsOwnRegion() {
        let triangle = Contour([Vector2(0, 0), Vector2(300, 0), Vector2(0, 400)], closed: true)
        let found = regions(enclosedBy: [triangle])
        #expect(found.count == 1)
        #expect(abs(found[0].area - 60_000) < 1e-9)
        #expect(found[0].contours[0].points.count == 3)
    }

    // MARK: Holes

    @Test func aRegionInsideAnotherIsAHoleInIt() {
        let outer = Circle(center: Vector2(400, 400), radius: 300).contour()
        let middle = Circle(center: Vector2(380, 420), radius: 160).contour()
        let inner = Circle(center: Vector2(360, 440), radius: 60).contour()
        let found = regions(enclosedBy: [outer, middle, inner])
        #expect(found.count == 3)
        let byArea = found.sorted { exactArea($0) < exactArea($1) }
        let disc = Shape(contours: [inner]).area
        let ring = Shape(contours: [middle]).area - disc
        let band = Shape(contours: [outer]).area - Shape(contours: [middle]).area
        #expect(abs(exactArea(byArea[0]) - disc) < 1e-6)
        #expect(byArea[0].contours.count == 1)
        #expect(abs(exactArea(byArea[1]) - ring) < 1e-6)
        #expect(byArea[1].contours.count == 2)
        #expect(abs(exactArea(byArea[2]) - band) < 1e-6)
        #expect(byArea[2].contours.count == 2)
        // The band's hole is the middle circle, not the inner one.
        #expect(byArea[2].contains(Vector2(360, 440)) == false)
        #expect(byArea[2].contains(Vector2(400, 120)))
        #expect(abs(totalArea(found) - enclosedArea([outer, middle, inner])) < booleanSlack)
    }

    @Test func twoIslandsInsideOneRegionAreTwoHoles() {
        let frame = Rectangle(x: 0, y: 0, width: 600, height: 400).contour
        let left = Circle(center: Vector2(150, 200), radius: 80).contour()
        let right = Rectangle(x: 350, y: 120, width: 160, height: 160).contour
        let found = regions(enclosedBy: [frame, left, right])
        #expect(found.count == 3)
        let outside = found.max { exactArea($0) < exactArea($1) }
        #expect(outside?.contours.count == 3)
        #expect(abs(totalArea(found) - 600 * 400) < 1e-6)
    }

    // MARK: Lines along each other

    @Test func linesAlongEachOtherShareOneEdge() {
        // Two squares that abut along a whole side, and a third that overlaps
        // part of a side of the first.
        let a = Rectangle(x: 0, y: 0, width: 200, height: 200).contour
        let b = Rectangle(x: 200, y: 0, width: 200, height: 200).contour
        let abutting = regions(enclosedBy: [a, b])
        #expect(abutting.count == 2)
        #expect(abs(totalArea(abutting) - 80_000) < 1e-6)
        #expect(largestOverlap(abutting) < booleanSlack)
        let c = Rectangle(x: 50, y: 200, width: 100, height: 100).contour
        let partial = regions(enclosedBy: [a, c])
        #expect(partial.count == 2)
        #expect(abs(totalArea(partial) - 50_000) < 1e-6)
        #expect(farthestFromInput(partial, [a, c]) < 1e-9)
    }

    @Test func aLineThroughACornerCountsOnce() {
        // A diagonal exactly through two corners of a square splits it in two
        // triangles, and a line ending exactly on an edge is a T-junction.
        let square = Rectangle(x: 0, y: 0, width: 200, height: 200).contour
        let diagonal = line(Vector2(-50, -50), Vector2(250, 250))
        let halves = regions(enclosedBy: [square, diagonal])
        #expect(halves.count == 2)
        for half in halves { #expect(abs(half.area - 20_000) < 1e-9) }
        let tee = line(Vector2(100, 0), Vector2(100, 200))
        let columns = regions(enclosedBy: [square, tee])
        #expect(columns.count == 2)
        for column in columns { #expect(abs(column.area - 20_000) < 1e-9) }
    }

    // MARK: Order and the shape form

    @Test func theOrderIsReadingOrderAndTheSameDrawingRepeats() {
        var rng = SplitMix64(seed: 21)
        var outlines: [Contour] = []
        for _ in 0 ..< 9 {
            let center = Vector2(Double.random(in: 100 ... 900, using: &rng),
                                 Double.random(in: 100 ... 900, using: &rng))
            outlines.append(Circle(center: center, radius: Double.random(in: 80 ... 220, using: &rng)).contour())
        }
        let first = regions(enclosedBy: outlines)
        let second = regions(enclosedBy: outlines)
        #expect(first == second)
        for i in 1 ..< first.count {
            let before = first[i - 1].bounds!, after = first[i].bounds!
            #expect(before.y < after.y || (before.y == after.y && before.x <= after.x))
        }
        let shuffled = regions(enclosedBy: outlines.reversed())
        #expect(abs(totalArea(shuffled) - totalArea(first)) < 1e-6)
        #expect(shuffled.count == first.count)
    }

    @Test func theShapeFormReadsEveryContour() {
        let frame = Shape(outer: Rectangle(x: 0, y: 0, width: 400, height: 400).contour.points,
                          holes: [Rectangle(x: 100, y: 100, width: 200, height: 200).contour.points])
        let bar = Shape(Rectangle(x: 150, y: -50, width: 100, height: 500).contour.points)
        let fromShapes = regions(enclosedBy: [frame, bar])
        let fromContours = regions(enclosedBy: frame.contours + bar.contours)
        #expect(fromShapes == fromContours)
        #expect(fromShapes.count == 9)
        #expect(abs(totalArea(fromShapes) - (400 * 400 + 100 * 100)) < 1e-6)
    }

    // MARK: Degenerate input

    @Test func degenerateInputEnclosesNothing() {
        #expect(regions(enclosedBy: [Contour]()).isEmpty)
        #expect(regions(enclosedBy: [Contour([Vector2(1, 1)])]).isEmpty)
        #expect(regions(enclosedBy: [Contour([Vector2(1, 1), Vector2(5, 5)])]).isEmpty)
        #expect(regions(enclosedBy: [Contour([Vector2(1, 1), Vector2(1, 1), Vector2(1, 1)])]).isEmpty)
        let bad = Contour([Vector2(0, 0), Vector2(.nan, 10), Vector2(10, 10), Vector2(10, 0)])
        #expect(regions(enclosedBy: [bad]).isEmpty)
    }

    // MARK: The outlines a circle and a rectangle give

    @Test func aCircleOutlineStaysWithinATenthOfTheCircle() {
        for radius in [4.0, 30.0, 120.0, 400.0, 1500.0] {
            let circle = Circle(center: Vector2(10, 20), radius: radius)
            let outline = circle.contour()
            #expect(outline.isClosed)
            #expect(outline.points.count >= 8 && outline.points.count <= 256)
            for p in outline { #expect(abs(p.distance(to: circle.center) - radius) < 1e-9) }
            let points = outline.points
            for i in points.indices where points.count < 256 {
                let mid = (points[i] + points[(i + 1) % points.count]) / 2
                #expect(radius - mid.distance(to: circle.center) <= 0.1 + 1e-9)
            }
        }
        #expect(Circle(center: .zero, radius: 10).contour(segments: 5).points.count == 5)
        #expect(Circle(center: .zero, radius: 10).contour(segments: 1).points.count == 3)
        #expect(Circle(center: .zero, radius: 1500).contour().points.count == 256)
        #expect(Circle(center: .zero, radius: 400).contour().points.count > Circle(center: .zero, radius: 30).contour().points.count)
        // Starts at the right and runs clockwise as the canvas shows it.
        let ring = Circle(center: Vector2(100, 100), radius: 50).contour(segments: 4)
        #expect(ring.points[0] == Vector2(150, 100))
        #expect(ring.points[1].distance(to: Vector2(100, 150)) < 1e-9)
    }

    @Test func aRectangleOutlineIsItsCornersClockwise() {
        let box = Rectangle(x: 10, y: 20, width: 30, height: 40)
        #expect(box.contour.points == [Vector2(10, 20), Vector2(40, 20), Vector2(40, 60), Vector2(10, 60)])
        #expect(box.contour.isClosed)
        #expect(abs(Shape(contours: [box.contour]).area - 1200) < 1e-9)
    }
}
