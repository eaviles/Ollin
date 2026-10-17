import Foundation
import Testing
@testable import Ollin

/// The two parameter kinds shaped by hand in the inspector: a `ResponseCurve`
/// (a graph whose points drag, read as a function from 0 to 1) and a list of
/// numbers (a row of bars). These pin the curve's own promises, both kinds'
/// clamps, restores, and payloads, how a cue and the timeline move between two
/// of them, the `--param` spelling, and the editing the rows do.
@Suite
@MainActor
struct CurveAndListParamTests {

    // MARK: The curve

    /// Through every point, and between two points never past either height:
    /// a zigzag of points, sampled densely, stays inside each pair's band.
    @Test func aCurvePassesThroughItsPointsAndNeverOvershoots() {
        let points = [Vector2(0, 0), Vector2(0.2, 0.9), Vector2(0.35, 0.1), Vector2(0.6, 0.95),
                      Vector2(0.62, 0.9), Vector2(1, 0.5)]
        let curve = ResponseCurve(points: points)
        for point in points { #expect(curve(point.x) == point.y, "missed \(point)") }
        for pair in zip(points, points.dropFirst()) {
            let low = min(pair.0.y, pair.1.y), high = max(pair.0.y, pair.1.y)
            for step in 0...200 {
                let x = pair.0.x + (pair.1.x - pair.0.x) * Double(step) / 200
                let y = curve(x)
                #expect(y >= low - 1e-12 && y <= high + 1e-12, "overshot at \(x): \(y) outside \(low)...\(high)")
            }
        }
    }

    /// Smooth through a point: the slope just left of an inner point is the
    /// slope just right of it, which a polyline through the same points is not.
    @Test func aCurveIsSmoothThroughItsPoints() {
        let curve = ResponseCurve([(0, 1), (0.3, 0.8), (0.7, 0.2), (1, 0)])
        let h = 1e-6
        for x in [0.3, 0.7] {
            let left = (curve(x) - curve(x - h)) / h
            let right = (curve(x + h) - curve(x)) / h
            #expect(abs(left - right) < 1e-3, "a corner at \(x): \(left) against \(right)")
        }
        // Between the points it is a curve, not the straight line.
        #expect(abs(curve(0.5) - 0.5) < 1e-9, "symmetry put the middle at 0.5")
        #expect(abs(curve(0.15) - 0.9) > 0.005, "the first piece is straight")
    }

    /// Past its ends a curve holds the end heights; the points are put in
    /// order, held to the unit square, and one per place; no points is the
    /// straight line, which hands back what it is given.
    @Test func aCurveHoldsItsEndsAndTidiesItsPoints() {
        let curve = ResponseCurve([(0.8, 0.1), (0.2, 0.7), (0.5, 1.4), (0.5, 0.2), (.nan, 0.5)])
        #expect(curve.points == [Vector2(0.2, 0.7), Vector2(0.5, 1), Vector2(0.8, 0.1)])
        #expect(curve(0) == 0.7 && curve(0.1) == 0.7 && curve(-3) == 0.7)
        #expect(curve(0.9) == 0.1 && curve(1) == 0.1 && curve(7) == 0.1)
        #expect(ResponseCurve(points: []) == .linear)
        for x in stride(from: 0.0, through: 1, by: 0.125) { #expect(ResponseCurve.linear(x) == x) }
        #expect(ResponseCurve([(0, 0.4)])(0.9) == 0.4, "one point is a flat line")
        let eased = ResponseCurve([(0, 0), (0.5, 0.8), (1, 1)]).easing
        #expect(eased(0.5) == 0.8 && eased(2) == 1)
    }

    // MARK: As parameters

    private final class Shaped: Sketch {
        @Param(count: 2...4) var falloff = ResponseCurve([(0, 1), (0.5, 0.8), (1, 0)])
        @Param(-1...1) var swing = [0.5, -0.5, 1, 0]
        @Param(0...12, step: 2) var notes = [0, 3, 7, 10]
        override func draw() {}
    }

    /// The control follows the type: a curve is a graph, a list of numbers a
    /// row of bars, and a whole list steps by its step or by one.
    @Test func eachKindTakesItsRow() throws {
        let s = Shaped()
        let handles = Dictionary(uniqueKeysWithValues: s.parameters().map { ($0.name, $0) })
        guard case .graph(let graph) = handles["falloff"]?.control else {
            Issue.record("a curve is not a graph"); return
        }
        #expect(graph.count == 2...4 && graph.read() == s.falloff.points)
        guard case .bars(let swing) = handles["swing"]?.control,
              case .bars(let notes) = handles["notes"]?.control else {
            Issue.record("a list is not a row of bars"); return
        }
        #expect(swing.range == -1...1 && swing.step == nil)
        #expect(notes.range == 0...12 && notes.step == 2)
        #expect(s.notes == [0, 4, 8, 10], "a whole list snaps to its step: \(s.notes)")
        swing.write([2, -3, 0.25, 0])
        #expect(s.swing == [1, -1, 0.25, 0])
    }

    /// A curve keeps both ends when it holds too many points, and its payload
    /// restores exactly the shape that was left.
    @Test func aCurveClampsFromTheInsideAndRestoresItsShape() {
        let s = Shaped()
        s.falloff = ResponseCurve([(0, 1), (0.2, 0.9), (0.4, 0.6), (0.6, 0.4), (1, 0)])
        #expect(s.falloff.points == [Vector2(0, 1), Vector2(0.2, 0.9), Vector2(0.4, 0.6), Vector2(1, 0)])
        let stored = s.$falloff.stored
        #expect(stored == .curve([Vector2(0, 1), Vector2(0.2, 0.9), Vector2(0.4, 0.6), Vector2(1, 0)]))
        let fresh = Shaped()
        fresh.$falloff.restore(stored)
        #expect(fresh.falloff == s.falloff)
        fresh.$falloff.restore(.curve([]))
        #expect(fresh.falloff == s.falloff, "an empty payload restored something")
        fresh.$falloff.restore(.numbers([1, 2]))
        #expect(fresh.falloff == s.falloff, "a payload of the wrong kind restored something")
    }

    /// The number of bars is the declaration's: a longer payload restores its
    /// first values, a shorter one keeps the list's values past its end.
    @Test func aListKeepsItsLengthThroughARestore() {
        let s = Shaped()
        s.$swing.restore(.numbers([0.1, 0.2, 0.3, 0.4, 0.5, 0.6]))
        #expect(s.swing == [0.1, 0.2, 0.3, 0.4])
        s.$swing.restore(.numbers([-0.9]))
        #expect(s.swing == [-0.9, 0.2, 0.3, 0.4])
        s.$notes.restore(.numbers([12, .nan]))
        #expect(s.notes == [0, 4, 8, 10], "a payload with a number that is no step restored something")
        s.$notes.restore(.numbers([5.2, 11]))
        #expect(s.notes == [6, 12, 8, 10], "rounded, then snapped to the step: \(s.notes)")
    }

    /// Both payloads keep through a file and the wire.
    @Test func thePayloadsRoundTripThroughJSON() throws {
        let values: [ParamStored] = [.curve([Vector2(0, 1), Vector2(0.25, 0.5), Vector2(1, 0)]),
                                     .numbers([1, 0.25, -0.5])]
        let data = try JSONEncoder().encode(values)
        #expect(try JSONDecoder().decode([ParamStored].self, from: data) == values)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("\"curve\"") && text.contains("\"numbers\""))
    }

    // MARK: Between two values

    /// The timeline moves a list bar by bar and a curve point by point while
    /// the two hold as many; lengths that differ hold until the next key.
    @Test func aBlendMovesBarByBarAndPointByPoint() {
        let half = Automation.blend(.numbers([0, 1, 0.5]), .numbers([1, 0, 0.5]), 0.5)
        #expect(half == .numbers([0.5, 0.5, 0.5]))
        let curve = Automation.blend(.curve([Vector2(0, 0), Vector2(1, 1)]),
                                     .curve([Vector2(0, 1), Vector2(0.5, 0)]), 0.5)
        #expect(curve == .curve([Vector2(0, 0.5), Vector2(0.75, 0.5)]))
        #expect(Automation.blend(.numbers([0, 1]), .numbers([1, 0, 1]), 0.5) == .numbers([0, 1]))
        #expect(CueSheet.canFade(.numbers([0, 1]), .numbers([1, 0])))
        #expect(!CueSheet.canFade(.numbers([0, 1]), .numbers([1, 0, 1])))
        #expect(CueSheet.canFade(.curve([Vector2(0, 0), Vector2(1, 1)]), .curve([Vector2(0, 1), Vector2(1, 0)])))
    }

    /// A cue holds both kinds, and a fade between two cues moves the bars and
    /// the curve's points along with the numbers.
    @Test func aCueHoldsACurveAndAList() {
        let s = Shaped()
        s.swing = [-1, -1, -1, -1]
        s.falloff = ResponseCurve([(0, 0), (1, 0)])
        s.saveCue("low")
        s.swing = [1, 1, 1, 1]
        s.falloff = ResponseCurve([(0, 1), (1, 1)])
        s.saveCue("high")
        s.cue("low")
        #expect(s.swing == [-1, -1, -1, -1] && s.falloff(0.5) == 0)
        s.cue("high", over: 1)
        for i in 0..<30 { s.advance(time: Double(i) / 60, deltaTime: 1.0 / 60, frameRate: 60) }
        #expect(s.swing.allSatisfy { abs($0) < 0.1 }, "the bars at the midpoint: \(s.swing)")
        #expect(abs(s.falloff(0.5) - 0.5) < 0.05, "the curve at the midpoint: \(s.falloff(0.5))")
        for i in 30..<61 { s.advance(time: Double(i) / 60, deltaTime: 1.0 / 60, frameRate: 60) }
        #expect(s.swing == [1, 1, 1, 1] && s.falloff(0.5) == 1)
    }

    // MARK: On the command line

    /// `--param` reads a curve as heights at places (or heights spread evenly)
    /// and a list as its numbers, and the listing writes each the way the flag
    /// reads it back.
    @Test func theFlagReadsAndTheListingWritesBothKinds() {
        guard case .value(let placed) = ParamOverride.stored("1@0, 0.7@0.4, 0@1", like: .curve([])),
              case .value(let even) = ParamOverride.stored("1,0.5,0", like: .curve([])),
              case .value(let list) = ParamOverride.stored("1, 0.25,0", like: .numbers([0, 0, 0])) else {
            Issue.record("a well-formed value was refused"); return
        }
        #expect(placed == .curve([Vector2(0, 1), Vector2(0.4, 0.7), Vector2(1, 0)]))
        #expect(even == .curve([Vector2(0, 1), Vector2(0.5, 0.5), Vector2(1, 0)]))
        #expect(list == .numbers([1, 0.25, 0]))
        if case .value = ParamOverride.stored("1@x", like: .curve([])) { Issue.record("a bad place was read") }
        if case .value = ParamOverride.stored("1,,0", like: .numbers([0])) { Issue.record("an empty number was read") }

        let curveText = ParamListing.value(of: placed)
        #expect(curveText == "1@0,0.7@0.4,0@1")
        if case .value(let back) = ParamOverride.stored(curveText, like: .curve([])) { #expect(back == placed) }
        #expect(ParamListing.value(of: list) == "1,0.25,0")
    }

    // MARK: The rows' editing

    /// The add button puts its point in the widest gap, on the curve, so the
    /// curve does not move; a press at a place already held selects that point.
    @Test func anAddedPointLandsOnTheCurve() {
        let curve = ResponseCurve([(0, 1), (0.2, 0.9), (1, 0)])
        let added = curveGraphAdding(to: curve.points, sample: curve.callAsFunction)
        #expect(added.points.count == 4 && added.selected == 2)
        #expect(added.points[2].x == 0.6 && added.points[2].y == curve(0.6))
        let inserted = curveGraphInserting(at: 0.2, into: curve.points, sample: curve.callAsFunction)
        #expect(inserted.points == curve.points && inserted.selected == 1)
    }

    /// A dragged point stops a gap short of its neighbors and inside the
    /// square, so the order the graph shows is the order the curve holds.
    @Test func aDraggedPointStaysBetweenItsNeighbors() {
        let points = [Vector2(0, 1), Vector2(0.4, 0.5), Vector2(0.6, 0.2), Vector2(1, 0)]
        let moved = curveGraphMoving(points, index: 1, to: Vector2(0.9, 1.5), gap: 0.05)
        #expect(abs(moved[1].x - 0.55) < 1e-12 && moved[1].y == 1, "moved to \(moved[1])")
        let first = curveGraphMoving(points, index: 0, to: Vector2(-1, -1), gap: 0.05)
        #expect(first[0] == Vector2(0, 0))
    }

    /// A quick stroke that skips bars between two frames paints the bars it
    /// skipped, each its share of the way.
    @Test func aStrokeAcrossTheBarsPaintsTheOnesItSkipped() {
        let painted = barsPainting([0, 0, 0, 0, 0], from: 0, fromValue: 1, to: 4, toValue: 0)
        #expect(painted == [1, 0.75, 0.5, 0.25, 0])
        let back = barsPainting([0, 0, 0], from: 2, fromValue: 0, to: 0, toValue: 1)
        #expect(back == [1, 0.5, 0])
        #expect(barsPainting([0, 0], from: 1, fromValue: 0.3, to: 1, toValue: 0.6) == [0, 0.6])
    }
}
