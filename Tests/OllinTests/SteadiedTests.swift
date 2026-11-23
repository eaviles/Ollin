import Foundation
import Testing
@testable import Ollin

/// Found things held steady (`Steadier`, `@Steadied`), on findings the test
/// makes itself so the truth is known: where each thing really is, when it
/// was really there, and which one it is. Points are a share of a picture
/// 1080 pixels across, which is what turns a step into pixels below.
@Suite struct SteadiedTests {

    static let canvas = 1080.0
    /// Analyses a second and drawn frames a second: a detector slower than
    /// the sketch, every answer read for two frames.
    static let rate = 30.0
    static let drawRate = 60.0

    /// A small seeded generator, so each test's shake is the same every run.
    struct Mix {
        private var state: UInt64
        init(_ seed: UInt64) { state = seed }

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }

        mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }

        mutating func gaussian() -> Double {
            while true {
                let u = unit() * 2 - 1, v = unit() * 2 - 1
                let s = u * u + v * v
                if s > 0, s < 1 { return u * (-2 * Foundation.log(s) / s).squareRoot() }
            }
        }
    }

    /// A box with every edge shaken by `pixels` (standard deviation).
    static func shaken(_ box: Rectangle, by pixels: Double, _ mix: inout Mix) -> Rectangle {
        let s = pixels / canvas
        let x0 = box.x + mix.gaussian() * s, y0 = box.y + mix.gaussian() * s
        let x1 = box.x + box.width + mix.gaussian() * s, y1 = box.y + box.height + mix.gaussian() * s
        return Rectangle(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    /// Runs `analyses` through `steadier` the way a sketch does, each read
    /// for two drawn frames, and hands every drawn frame's things to `each`
    /// with the index of the analysis it read.
    static func drive<Thing: Steadiable>(_ steadier: inout Steadier<Thing>, _ analyses: [[Thing]],
                                         each: (Int, [Steady<Thing>]) -> Void) {
        let hold = Int(drawRate / rate)
        for (index, found) in analyses.enumerated() {
            for _ in 0..<hold {
                each(index, steadier.steady(found, deltaTime: 1 / drawRate))
            }
        }
    }

    /// The farthest any edge of a box moved between two frames, in pixels.
    static func step(_ a: Rectangle, _ b: Rectangle) -> Double {
        zip(a.steadyPoints, b.steadyPoints).map { max(abs($0.x - $1.x), abs($0.y - $1.y)) }.max()! * canvas
    }

    static func quantile(_ values: [Double], _ p: Double) -> Double {
        let sorted = values.sorted()
        return sorted[min(sorted.count - 1, Int(Double(sorted.count) * p))]
    }

    // MARK: Shake

    @Test func aStillThingMovesUnderAPixel() {
        var mix = Mix(11)
        let truth = Rectangle(x: 0.4, y: 0.35, width: 0.2, height: 0.3)
        let analyses = (0..<300).map { _ in [Self.shaken(truth, by: 2, &mix)] }

        // What goes in shakes by pixels from one analysis to the next.
        let rawSteps = zip(analyses, analyses.dropFirst()).map { Self.step($0[0], $1[0]) }
        #expect(Self.quantile(rawSteps, 0.5) > 2.5)

        var steadier = Steadier<Rectangle>()
        var steps: [Double] = []
        var last: Rectangle?
        var farthest = 0.0
        Self.drive(&steadier, analyses) { index, things in
            guard index >= 30, let thing = things.first else { return }
            if let last { steps.append(Self.step(last, thing.value)) }
            last = thing.value
            farthest = max(farthest, Self.step(truth, thing.value))
        }
        #expect(steps.count > 500)
        #expect(Self.quantile(steps, 0.95) < 1, "p95 \(Self.quantile(steps, 0.95)) px a frame")
        #expect(steps.max()! < 2)
        // And it is steady about the right place, not somewhere it drifted to.
        #expect(farthest < 3, "\(farthest) px from where the thing is")
    }

    @Test func aMovingThingIsFollowedClosely() {
        var mix = Mix(12)
        // Across the picture in two seconds, which is a hand moving a cup.
        let analyses = (0..<60).map { index -> [Rectangle] in
            let x = 0.1 + 0.6 * Double(index) / 60
            return [Self.shaken(Rectangle(x: x, y: 0.4, width: 0.15, height: 0.2), by: 1.5, &mix)]
        }
        var steadier = Steadier<Rectangle>()
        var behind: [Double] = []
        Self.drive(&steadier, analyses) { index, things in
            guard index >= 15, let thing = things.first else { return }
            behind.append((thing.found.x - thing.value.x) * Self.canvas)
        }
        // 324 pixels a second; under 20 pixels behind is under 60 ms.
        #expect(Self.quantile(behind, 0.5) > 0, "it trails, it does not lead")
        #expect(Self.quantile(behind, 0.95) < 20, "p95 \(Self.quantile(behind, 0.95)) px behind")
    }

    // MARK: Blink

    @Test func aThingThatDropsForThreeFramesDoesNotBlink() {
        var mix = Mix(21)
        let truth = Rectangle(x: 0.3, y: 0.3, width: 0.2, height: 0.2)
        var analyses: [[Rectangle]] = []
        for _ in 0..<6 {
            analyses += (0..<20).map { _ in [Self.shaken(truth, by: 2, &mix)] }
            analyses += [[], [], []]
        }
        var steadier = Steadier<Rectangle>()
        var appeared = false
        var longestUnseen = 0.0
        var ids = Set<Int>()
        var gaps = 0
        Self.drive(&steadier, analyses) { _, things in
            if !things.isEmpty { appeared = true }
            guard appeared else { return }
            if things.count != 1 { gaps += 1 }
            for thing in things {
                ids.insert(thing.id)
                longestUnseen = max(longestUnseen, thing.unseenFor)
            }
        }
        #expect(appeared)
        #expect(gaps == 0, "it was gone for \(gaps) drawn frames")
        #expect(ids == [1], "one thing all along, not \(ids.sorted())")
        // Three analyses at thirty a second.
        #expect(longestUnseen > 0.08 && longestUnseen <= 0.1 + 1e-9, "\(longestUnseen)")
    }

    @Test func aThingGoneLongerThanTheHoldIsLetGoAndComesBackAsAnother() {
        let truth = Rectangle(x: 0.3, y: 0.3, width: 0.2, height: 0.2)
        var analyses = [[Rectangle]](repeating: [truth], count: 15)
        analyses += [[Rectangle]](repeating: [], count: 15)    // half a second
        analyses += [[Rectangle]](repeating: [truth], count: 15)
        var steadier = Steadier<Rectangle>()
        var showing: [Int: Int] = [:]   // analysis → the id showing, 0 for none
        Self.drive(&steadier, analyses) { index, things in showing[index] = things.first?.id ?? 0 }
        #expect(showing[14] == 1)
        // Held for the hold time (nine analyses), then gone.
        #expect(showing[15 + 8] == 1)
        #expect(showing[15 + 10] == 0)
        #expect(showing[29] == 0)
        #expect(showing[44] == 2)
    }

    @Test func aThingFoundForOneFrameNeverAppears() {
        let ghost = Rectangle(x: 0.6, y: 0.6, width: 0.1, height: 0.1)
        var analyses = [[Rectangle]](repeating: [], count: 40)
        for index in stride(from: 3, to: 40, by: 5) { analyses[index] = [ghost] }
        var steadier = Steadier<Rectangle>()
        var shown = 0
        Self.drive(&steadier, analyses) { _, things in shown += things.count }
        #expect(shown == 0)
    }

    @Test func aThingAppearsOnceItHasBeenFoundForTheDelay() {
        let truth = Rectangle(x: 0.3, y: 0.3, width: 0.2, height: 0.2)
        var steadier = Steadier<Rectangle>(Steadiness(appearDelay: 0.1))
        var first: Int?
        for frame in 0..<20 {
            if !steadier.steady([truth], deltaTime: 1 / Self.drawRate).isEmpty, first == nil { first = frame }
        }
        // Found from frame 0, so a tenth of a second is the sixth frame after.
        let appeared = try! #require(first)
        #expect(appeared == 6 || appeared == 7, "frame \(appeared)")

        var atOnce = Steadier<Rectangle>(Steadiness(appearDelay: 0))
        #expect(atOnce.steady([truth], deltaTime: 1 / Self.drawRate).map(\.id) == [1])
    }

    // MARK: Identity

    @Test func twoThingsThatCrossKeepTheirIdentities() {
        var mix = Mix(31)
        // The same size on the same line, straight through each other.
        let analyses = (0..<70).map { index -> [Rectangle] in
            let t = Double(index) / 70
            let goingRight = Rectangle(x: 0.15 + 0.6 * t, y: 0.4, width: 0.12, height: 0.2)
            let goingLeft = Rectangle(x: 0.75 - 0.6 * t, y: 0.4, width: 0.12, height: 0.2)
            let found = [Self.shaken(goingRight, by: 1.5, &mix), Self.shaken(goingLeft, by: 1.5, &mix)]
            // The detector's order says nothing about which is which.
            return mix.unit() < 0.5 ? found : found.reversed()
        }
        var steadier = Steadier<Rectangle>()
        var startedLeft: Int?
        var counts = Set<Int>()
        var ids = Set<Int>()
        var last: [Steady<Rectangle>] = []
        Self.drive(&steadier, analyses) { index, things in
            if index == 8 { startedLeft = things.min { $0.value.x < $1.value.x }?.id }
            if index >= 8 {
                counts.insert(things.count)
                things.forEach { ids.insert($0.id) }
            }
            last = things
        }
        #expect(counts == [2], "two things on every frame, not \(counts.sorted())")
        #expect(ids == [1, 2], "the same two all along, not \(ids.sorted())")
        let left = try! #require(startedLeft)
        let ended = try! #require(last.first { $0.id == left })
        #expect(ended.value.x > 0.6, "the one that started on the left ended at \(ended.value.x)")
    }

    @Test func twoThingsThatCrossUnderASlowDetectorKeepTheirIdentities() {
        var mix = Mix(32)
        // Fifteen answers a second, each read for four drawn frames, and the
        // things faster: between two answers each has gone a quarter of its
        // width, so only the speed it was going says which is which.
        let analyses = (0..<30).map { index -> [Rectangle] in
            let t = Double(index) / 30
            let goingRight = Rectangle(x: 0.05 + 0.8 * t, y: 0.4, width: 0.12, height: 0.2)
            let goingLeft = Rectangle(x: 0.85 - 0.8 * t, y: 0.4, width: 0.12, height: 0.2)
            let found = [Self.shaken(goingRight, by: 1.5, &mix), Self.shaken(goingLeft, by: 1.5, &mix)]
            return mix.unit() < 0.5 ? found : found.reversed()
        }
        var steadier = Steadier<Rectangle>()
        var startedLeft: Int?
        var ids = Set<Int>()
        var last: [Steady<Rectangle>] = []
        for (index, found) in analyses.enumerated() {
            for _ in 0..<4 {
                last = steadier.steady(found, deltaTime: 1 / Self.drawRate)
                if index == 5, startedLeft == nil { startedLeft = last.min { $0.value.x < $1.value.x }?.id }
                if index >= 5 { last.forEach { ids.insert($0.id) } }
            }
        }
        #expect(ids == [1, 2], "the same two all along, not \(ids.sorted())")
        let left = try! #require(startedLeft)
        let ended = try! #require(last.first { $0.id == left })
        #expect(ended.value.x > 0.6, "the one that started on the left ended at \(ended.value.x)")
    }

    @Test func theNumbersCountTheThingsThatAppeared() {
        let a = Rectangle(x: 0.1, y: 0.1, width: 0.1, height: 0.1)
        let b = Rectangle(x: 0.5, y: 0.1, width: 0.1, height: 0.1)
        let ghost = Rectangle(x: 0.8, y: 0.8, width: 0.1, height: 0.1)
        let c = Rectangle(x: 0.5, y: 0.6, width: 0.1, height: 0.1)
        var analyses = [[Rectangle]](repeating: [a], count: 10)
        analyses += [[a, ghost]]                                   // one frame, and never a number
        analyses += [[Rectangle]](repeating: [b, a], count: 10)    // the newcomer listed first
        analyses += [[Rectangle]](repeating: [c, b, a], count: 10)
        var steadier = Steadier<Rectangle>()
        var last: [Steady<Rectangle>] = []
        Self.drive(&steadier, analyses) { _, things in last = things }
        #expect(last.map(\.id) == [1, 2, 3], "oldest first")
        #expect(abs(last[0].value.x - a.x) < 1e-6 && abs(last[1].value.x - b.x) < 1e-6)
        #expect(abs(last[2].value.y - c.y) < 1e-6)
        #expect(last[0].age > last[1].age && last[1].age > last[2].age)
    }

    // MARK: Confidence

    /// A box with a confidence of its own.
    struct Guess: Steadiable {
        var box: Rectangle
        var confidence: Double
        var steadyPoints: [Vector2] { box.steadyPoints }
        var steadyConfidence: Double { confidence }
        func steadied(at points: [Vector2]) -> Guess { Guess(box: box.steadied(at: points), confidence: confidence) }
    }

    @Test func aFaintFindingKeepsAThingAndNeverStartsOne() {
        let box = Rectangle(x: 0.3, y: 0.3, width: 0.2, height: 0.2)
        let other = Rectangle(x: 0.7, y: 0.7, width: 0.1, height: 0.1)
        var steadier = Steadier<Guess>(Steadiness(minConfidence: 0.5, minKeptConfidence: 0.1))
        var analyses = [[Guess]](repeating: [Guess(box: box, confidence: 0.9), Guess(box: other, confidence: 0.3)],
                                 count: 10)
        // Its confidence dips under the bar for a second: still found.
        analyses += [[Guess]](repeating: [Guess(box: box, confidence: 0.3), Guess(box: other, confidence: 0.3)],
                              count: 30)
        var unseen = 0.0
        var counts = Set<Int>()
        Self.drive(&steadier, analyses) { index, things in
            guard index >= 5 else { return }
            counts.insert(things.count)
            unseen = max(unseen, things.first?.unseenFor ?? 99)
        }
        #expect(counts == [1], "the faint one in the corner never appeared: \(counts.sorted())")
        #expect(unseen == 0, "and the dip was never a gap")
        #expect(steadier.things.first?.value.confidence == 0.3, "the newest finding's confidence")

        // Under the lower bar a finding is not a finding: the thing is held, then gone.
        let ignored = [[Guess]](repeating: [Guess(box: box, confidence: 0.05)], count: 12)
        Self.drive(&steadier, ignored) { _, _ in }
        #expect(steadier.things.isEmpty)
    }

    // MARK: Outlines

    /// Four corners in order, as a rectangle detector gives them.
    struct Quad: Steadiable {
        var corners: [Vector2]
        var steadyPoints: [Vector2] { corners }
        func steadied(at points: [Vector2]) -> Quad { Quad(corners: points) }

        var area: Double {
            var sum = 0.0
            for i in corners.indices {
                let a = corners[i], b = corners[(i + 1) % corners.count]
                sum += a.x * b.y - b.x * a.y
            }
            return abs(sum) / 2
        }
    }

    @Test func anOutlinesCornersMayBeNamedFromAnyOfThem() {
        var mix = Mix(41)
        let truth = [Vector2(0.30, 0.30), Vector2(0.62, 0.34), Vector2(0.58, 0.66), Vector2(0.27, 0.61)]
        // The detector calls a different corner the first on every frame.
        let analyses = (0..<90).map { _ -> [Quad] in
            let turn = Int(mix.next() % 4)
            let shaken = truth.map { $0 + Vector2(mix.gaussian(), mix.gaussian()) * (1.5 / Self.canvas) }
            return [Quad(corners: (0..<4).map { shaken[($0 + turn) % 4] })]
        }
        var steadier = Steadier<Quad>()
        var worstArea = 0.0
        var worstOrder = 0.0
        let area = Quad(corners: truth).area
        Self.drive(&steadier, analyses) { index, things in
            guard index >= 15, let thing = things.first else { return }
            // Smoothed corner for corner it keeps its shape. Smoothed in the
            // order given, each corner would be dragged toward the middle.
            worstArea = max(worstArea, abs(thing.value.area - area) / area)
            // And the steadied corners come back in the newest finding's order.
            for (steady, found) in zip(thing.value.corners, thing.found.corners) {
                worstOrder = max(worstOrder, (steady - found).length * Self.canvas)
            }
        }
        #expect(steadier.things.count == 1)
        #expect(worstArea < 0.02, "its area was \(worstArea * 100)% off")
        #expect(worstOrder < 8, "a corner \(worstOrder) px from the corner of the same name")
    }

    @Test func findingsThatOnlyPileUpInOnePlaceAreNotOneThing() {
        var mix = Mix(51)
        // A different rectangle about the same middle on every frame.
        let analyses = (0..<120).map { _ -> [Rectangle] in
            let w = 0.12 + mix.unit() * 0.16, h = 0.12 + mix.unit() * 0.16
            return [Rectangle(x: 0.5 - w / 2 + mix.gaussian() * 0.02, y: 0.5 - h / 2 + mix.gaussian() * 0.02,
                              width: w, height: h)]
        }
        // Loosely matched they chain into one thing that hops.
        var loose = Steadier<Rectangle>(Steadiness(minOverlap: 0.2))
        var looseShown = 0
        Self.drive(&loose, analyses) { _, things in looseShown += things.count }
        #expect(looseShown > 150)
        // A high overlap and a longer wait keep them out.
        var strict = Steadier<Rectangle>(Steadiness(appearDelay: 0.25, minOverlap: 0.8))
        var strictShown = 0
        Self.drive(&strict, analyses) { _, things in strictShown += things.count }
        #expect(strictShown == 0, "shown on \(strictShown) drawn frames")
    }

    @Test func itTakesMoreToBeAdmittedThanToStay() {
        // Two boxes for one thing that share six tenths of what they cover:
        // a detector that gives one outline and then settles on another.
        let wide = Rectangle(x: 0.30, y: 0.30, width: 0.30, height: 0.20)
        let narrow = Rectangle(x: 0.30, y: 0.30, width: 0.18, height: 0.20)
        let undecided = (0..<60).map { [$0 % 2 == 0 ? wide : narrow] }
        let changesItsMind = [[Rectangle]](repeating: [wide], count: 20) + [[Rectangle]](repeating: [narrow], count: 40)
        let both = Steadiness(appearDelay: 0.25, minOverlap: 0.8, minKeptOverlap: 0.5)

        // Turn about between the two from the start, it is never admitted.
        var never = Steadier<Rectangle>(both)
        var shown = 0
        Self.drive(&never, undecided) { _, things in shown += things.count }
        #expect(shown == 0)

        // Admitted while the detector was sure, it is followed to the other box.
        var stays = Steadier<Rectangle>(both)
        var ids = Set<Int>()
        var gaps = 0
        Self.drive(&stays, changesItsMind) { index, things in
            guard index >= 12 else { return }
            if things.count != 1 { gaps += 1 }
            things.forEach { ids.insert($0.id) }
        }
        #expect(ids == [1] && gaps == 0, "ids \(ids.sorted()), not one thing for \(gaps) frames")
        #expect(abs((stays.things.first?.value.width ?? 0) - narrow.width) < 0.005)

        // Held to the overlap it was admitted at, it is let go, and the other
        // box is admitted in its place as another thing.
        var strict = both
        strict.minKeptOverlap = 0.8
        var leaves = Steadier<Rectangle>(strict)
        var strictIDs = Set<Int>()
        Self.drive(&leaves, changesItsMind) { _, things in things.forEach { strictIDs.insert($0.id) } }
        #expect(strictIDs == [1, 2], "\(strictIDs.sorted())")
        #expect(leaves.things.map(\.id) == [2])

        // A kept overlap above the admitting one counts as the admitting one.
        var inverted = Steadier<Rectangle>(Steadiness(appearDelay: 0, minOverlap: 0.3, minKeptOverlap: 0.9))
        var invertedIDs = Set<Int>()
        Self.drive(&inverted, undecided) { _, things in things.forEach { invertedIDs.insert($0.id) } }
        #expect(invertedIDs == [1], "\(invertedIDs.sorted())")
    }

    // MARK: Settings

    struct Fussy: Steadiable {
        var box: Rectangle
        var steadyPoints: [Vector2] { box.steadyPoints }
        func steadied(at points: [Vector2]) -> Fussy { Fussy(box: box.steadied(at: points)) }
        static var steadiness: Steadiness { Steadiness(appearDelay: 0.5, minOverlap: 0.9) }
    }

    @Test func theSettingsAreTheTypesOwnUnlessGiven() {
        #expect(Steadier<Rectangle>().steadiness == Steadiness())
        #expect(Steadier<Fussy>().steadiness == Fussy.steadiness)
        #expect(Steadier<Fussy>(Steadiness(holdTime: 1)).steadiness.minOverlap == 0.2)

        let own = Steadied<Fussy>()
        #expect(own.steadiness == Fussy.steadiness)
        // One setting given, the others still the type's.
        let held = Steadied<Fussy>(holdTime: 1)
        #expect(held.steadiness.holdTime == 1)
        #expect(held.steadiness.appearDelay == 0.5 && held.steadiness.minOverlap == 0.9)
        held.steadiness.beta = 2
        #expect(held.steadiness.beta == 2)
    }

    @Test func theSettingsMeanTheSameInPixelsAsInSharesOfThePicture() {
        var mix = Mix(71)
        let truth = Rectangle(x: 0.2, y: 0.3, width: 0.2, height: 0.3)
        // A box that shakes, then crosses half the picture, then shakes again.
        let shares = (0..<150).map { index -> [Rectangle] in
            let along = min(max(Double(index - 50) / 50, 0), 1) * 0.5
            return [Self.shaken(Rectangle(x: truth.x + along, y: truth.y, width: truth.width, height: truth.height),
                                by: 2, &mix)]
        }
        let pixels = shares.map { $0.map { Rectangle(x: $0.x * 1920, y: $0.y * 1920, width: $0.width * 1920, height: $0.height * 1920) } }
        var a = Steadier<Rectangle>(), b = Steadier<Rectangle>()
        var worst = 0.0
        for (inShares, inPixels) in zip(shares, pixels) {
            for _ in 0..<2 {
                let one = a.steady(inShares, deltaTime: 1 / Self.drawRate).first
                let other = b.steady(inPixels, deltaTime: 1 / Self.drawRate).first
                #expect((one == nil) == (other == nil))
                guard let one, let other else { continue }
                worst = max(worst, abs(one.value.x * 1920 - other.value.x), abs(one.value.width * 1920 - other.value.width))
            }
        }
        // The same box to a rounding error, a thousandth of a pixel in 1920.
        #expect(worst < 1e-3, "\(worst) px apart")
    }

    @Test func resetForgetsEverything() {
        let box = Rectangle(x: 0.3, y: 0.3, width: 0.2, height: 0.2)
        var steadier = Steadier<Rectangle>()
        for _ in 0..<20 { steadier.steady([box], deltaTime: 1 / Self.drawRate) }
        #expect(steadier.things.map(\.id) == [1])
        steadier.reset()
        #expect(steadier.things.isEmpty)
        for _ in 0..<20 { steadier.steady([box], deltaTime: 1 / Self.drawRate) }
        #expect(steadier.things.map(\.id) == [1], "the numbers start again")
    }

    @Test func aBoxIsItsTwoCornersAndComesBackFromThem() {
        let box = Rectangle(x: 3, y: 4, width: 10, height: 20)
        #expect(box.steadyPoints == [Vector2(3, 4), Vector2(13, 24)])
        #expect(box.steadied(at: [Vector2(1, 2), Vector2(5, 9)]) == Rectangle(x: 1, y: 2, width: 4, height: 7))
        #expect(box.steadyConfidence == 1)
    }
}

/// `@Steadied` as a sketch holds it: stepped once a frame by the sketch, with
/// nothing called.
@Suite @MainActor struct SteadiedWrapperTests {

    /// Assigns a box that shakes by a pixel every frame and writes down what
    /// the wrapper reads back, in canvas pixels.
    private final class Finder: Sketch {
        @Steadied(appearDelay: 0.05) var boxes: [Rectangle] = []
        nonisolated(unsafe) static var read: [[Rectangle]] = []
        nonisolated(unsafe) static var ids: [[Int]] = []
        nonisolated(unsafe) static var raw: [Int] = []
        override var canvasSize: CanvasSize { .square(8) }
        override func draw() {
            Self.read.append(boxes)
            Self.ids.append($boxes.things.map(\.id))
            boxes = [Rectangle(x: 100 + Double(frameCount % 2), y: 50, width: 40, height: 30)]
            Self.raw.append($boxes.rawValue.count)
        }
    }

    @Test func aSketchStepsItsSteadiedThingsEveryFrame() throws {
        Finder.read = []; Finder.ids = []; Finder.raw = []
        _ = try OllinApp.image(of: Finder(), frame: 60)
        let read = Finder.read
        #expect(read.count == 61)
        #expect(read[0].isEmpty, "nothing was assigned before the first frame")
        #expect(Finder.raw.allSatisfy { $0 == 1 }, "what was assigned is there to read at once")
        // Found from the first frame's assignment, shown once the delay has passed.
        let first = try #require(read.firstIndex { !$0.isEmpty })
        #expect(first >= 3 && first <= 6, "frame \(first)")
        #expect(Finder.ids[first...].allSatisfy { $0 == [1] })
        // The pixel of shake going in is a fraction of one coming out.
        let xs = read[20...].compactMap { $0.first?.x }
        #expect(xs.count == 41)
        #expect(xs.max()! - xs.min()! < 0.3, "it wandered \(xs.max()! - xs.min()!) px")
        #expect(xs.allSatisfy { $0 > 100 && $0 < 101 })
    }

    @Test func resettingTheWrapperForgetsWhatWasAssigned() {
        let steadied = Steadied<Rectangle>(appearDelay: 0)
        steadied.wrappedValue = [Rectangle(x: 1, y: 1, width: 2, height: 2)]
        steadied.advance(by: 1 / 60)
        #expect(steadied.wrappedValue.count == 1)
        steadied.reset()
        #expect(steadied.wrappedValue.isEmpty && steadied.rawValue.isEmpty && steadied.things.isEmpty)
    }
}
