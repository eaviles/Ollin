import Foundation
import Testing
import Ollin
@testable import OllinLaser

/// What the optimizer promises, measured on the stream it produces: the field
/// map, even point spacing, corners kept and held, blanked travel between
/// shapes, a seamless loop, path ordering, and a budget that reports rather
/// than drops. Pure arithmetic, no sockets and no GPU, so it runs anywhere.
@Suite
struct LaserOptimizerTests {

    // MARK: The field

    @Test func theCanvasMapsOntoTheFieldWithYTurnedOver() {
        let canvas = Rectangle(x: 0, y: 0, width: 100, height: 100)
        let toField = ProjectorSpace.transform(from: canvas)
        // The canvas grows downward and the field grows upward, so the top-left
        // corner is the field's top-left: x at its lowest, y at its highest.
        #expect(close(toField(Vector2(0, 0)), Vector2(-1, 1)))
        #expect(close(toField(Vector2(100, 100)), Vector2(1, -1)))
        #expect(close(toField(Vector2(50, 50)), Vector2(0, 0)))
    }

    @Test func aWideCanvasFitsInsideTheFieldRatherThanFillingIt() {
        let toField = ProjectorSpace.transform(from: Rectangle(x: 0, y: 0, width: 200, height: 100))
        #expect(close(toField(Vector2(0, 0)), Vector2(-1, 0.5)))
        #expect(close(toField(Vector2(200, 100)), Vector2(1, -0.5)))
    }

    @Test func theMapBackIsTheMapForward() {
        let canvas = Rectangle(x: 40, y: -10, width: 300, height: 180)
        let toField = ProjectorSpace.transform(from: canvas)
        let toCanvas = ProjectorSpace.inverse(to: canvas)
        for point in [Vector2(40, -10), Vector2(190, 80), Vector2(340, 170)] {
            #expect(close(toCanvas(toField(point)), point, tolerance: 1e-9))
        }
    }

    @Test func aPointDrawnOffTheCanvasStaysInsideTheField() {
        var frame = LaserFrame(canvas: Rectangle(x: 0, y: 0, width: 100, height: 100))
        frame.addLine(from: Vector2(-500, -500), to: Vector2(600, 600), color: .white)
        let stream = LaserOptimizer().stream(frame)
        for point in stream.points {
            #expect(abs(point.position.x) <= 1 + 1e-9)
            #expect(abs(point.position.y) <= 1 + 1e-9)
        }
    }

    // MARK: Spacing

    @Test func litPointsAreNeverFurtherApartThanTheSpacing() {
        var optimizer = LaserOptimizer()
        optimizer.spacing = 0.05
        let stream = optimizer.stream(square())
        var previous: LaserPoint?
        for point in stream.points {
            defer { previous = point }
            guard let last = previous, !last.isBlanked, !point.isBlanked else { continue }
            #expect((point.position - last.position).length <= optimizer.spacing + 1e-9)
        }
    }

    @Test func finerSpacingSpendsMorePointsOnTheSameLineWork() {
        var coarse = LaserOptimizer()
        coarse.spacing = 0.08
        var fine = LaserOptimizer()
        fine.spacing = 0.02
        #expect(fine.stream(square()).points.count > coarse.stream(square()).points.count * 2)
    }

    @Test func everyVertexTheSketchGaveLandsExactlyWhereItPutIt() {
        // Filling segments in keeps the corners; resampling the whole path by
        // arc length would move them, which is what rounds a square off.
        var optimizer = LaserOptimizer()
        optimizer.spacing = 0.07                  // does not divide the sides evenly
        optimizer.reordersPaths = false
        let stream = optimizer.stream(square())
        let corners = [Vector2(-0.5, 0.5), Vector2(0.5, 0.5), Vector2(0.5, -0.5), Vector2(-0.5, -0.5)]
        for corner in corners {
            let hit = stream.points.contains { close($0.position, corner, tolerance: 1e-9) }
            #expect(hit, "the corner at \(corner) is missing from the stream")
        }
    }

    // MARK: Corners

    @Test func aSharpCornerIsHeldForTheDwellCount() {
        var optimizer = LaserOptimizer()
        optimizer.cornerDwell = 5
        optimizer.reordersPaths = false
        let stream = optimizer.stream(square())
        // Each of the four right angles is held: the corner position repeats
        // once as the segment's end, then five more times.
        for corner in [Vector2(0.5, 0.5), Vector2(0.5, -0.5), Vector2(-0.5, -0.5)] {
            let held = stream.points.count(where: { close($0.position, corner, tolerance: 1e-9) && !$0.isBlanked })
            #expect(held == 6, "the corner at \(corner) was held \(held) times")
        }
    }

    @Test func aStraightRunIsNotHeldAtAll() {
        var optimizer = LaserOptimizer()
        optimizer.cornerDwell = 5
        optimizer.spacing = 10                    // one point per segment, nothing filled in
        var frame = LaserFrame(canvas: unitCanvas)
        // Three points in a line: the middle one is a vertex, not a corner.
        frame.add([Vector2(0, 500), Vector2(500, 500), Vector2(1000, 500)],
                  color: .white, closed: false)
        let stream = LaserOptimizer.streamCountingRepeats(optimizer, frame)
        #expect(stream == 0)
    }

    @Test func aTurnUnderTheCornerAngleIsNotHeld() {
        var optimizer = LaserOptimizer()
        optimizer.cornerDwell = 4
        optimizer.cornerAngle = .pi / 2           // only turns past 90 degrees count
        optimizer.spacing = 10
        var frame = LaserFrame(canvas: unitCanvas)
        frame.add([Vector2(0, 500), Vector2(500, 400), Vector2(1000, 500)],
                  color: .white, closed: false)   // a shallow bend
        #expect(LaserOptimizer.streamCountingRepeats(optimizer, frame) == 0)
    }

    // MARK: Blanking and travel

    @Test func theBeamIsOffBetweenTwoSeparateShapes() {
        var optimizer = LaserOptimizer()
        optimizer.reordersPaths = false
        var frame = LaserFrame(canvas: unitCanvas)
        frame.addLine(from: Vector2(100, 100), to: Vector2(200, 100), color: .red)
        frame.addLine(from: Vector2(800, 800), to: Vector2(900, 800), color: .blue)
        let stream = optimizer.stream(frame)

        // Walk the stream: the two lit runs must be separated by blanked points,
        // and no lit segment may span the gap between the shapes.
        var runs: [[LaserPoint]] = []
        var current: [LaserPoint] = []
        for point in stream.points {
            if point.isBlanked {
                if !current.isEmpty { runs.append(current); current = [] }
            } else {
                current.append(point)
            }
        }
        if !current.isEmpty { runs.append(current) }
        #expect(runs.count == 2)
        #expect(runs.allSatisfy { run in
            guard let first = run.first, let last = run.last else { return false }
            return (last.position - first.position).length < 0.3
        })
    }

    @Test func theBeamSettlesAtEachEndOfADarkJump() {
        var optimizer = LaserOptimizer()
        optimizer.blankingDwell = 6
        optimizer.reordersPaths = false
        var frame = LaserFrame(canvas: unitCanvas)
        frame.addLine(from: Vector2(100, 100), to: Vector2(200, 100), color: .red)
        frame.addLine(from: Vector2(800, 800), to: Vector2(900, 800), color: .blue)
        let points = optimizer.stream(frame).points

        // The stream opens with the settle at the first path's entry.
        let lead = points.prefix { $0.isBlanked }
        #expect(lead.count == 6)
        #expect(lead.allSatisfy { close($0.position, points[6].position, tolerance: 1e-9) })

        // And every lit run is followed by the same settle at its exit.
        guard let firstLit = points.firstIndex(where: { !$0.isBlanked }),
              let exit = points[firstLit...].firstIndex(where: { $0.isBlanked }) else {
            Issue.record("no dark jump in the stream")
            return
        }
        let settle = points[exit...].prefix { close($0.position, points[exit - 1].position, tolerance: 1e-9) }
        #expect(settle.count == 6)
    }

    @Test func theFrameLoopsWithNoSeam() {
        // The walk back from the last shape to the first is part of the frame,
        // so playing it again picks up where it left off.
        var optimizer = LaserOptimizer()
        optimizer.travelSpacing = 0.1
        var frame = LaserFrame(canvas: unitCanvas)
        frame.addLine(from: Vector2(100, 100), to: Vector2(200, 100), color: .red)
        frame.addLine(from: Vector2(800, 800), to: Vector2(900, 800), color: .blue)
        let points = optimizer.stream(frame).points
        guard let first = points.first, let last = points.last else { return }
        #expect((last.position - first.position).length <= optimizer.travelSpacing + 1e-9)
    }

    @Test func aClosedPathNeedsNoTravelToItself() {
        var optimizer = LaserOptimizer()
        optimizer.reordersPaths = false
        var frame = LaserFrame(canvas: unitCanvas)
        frame.add(ring(), color: .green)
        #expect(optimizer.stream(frame).travelLength == 0)
    }

    // MARK: Order

    @Test func pathsAreVisitedNearToNearRatherThanAsGiven() {
        var frame = LaserFrame(canvas: unitCanvas)
        // Deliberately alternating: as given, the beam crosses the canvas twice.
        frame.addLine(from: Vector2(50, 50), to: Vector2(150, 50), color: .white)
        frame.addLine(from: Vector2(950, 950), to: Vector2(850, 950), color: .white)
        frame.addLine(from: Vector2(200, 50), to: Vector2(300, 50), color: .white)
        frame.addLine(from: Vector2(800, 950), to: Vector2(700, 950), color: .white)

        var ordered = LaserOptimizer()
        ordered.reordersPaths = true
        var asGiven = LaserOptimizer()
        asGiven.reordersPaths = false
        #expect(ordered.stream(frame).travelLength < asGiven.stream(frame).travelLength)
    }

    @Test func orderingChangesTheRouteAndNotThePicture() {
        var frame = LaserFrame(canvas: unitCanvas)
        frame.addLine(from: Vector2(50, 50), to: Vector2(150, 50), color: .white)
        frame.addLine(from: Vector2(950, 950), to: Vector2(850, 950), color: .white)
        frame.addLine(from: Vector2(200, 50), to: Vector2(300, 50), color: .white)

        var ordered = LaserOptimizer()
        ordered.reordersPaths = true
        var asGiven = LaserOptimizer()
        asGiven.reordersPaths = false
        let a = ordered.stream(frame), b = asGiven.stream(frame)
        #expect(abs(a.drawnLength - b.drawnLength) < 1e-9)
        #expect(a.pathCount == b.pathCount)
    }

    @Test func anOpenPathMayBeWalkedBackwardsAndKeepsItsColors() {
        var frame = LaserFrame(canvas: unitCanvas)
        // The beam starts at the field center, so the tour enters this path at
        // whichever end is nearer: the blue one.
        frame.add([Vector2(50, 500), Vector2(450, 500)], colors: [.red, .blue], closed: false)
        let stream = LaserOptimizer().stream(frame)
        guard let firstLit = stream.points.first(where: { !$0.isBlanked }),
              let lastLit = stream.points.last(where: { !$0.isBlanked }) else {
            Issue.record("nothing lit")
            return
        }
        #expect(firstLit.color.blue > firstLit.color.red)
        #expect(lastLit.color.red > lastLit.color.blue)
        // And the color travels with the point it belongs to, not the index.
        #expect(firstLit.position.x > lastLit.position.x)
    }

    @Test func aColorRunIsCrossFadedAlongTheLine() {
        var optimizer = LaserOptimizer()
        optimizer.spacing = 0.05
        var frame = LaserFrame(canvas: unitCanvas)
        frame.add([Vector2(100, 500), Vector2(900, 500)], colors: [.red, .blue], closed: false)
        let lit = optimizer.stream(frame).points.filter { !$0.isBlanked }
        let middle = lit[lit.count / 2]
        #expect(middle.color.red > 0.2 && middle.color.red < 0.8)
        #expect(middle.color.blue > 0.2 && middle.color.blue < 0.8)
    }

    // MARK: Budget

    @Test func theBudgetIsThePointRateOverTheRefreshRate() {
        var optimizer = LaserOptimizer()
        optimizer.pointsPerSecond = 30_000
        optimizer.refreshRate = 25
        #expect(optimizer.pointBudget == 1_200)
        #expect(optimizer.stream(square()).pointBudget == 1_200)
    }

    @Test func aHeavyFrameReportsTheOverrunAndKeepsEveryPath() {
        var optimizer = LaserOptimizer()
        optimizer.pointsPerSecond = 1_000
        optimizer.refreshRate = 30                // 33 points to spend
        optimizer.spacing = 0.005
        let stream = optimizer.stream(square())
        #expect(stream.isOverBudget)
        #expect(stream.pathCount == 1)
        #expect(stream.refreshRate < optimizer.refreshRate)
        // Nothing is dropped: the whole square is still drawn, slowly.
        #expect(stream.drawnLength > 3.9)
    }

    @Test func anEmptyFrameProducesNothingToPlay() {
        let stream = LaserOptimizer().stream(LaserFrame(canvas: unitCanvas))
        #expect(stream.points.isEmpty)
        #expect(stream.refreshRate == 0)
    }

    @Test func degeneratePathsAreDropped() {
        var frame = LaserFrame(canvas: unitCanvas)
        frame.add([Vector2(10, 10)], color: .white)                        // one point
        frame.add([Vector2(20, 20), Vector2(20, 20)], color: .white)       // no length
        #expect(frame.isEmpty == false)
        let stream = LaserOptimizer().stream(frame)
        #expect(stream.pathCount == 0)
        #expect(stream.points.isEmpty)
    }

    @Test func theStreamCountsWhatItHolds() {
        let stream = LaserOptimizer().stream(square())
        #expect(stream.litCount + stream.blankedCount == stream.points.count)
        #expect(stream.litCount > 0)
        #expect(stream.duration > 0)
        #expect(stream.summary.contains("points"))
    }
}

// MARK: - Fixtures

let unitCanvas = Rectangle(x: 0, y: 0, width: 1000, height: 1000)

/// A square in the middle of the canvas: half the field wide, four right
/// angles, and closed.
func square() -> LaserFrame {
    var frame = LaserFrame(canvas: unitCanvas)
    frame.add([Vector2(250, 250), Vector2(750, 250), Vector2(750, 750), Vector2(250, 750)],
              color: .white, closed: true)
    return frame
}

/// A closed ring of twenty points.
func ring(radius: Double = 300) -> Contour {
    let points = (0..<20).map { i -> Vector2 in
        let a = Double(i) / 20 * 2 * .pi
        return Vector2(500 + cos(a) * radius, 500 + sin(a) * radius)
    }
    return Contour(points, closed: true)
}

func close(_ a: Vector2, _ b: Vector2, tolerance: Double = 1e-6) -> Bool {
    (a - b).length <= tolerance
}

extension LaserOptimizer {
    /// How many points in the stream repeat the position before them: the dwell
    /// the optimizer added, and nothing else.
    static func streamCountingRepeats(_ optimizer: LaserOptimizer, _ frame: LaserFrame) -> Int {
        let points = optimizer.stream(frame).points.filter { !$0.isBlanked }
        var repeats = 0
        for i in 1..<max(points.count, 1) where close(points[i].position, points[i - 1].position, tolerance: 1e-9) {
            repeats += 1
        }
        return repeats
    }
}
