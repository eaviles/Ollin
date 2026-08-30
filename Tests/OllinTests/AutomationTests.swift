@testable import Ollin
import Foundation
import Testing

/// Keyframed parameters (`Automation`): the claims worth pinning are laws
/// rather than pictures. A key must read back as itself, a curve must leave 0
/// and arrive at 1 without turning back, a value with nothing between two
/// settings must step instead of blending, and the whole thing must survive a
/// trip through a file. The last group drives a real sketch, because the
/// promise is that the knob a sketch reads in `draw()` is the curve.
@Suite
@MainActor
struct AutomationTests {

    // MARK: Curves

    private static let travelling: [Automation.Curve] = [
        .linear, .easeIn, .easeOut, .easeInOut,
        .bezier(x1: 0.42, y1: 0, x2: 0.58, y2: 1),
        .bezier(x1: 0.9, y1: 0.05, x2: 0.1, y2: 0.95),
    ]

    /// Every curve that travels leaves at 0, arrives at 1, and never turns
    /// back on the way. A curve that failed this would read as a knob that
    /// jumps or backs up mid move.
    @Test func curvesRunFromZeroToOneWithoutTurningBack() {
        for curve in Self.travelling {
            #expect(abs(curve.shape(0) - 0) < 1e-6, "\(curve) leaves 0")
            #expect(abs(curve.shape(1) - 1) < 1e-6, "\(curve) arrives at 1")
            var previous = -Double.infinity
            for step in 0...200 {
                let value = curve.shape(Double(step) / 200)
                #expect(value >= previous - 1e-9, "\(curve) turns back at \(step)")
                previous = value
            }
        }
    }

    /// Progress outside `0...1` clamps rather than running off the curve.
    @Test func progressOutsideTheSpanClamps() {
        for curve in Self.travelling {
            #expect(curve.shape(-3) == curve.shape(0))
            #expect(curve.shape(4) == curve.shape(1))
        }
    }

    /// The Bezier through its own diagonal handles is the straight line, and
    /// the symmetric pair mirrors about the middle: f(t) + f(1 - t) == 1.
    /// Both catch a solver that lands on the wrong parameter.
    @Test func bezierMatchesItsOwnGeometry() {
        let identity = Automation.Curve.bezier(x1: 0, y1: 0, x2: 1, y2: 1)
        let straight = Automation.Curve.bezier(x1: 1.0 / 3, y1: 1.0 / 3, x2: 2.0 / 3, y2: 2.0 / 3)
        let symmetric = Automation.Curve.bezier(x1: 0.42, y1: 0, x2: 0.58, y2: 1)
        for step in 0...50 {
            let t = Double(step) / 50
            #expect(abs(identity.shape(t) - t) < 1e-6)
            #expect(abs(straight.shape(t) - t) < 1e-6)
            #expect(abs(symmetric.shape(t) + symmetric.shape(1 - t) - 1) < 1e-6)
        }
    }

    /// The whole point of a Bezier timing curve is that the handles bend the
    /// *clock* as well as the value: reading it means finding the parameter
    /// whose x is the progress, then answering with that parameter's y. This
    /// measures the solver against a plain bisection written here, so a curve
    /// that skipped the search and read y straight off the progress reads
    /// wrong wherever the handles bend x.
    @Test func bezierInvertsItsOwnClock() {
        func reference(_ t: Double, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Double {
            func axis(_ a: Double, _ b: Double, _ u: Double) -> Double {
                let v = 1 - u
                return 3 * v * v * u * a + 3 * v * u * u * b + u * u * u
            }
            var low = 0.0, high = 1.0
            for _ in 0..<200 {
                let mid = (low + high) / 2
                if axis(x1, x2, mid) < t { low = mid } else { high = mid }
            }
            return axis(y1, y2, (low + high) / 2)
        }
        let handles: [(Double, Double, Double, Double)] = [
            (0.42, 0, 1, 1), (0, 0, 0.58, 1), (0.9, 0.05, 0.1, 0.95), (0.25, 0.9, 0.75, 0.1),
        ]
        for (x1, y1, x2, y2) in handles {
            let curve = Automation.Curve.bezier(x1: x1, y1: y1, x2: x2, y2: y2)
            var bentAwayFromTheProgress = false
            for step in 0...100 {
                let t = Double(step) / 100
                let expected = reference(t, x1, y1, x2, y2)
                #expect(abs(curve.shape(t) - expected) < 1e-6, "(\(x1), \(y1), \(x2), \(y2)) at \(t)")
                if abs(expected - t) > 0.02 { bentAwayFromTheProgress = true }
            }
            #expect(bentAwayFromTheProgress, "this handle set bends nothing, so it measures nothing")
        }
    }

    /// A hold sits at the value it left until the next key takes over.
    @Test func holdStaysUntilTheNextKey() {
        let track = Automation.Track(name: "n", keys: [
            .init(at: 0, .number(10), curve: .hold),
            .init(at: 2, .number(20), curve: .hold),
        ])
        #expect(track.value(at: 0) == .number(10))
        #expect(track.value(at: 1.999) == .number(10))
        #expect(track.value(at: 2) == .number(20))
    }

    // MARK: Tracks

    /// A key reads back as exactly itself, whatever curve leaves it. A blend
    /// that failed to short-circuit its ends would miss this by a hair.
    @Test func aKeyReadsBackAsItself() {
        for curve in Self.travelling + [.hold] {
            let track = Automation.Track(name: "n", keys: [
                .init(at: 0, .number(-3), curve: curve),
                .init(at: 1.5, .number(7), curve: curve),
                .init(at: 4, .number(0.25), curve: curve),
            ])
            #expect(track.value(at: 0) == .number(-3))
            #expect(track.value(at: 1.5) == .number(7))
            #expect(track.value(at: 4) == .number(0.25))
        }
    }

    /// Outside its own span a track is a constant: the first key before it,
    /// the last key after it.
    @Test func aTrackHoldsOutsideItsSpan() {
        let track = Automation.Track(name: "n", keys: [
            .init(at: 1, .number(5)), .init(at: 3, .number(9)),
        ])
        #expect(track.value(at: -100) == .number(5))
        #expect(track.value(at: 0.5) == .number(5))
        #expect(track.value(at: 3.5) == .number(9))
        #expect(track.value(at: 1e6) == .number(9))
        #expect(Automation.Track(name: "n", keys: []).value(at: 0) == nil)
    }

    /// Keys sort themselves, and two keys at the same moment keep the order
    /// they were written in, so the later one takes over from there.
    @Test func keysSortAndTiesKeepTheirOrder() {
        let track = Automation.Track(name: "n", keys: [
            .init(at: 3, .number(30)), .init(at: 1, .number(10)),
            .init(at: 2, .number(20)), .init(at: 2, .number(21)),
        ])
        #expect(track.keys.map(\.time) == [1, 2, 2, 3])
        #expect(track.value(at: 2) == .number(21))
        #expect(track.duration == 3)
    }

    /// A linear track measures the straight line between its keys.
    @Test func linearTravelsAtAnEvenRate() {
        let track = Automation.Track(name: "n", keys: [
            .init(at: 0, .number(0), curve: .linear),
            .init(at: 4, .number(100), curve: .linear),
        ])
        for step in 0...8 {
            let t = Double(step) / 2
            guard case .number(let value)? = track.value(at: t) else {
                Issue.record("no value at \(t)"); return
            }
            #expect(abs(value - t * 25) < 1e-9)
        }
    }

    // MARK: Blending by kind

    /// The geometry kinds blend component by component.
    @Test func geometryKindsBlendComponentwise() {
        #expect(Automation.blend(.vector(x: 0, y: 10), .vector(x: 4, y: 0), 0.5)
                == .vector(x: 2, y: 5))
        #expect(Automation.blend(.vector3(x: 0, y: 0, z: 0), .vector3(x: 2, y: 4, z: 8), 0.25)
                == .vector3(x: 0.5, y: 1, z: 2))
        #expect(Automation.blend(.rectangle(x: 0, y: 0, width: 10, height: 20),
                                 .rectangle(x: 10, y: 10, width: 20, height: 20), 0.5)
                == .rectangle(x: 5, y: 5, width: 15, height: 20))
        #expect(Automation.blend(.insets(top: 0, right: 0, bottom: 0, left: 0),
                                 .insets(top: 4, right: 8, bottom: 12, left: 16), 0.5)
                == .insets(top: 2, right: 4, bottom: 6, left: 8))
        #expect(Automation.blend(.range(lower: 0, upper: 10), .range(lower: 10, upper: 20), 0.5)
                == .range(lower: 5, upper: 15))
    }

    /// A switch, a menu choice, and a piece of text have nothing between two
    /// settings, so they hold the one they left. Two values of different kinds
    /// hold as well, which is what a knob that changed type does.
    @Test func settingsWithNothingBetweenThemStep() {
        #expect(Automation.blend(.boolean(false), .boolean(true), 0.99) == .boolean(false))
        #expect(Automation.blend(.option("a"), .option("b"), 0.75) == .option("a"))
        #expect(Automation.blend(.text("one"), .text("two"), 0.5) == .text("one"))
        #expect(Automation.blend(.number(1), .boolean(true), 0.5) == .number(1))
        // The ends still land on their own key.
        #expect(Automation.blend(.boolean(false), .boolean(true), 1) == .boolean(true))
    }

    /// A color fade keeps its ends and moves away from both in the middle,
    /// while alpha travels at an even rate.
    @Test func colorsFadeAndKeepTheirEnds() {
        let from = ParamStored.color(red: 1, green: 0, blue: 0, alpha: 0)
        let to = ParamStored.color(red: 0, green: 0, blue: 1, alpha: 1)
        #expect(Automation.blend(from, to, 0) == from)
        #expect(Automation.blend(from, to, 1) == to)
        guard case .color(let r, let g, let b, let a) = Automation.blend(from, to, 0.5) else {
            Issue.record("a color blend answered another kind"); return
        }
        #expect(abs(a - 0.5) < 1e-9)
        #expect(r < 1 && r > 0)
        #expect(b < 1 && b > 0)
        _ = g
    }

    // MARK: Playing it back

    /// The position reads the clock: speed scales it, start offsets it, and a
    /// backwards pass is the mirror of the forward one.
    @Test func speedAndDirectionReadTheClock() {
        var forward = Automation(tracks: [.init(name: "n", keys: [
            .init(at: 0, .number(0), curve: .linear), .init(at: 4, .number(100), curve: .linear),
        ])])
        #expect(forward.duration == 4)
        #expect(forward.position(at: 2) == 2)

        forward.speed = 2
        #expect(forward.position(at: 2) == 4)

        var backward = forward
        backward.speed = -1
        backward.start = backward.duration
        for step in 0...8 {
            let t = Double(step) / 2
            #expect(backward.value(of: "n", at: t) == forward.value(of: "n", at: 0)
                    || backward.position(at: t) == 4 - t)
        }
        #expect(backward.value(of: "n", at: 1) == .number(75))
        #expect(backward.value(of: "n", at: 3) == .number(25))
    }

    /// A looping automation wraps at its duration, forwards and backwards, and
    /// `length` moves where the wrap falls so a pass can hold past its last key.
    @Test func loopingWrapsAtTheDuration() {
        var automation = Automation(tracks: [.init(name: "n", keys: [
            .init(at: 0, .number(0), curve: .linear), .init(at: 4, .number(100), curve: .linear),
        ])], loops: true)
        #expect(automation.position(at: 4.5) == 0.5)
        #expect(automation.position(at: 9) == 1)
        automation.speed = -1
        #expect(automation.position(at: 1) == 3)     // wrapped back into the span
        automation.speed = 1
        automation.length = 8
        #expect(automation.duration == 8)
        #expect(automation.value(of: "n", at: 6) == .number(100))   // holds past the last key
        #expect(automation.position(at: 9) == 1)
    }

    /// Nothing drives a knob no track names.
    @Test func anUnnamedKnobIsUntouched() {
        let automation = Automation(tracks: [.init(name: "n", keys: [.init(at: 0, .number(1))])])
        #expect(automation.value(of: "missing", at: 0) == nil)
        #expect(automation.track(named: "n") != nil)
    }

    /// Adding a track for a knob that already has one replaces it.
    @Test func aSecondTrackForOneKnobReplacesTheFirst() {
        var automation = Automation()
        automation.setTrack(.init(name: "n", keys: [.init(at: 0, .number(1))]))
        automation.setTrack(.init(name: "n", keys: [.init(at: 0, .number(2))]))
        automation.setTrack(.init(name: "m", keys: [.init(at: 0, .number(3))]))
        #expect(automation.tracks.count == 2)
        #expect(automation.value(of: "n", at: 0) == .number(2))
    }

    // MARK: The file

    /// An automation round-trips through its file unchanged, and a file from a
    /// format this Ollin does not read is refused rather than guessed at.
    @Test func theFileRoundTripsAndRefusesAnotherFormat() throws {
        let automation = Automation(tracks: [
            .init(name: "radius", keys: [
                .init(at: 0, .number(40), curve: .easeInOut),
                .init(at: 2, .number(320), curve: .bezier(x1: 0.2, y1: 0.9, x2: 0.4, y2: 1)),
                .init(at: 4, .color(red: 1, green: 0.5, blue: 0, alpha: 1), curve: .hold),
            ]),
            .init(name: "mix", keys: [.init(at: 1, .vector(x: 3, y: 4), curve: .linear)]),
        ], loops: true, speed: 1.5, start: 0.25, length: 6)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollin-automation-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try automation.write(to: url)
        #expect(try Automation.load(from: url) == automation)

        var stale = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] ?? [:]
        stale["version"] = Automation.currentVersion + 1
        try JSONSerialization.data(withJSONObject: stale).write(to: url)
        #expect(throws: AutomationError.self) { try Automation.load(from: url) }
    }

    // MARK: Driving a sketch

    /// A knob under a curve, a knob that is left alone, and a smoothed knob,
    /// so a run shows the curve reaching the sketch and no second glide on top
    /// of it.
    private final class Directed: Sketch {
        @Param(0...400) var radius = 10.0
        @Param(0...1, smoothing: .eased(0.5)) var mix = 0.0
        @Param(0...10) var untouched = 4.0
        var seen: [Double] = []

        override func setup() {
            automate($radius) { track in
                track.key(at: 0, 0, curve: .linear)
                track.key(at: 4, 400, curve: .linear)
            }
            automate($mix) { track in
                track.key(at: 0, 0, curve: .linear)
                track.key(at: 4, 1, curve: .linear)
            }
        }

        override func draw() { seen.append(radius) }
    }

    /// The value the sketch reads each frame is the value the curve holds at
    /// that frame's clock, including for a knob that carries smoothing: the
    /// curve is the glide, so nothing eases into it a second time.
    @Test func theSketchReadsTheCurve() {
        let sketch = Directed()
        sketch.setCanvasSize(width: 64, height: 64)
        sketch.setup()
        #expect(sketch.automation?.tracks.count == 2)
        for frame in 1...8 {
            let t = Double(frame) / 2
            sketch.advance(time: t, deltaTime: 0.5, frameRate: 2)
            sketch.draw()
            #expect(abs(sketch.radius - t * 100) < 1e-9, "radius at \(t)")
            #expect(abs(sketch.mix - t / 4) < 1e-9, "smoothed knob at \(t)")
        }
        #expect(sketch.untouched == 4)
        #expect(sketch.seen.count == 8)
    }

    /// A run recorded while an automation played writes the knob values down
    /// on the frames they held, so the take replays the same performance with
    /// no automation attached.
    @Test func aRecordedRunWritesDownWhatTheCurveHeld() {
        let sketch = Directed()
        sketch.setCanvasSize(width: 64, height: 64)
        sketch.takeRecorder = TakeRecorder(sketch: sketch)
        sketch.setup()
        for frame in 1...8 {
            sketch.advance(time: Double(frame) / 2, deltaTime: 0.5, frameRate: 2)
            sketch.draw()
        }
        let take = sketch.takeRecorder!.take
        #expect(take.frameCount == 8)
        // Frame k advanced to time (k + 1)/2, so its radius is that much of
        // the ramp; the change stamped k must carry exactly that value.
        for change in take.changes where change.name == "radius" {
            let expected = Double(change.frame + 1) / 2 * 100
            guard case .number(let value) = change.value else {
                Issue.record("the radius change is not a number"); return
            }
            #expect(abs(value - expected) < 1e-9, "frame \(change.frame)")
        }
        #expect(take.changes.contains { $0.name == "radius" })
    }

    /// A track naming a knob the sketch does not declare is skipped, and the
    /// other tracks still play.
    @Test func aTrackForAnUnknownKnobIsSkipped() {
        let sketch = Directed()
        sketch.setCanvasSize(width: 64, height: 64)
        sketch.setup()
        sketch.automate(.init(name: "notAKnob", keys: [.init(at: 0, .number(99))]))
        sketch.advance(time: 2, deltaTime: 0.5, frameRate: 2)
        #expect(abs(sketch.radius - 200) < 1e-9)
        #expect(sketch.untouched == 4)
    }
}

// MARK: - A knob driven by a formula

/// The other half of a track: instead of values placed at moments, a rule
/// worked out every frame. The claims worth pinning are the ones that decide
/// whether a picture is reproducible: which clock the formula reads, whether
/// two formulas can see each other's new values, and whether the answer
/// survives a trip through a file.
@Suite
@MainActor
struct FormulaTrackTests {

    private final class Driven: Sketch {
        @Param(0...400) var radius = 10.0
        @Param(0...100) var half = 0.0
        @Param(1...100) var count = 1
        @Param var lit = false

        override func setup() {
            drive($radius, "120 + sin(time * tau) * 40")
            drive($half, "radius / 4")
            drive($count, "time * 10")
            drive($lit, "time % 2 < 1")
        }
    }

    /// The knob a sketch reads is the formula worked out at that frame's clock,
    /// and each kind of knob takes the number the way its own type can: a whole
    /// number rounds, and a switch is on for anything but zero.
    @Test func theSketchReadsTheFormula() {
        let sketch = Driven()
        sketch.setCanvasSize(width: 64, height: 64)
        sketch.setup()
        #expect(sketch.automation?.tracks.count == 4)
        for frame in 1...8 {
            let t = Double(frame) / 4
            sketch.advance(time: t, deltaTime: 0.25, frameRate: 4)
            let expected = 120 + sin(t * .pi * 2) * 40
            #expect(abs(sketch.radius - expected) < 1e-9, "radius at \(t)")
            #expect(abs(sketch.half - expected / 4) < 1e-9, "a knob worked out from another at \(t)")
            #expect(sketch.count == Int((t * 10).rounded()), "a whole number at \(t)")
            #expect(sketch.lit == (t.truncatingRemainder(dividingBy: 2) < 1), "a switch at \(t)")
        }
    }

    /// A knob worked out from another lands on the same frame's numbers, and it
    /// does so whichever order the tracks sit in: the one named is set first.
    /// Reading in track order instead would give a knob its neighbor's value
    /// from the frame before, which would make the picture depend on the frame
    /// rate, and a 30-a-second export would not match the 60-a-second window.
    @Test func aKnobWorkedOutFromAnotherLandsOnTheSameFrame() {
        final class Chain: Sketch {
            @Param(0...100) var a = 0.0
            @Param(0...100) var b = 0.0
            @Param(0...100) var c = 0.0
        }

        func run(reversed: Bool) -> (Double, Double, Double) {
            let sketch = Chain()
            sketch.setCanvasSize(width: 64, height: 64)
            var automation = Automation(tracks: [
                .init(name: "c", formula: try! Formula("b + 1")),
                .init(name: "b", formula: try! Formula("a + 1")),
                .init(name: "a", formula: try! Formula("time * 10")),
            ])
            if reversed { automation.tracks.reverse() }
            sketch.automation = automation
            sketch.advance(time: 0.5, deltaTime: 0.5, frameRate: 2)
            return (sketch.a, sketch.b, sketch.c)
        }

        #expect(run(reversed: false) == (5, 6, 7))
        #expect(run(reversed: true) == (5, 6, 7))
    }

    /// A knob worked out from one that is worked out from it cannot settle on a
    /// single frame. The whole ring is left alone rather than played at a value
    /// that would depend on the frame rate, and a knob outside the ring still
    /// plays.
    @Test func knobsThatNameEachOtherAreLeftAlone() {
        final class Ring: Sketch {
            @Param(0...100) var a = 3.0
            @Param(0...100) var b = 5.0
            @Param(0...100) var n = 7.0
            @Param(0...100) var fine = 0.0
        }
        let sketch = Ring()
        sketch.setCanvasSize(width: 64, height: 64)
        sketch.automation = Automation(tracks: [
            .init(name: "a", formula: try! Formula("b + 1")),
            .init(name: "b", formula: try! Formula("a + 1")),
            .init(name: "n", formula: try! Formula("n + 1")),      // itself, the shortest ring
            .init(name: "fine", formula: try! Formula("time * 2")),
        ])
        sketch.advance(time: 1, deltaTime: 0.5, frameRate: 2)
        #expect(sketch.a == 3)
        #expect(sketch.b == 5)
        #expect(sketch.n == 7)
        #expect(sketch.fine == 2)
        // And it stays left alone rather than creeping frame by frame.
        sketch.advance(time: 2, deltaTime: 0.5, frameRate: 2)
        #expect(sketch.n == 7)
    }

    /// `frame` is the number the frame about to be drawn will carry, because a
    /// track is applied before the sketch steps its counter. A formula reading
    /// `frame` and the sketch reading `frameCount` must agree, or a stepped
    /// look lands one frame off what it says.
    @Test func frameIsTheNumberTheFrameWillCarry() {
        final class Counting: Sketch {
            @Param(0...1000) var n = 0
            var pairs: [(Int, Int)] = []
            override func setup() { drive($n, "frame") }
            override func draw() { pairs.append((frameCount, n)) }
        }
        let sketch = Counting()
        sketch.setCanvasSize(width: 64, height: 64)
        sketch.setup()
        for frame in 1...5 {
            sketch.advance(time: Double(frame) / 10, deltaTime: 0.1, frameRate: 10)
            sketch.draw()
        }
        #expect(sketch.pairs.count == 5)
        for (counted, read) in sketch.pairs { #expect(counted == read) }
    }

    /// A formula reads `time` as where the *automation* stands, not as the raw
    /// sketch clock, so `speed`, `start`, and `loops` shape it exactly as they
    /// shape a curve. Anything else handed in under that name is overruled.
    @Test func theFormulaReadsWhereTheAutomationStands() {
        let track = Automation.Track(name: "n", formula: try! Formula("time * 10"))
        #expect(track.value(at: 3) == .number(30))
        #expect(track.value(at: 3, reading: ["time": 99]) == .number(30))

        var automation = Automation(tracks: [track], loops: true, speed: 2, start: 1, length: 4)
        #expect(automation.value(of: "n", at: 0) == .number(10))     // start
        #expect(automation.value(of: "n", at: 1) == .number(30))     // start + 1 * speed
        #expect(automation.value(of: "n", at: 2) == .number(10))     // wrapped at length 4
        automation.loops = false
        #expect(automation.value(of: "n", at: 2) == .number(50))
    }

    /// A formula reaches the sketch's own noise field, so `noiseSeed()`
    /// reproduces a wandering knob the same way it reproduces a drawn one.
    @Test func aWanderingKnobFollowsTheSketchSeed() {
        final class Wandering: Sketch {
            @Param(0...1) var drift = 0.0
            override func setup() { drive($drift, "noise(time)") }
        }
        func run(seed: Int) -> Double {
            let sketch = Wandering()
            sketch.setCanvasSize(width: 64, height: 64)
            sketch.noiseSeed(seed)
            sketch.setup()
            sketch.advance(time: 0.7, deltaTime: 0.1, frameRate: 10)
            return sketch.drift
        }
        #expect(run(seed: 7) == run(seed: 7))
        #expect(run(seed: 7) != run(seed: 8))
    }

    /// A formula track travels as the text it was written as, so a person can
    /// read and edit it in the file, and it comes back working.
    @Test func aFormulaTrackRoundTripsThroughItsFile() throws {
        let automation = Automation(tracks: [
            .init(name: "radius", formula: try Formula("120 + sin(time * tau) * 40")),
            .init(name: "tint", keys: [.init(at: 0, .number(1))]),
        ], loops: true, length: 4)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollin-formula-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try automation.write(to: url)

        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("120 + sin(time * tau) * 40"), "the text itself is in the file")

        let read = try Automation.load(from: url)
        #expect(read == automation)
        #expect(read.value(of: "radius", at: 1) == automation.value(of: "radius", at: 1))
    }

    /// A file whose formula cannot be read is refused when it is read, rather
    /// than loading as a knob that quietly holds zero.
    @Test func aFileWithUnreadableTextIsRefused() throws {
        let json = """
        {"version": 2, "loops": false, "speed": 1, "start": 0,
         "tracks": [{"name": "radius", "formula": "sin(("}]}
        """
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollin-formula-bad-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(json.utf8).write(to: url)
        #expect(throws: (any Error).self) { try Automation.load(from: url) }
    }

    /// An automation written before formulas existed still reads, because every
    /// layout so far only added to the one before it. A newer one is still
    /// refused.
    @Test func anOlderFileStillReads() throws {
        let json = """
        {"version": 1, "loops": false, "speed": 1, "start": 0,
         "tracks": [{"name": "radius", "keys": [{"time": 0, "value": {"number": {"_0": 5}},
                                                 "curve": {"linear": {}}}]}]}
        """
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollin-formula-old-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(json.utf8).write(to: url)
        let read = try Automation.load(from: url)
        #expect(read.value(of: "radius", at: 0) == .number(5))
    }

    /// Text that cannot be read costs that one knob, never the sketch: the
    /// knob keeps the value it was given.
    @Test func aTypoLeavesTheKnobAlone() {
        final class Mistyped: Sketch {
            @Param(0...400) var radius = 42.0
            override func setup() { drive($radius, "120 + sin(") }
        }
        let sketch = Mistyped()
        sketch.setCanvasSize(width: 64, height: 64)
        sketch.setup()
        #expect(sketch.automation == nil)
        sketch.advance(time: 1, deltaTime: 0.1, frameRate: 10)
        #expect(sketch.radius == 42)
    }
}

// MARK: - A knob of more than one number, one rule per part

/// A point, a color, a rectangle, a set of insets, and a pair of ends each hold
/// several numbers, so each takes several rules. The claims worth pinning are
/// the ones a picture cannot show: that a part with no rule is left alone, that
/// one part of a knob is a name another rule can read on the same frame, that
/// the knob's own range still holds, and that the whole thing survives a trip
/// through a file.
@Suite
@MainActor
struct FormulaPartTests {

    private final class Parted: Sketch {
        @Param(x: 0...1000, y: 0...1000) var spot = Vector2(10, 20)
        @Param(x: -10...10, y: -10...10, z: -10...10) var eye = Vector3(0, 0, 0)
        @Param var tint = Color(red: 0.1, green: 0.2, blue: 0.3, alpha: 1)
        @Param(x: 0...500, y: 0...500, width: 0...500, height: 0...500)
        var box = Rectangle(x: 0, y: 0, width: 10, height: 10)
        @Param(0...100) var pad = Insets(top: 1, right: 2, bottom: 3, left: 4)
        @Param(in: 0...100) var span = 10.0...20.0
    }

    private static func made() -> Parted {
        let sketch = Parted()
        sketch.setCanvasSize(width: 64, height: 64)
        return sketch
    }

    /// Every knob that holds more than one number takes a rule for each part,
    /// and each number lands where its part is named.
    @Test func everyKindOfKnobTakesARuleForEachPart() {
        let sketch = Self.made()
        sketch.drive(sketch.$spot, x: "time * 10", y: "time * 20")
        sketch.drive(sketch.$eye, x: "1", y: "2", z: "3")
        sketch.drive(sketch.$tint, red: "0.5", green: "0.25", blue: "0.125", alpha: "0.75")
        sketch.drive(sketch.$box, x: "4", y: "5", width: "6", height: "7")
        sketch.drive(sketch.$pad, top: "8", right: "9", bottom: "10", left: "11")
        sketch.drive(sketch.$span, lower: "20", upper: "80")
        sketch.advance(time: 2, deltaTime: 0.5, frameRate: 2)

        #expect(sketch.spot == Vector2(20, 40))
        #expect(sketch.eye == Vector3(1, 2, 3))
        #expect(sketch.tint == Color(red: 0.5, green: 0.25, blue: 0.125, alpha: 0.75))
        #expect(sketch.box == Rectangle(x: 4, y: 5, width: 6, height: 7))
        #expect(sketch.pad == Insets(top: 8, right: 9, bottom: 10, left: 11))
        #expect(sketch.span == 20...80)
    }

    /// A part with no rule keeps whatever the knob holds, and the hand still
    /// reaches it while the part beside it plays. That is the whole point of a
    /// rule per part: one part directed, the rest still yours.
    @Test func aPartWithNoRuleIsLeftAlone() {
        let sketch = Self.made()
        sketch.spot = Vector2(3, 77)
        sketch.drive(sketch.$spot, x: "time * 10")
        sketch.advance(time: 1, deltaTime: 0.5, frameRate: 2)
        #expect(sketch.spot == Vector2(10, 77))

        sketch.spot = Vector2(0, 500)             // the hand moves the free part
        sketch.advance(time: 2, deltaTime: 0.5, frameRate: 2)
        #expect(sketch.spot == Vector2(20, 500))
    }

    /// One part of a knob is a name a rule can read, and it lands on the same
    /// frame whichever order the tracks sit in. Reading in track order instead
    /// would give the frame before's number, which would make the picture
    /// depend on the frame rate.
    @Test func aRuleReadsOnePartOnTheSameFrame() {
        final class Pair: Sketch {
            @Param(x: 0...1000, y: 0...1000) var spot = Vector2(0, 0)
            @Param(0...1000) var radius = 0.0
        }

        func run(reversed: Bool) -> (Vector2, Double) {
            let sketch = Pair()
            sketch.setCanvasSize(width: 64, height: 64)
            var automation = Automation(tracks: [
                .init(name: "radius", formula: try! Formula("spot.x / 2")),
                .init(name: "spot", parts: ["x": try! Formula("time * 100"),
                                              "y": try! Formula("time * 10")]),
            ])
            if reversed { automation.tracks.reverse() }
            sketch.automation = automation
            sketch.advance(time: 0.5, deltaTime: 0.5, frameRate: 2)
            return (sketch.spot, sketch.radius)
        }

        #expect(run(reversed: false) == (Vector2(50, 5), 25))
        #expect(run(reversed: true) == (Vector2(50, 5), 25))
    }

    /// The part a *keyed* track moves is a name as well, so a rule can follow a
    /// point that is being carried between two placed values.
    @Test func aRuleReadsOnePartOfAKeyedKnob() {
        final class Keyed: Sketch {
            @Param(x: 0...1000, y: 0...1000) var spot = Vector2(0, 0)
            @Param(0...1000) var radius = 0.0

            override func setup() {
                automate($spot) { track in
                    track.key(at: 0, Vector2(0, 0), curve: .linear)
                    track.key(at: 1, Vector2(100, 40))
                }
                drive($radius, "spot.x / 2")
            }
        }
        let sketch = Keyed()
        sketch.setCanvasSize(width: 64, height: 64)
        sketch.setup()
        sketch.advance(time: 0.5, deltaTime: 0.5, frameRate: 2)
        #expect(sketch.spot == Vector2(50, 20))
        #expect(sketch.radius == 25)
    }

    /// A part worked out from another part of the same knob cannot settle on
    /// one frame, so the whole knob is left alone rather than played at a value
    /// that would depend on the frame rate. A knob outside the ring still plays.
    @Test func aPartThatNamesItsOwnKnobIsLeftAlone() {
        final class Ring: Sketch {
            @Param(x: 0...1000, y: 0...1000) var spot = Vector2(3, 5)
            @Param(0...100) var fine = 0.0
        }
        let sketch = Ring()
        sketch.setCanvasSize(width: 64, height: 64)
        sketch.automation = Automation(tracks: [
            .init(name: "spot", parts: ["x": try! Formula("spot.y + 1"),
                                          "y": try! Formula("time")]),
            .init(name: "fine", formula: try! Formula("time * 2")),
        ])
        sketch.advance(time: 1, deltaTime: 0.5, frameRate: 2)
        #expect(sketch.spot == Vector2(3, 5))
        #expect(sketch.fine == 2)
        sketch.advance(time: 2, deltaTime: 0.5, frameRate: 2)
        #expect(sketch.spot == Vector2(3, 5))     // and it never creeps
    }

    /// The knob's own range still holds, exactly as it does when a hand drags
    /// the field. A rule is a way to set a knob, never a way past it.
    @Test func theKnobsOwnRangeStillHolds() {
        let sketch = Self.made()
        sketch.drive(sketch.$spot, x: "0 - 500", y: "9999")
        sketch.advance(time: 1, deltaTime: 0.5, frameRate: 2)
        #expect(sketch.spot == Vector2(0, 1000))
    }

    /// A pair of ends stays ordered, because a crossed pair is not a value the
    /// knob can hold. The lower end wins and the upper end is lifted to meet
    /// it, the way the two-thumb slider behaves under a hand.
    @Test func thePairOfEndsStaysOrdered() {
        let climbing = Self.made()
        climbing.drive(climbing.$span, lower: "time * 30")
        climbing.advance(time: 2, deltaTime: 0.5, frameRate: 2)
        #expect(climbing.span == 60...60)

        let falling = Self.made()
        falling.drive(falling.$span, upper: "5")
        falling.advance(time: 1, deltaTime: 0.5, frameRate: 2)
        #expect(falling.span == 10...10)
    }

    /// Every part a value reports is a part it takes back: writing a value's
    /// own numbers into it changes nothing, and a number written to one part
    /// reads back from that same part. A mismatch between the two would drive
    /// the wrong part, or none at all, and no picture would say which.
    @Test func everyPartReadsBackWhatWasWrittenToIt() {
        let values: [ParamStored] = [
            .vector(x: 1, y: 2),
            .vector3(x: 1, y: 2, z: 3),
            .color(red: 0.1, green: 0.2, blue: 0.3, alpha: 0.4),
            .rectangle(x: 1, y: 2, width: 3, height: 4),
            .insets(top: 1, right: 2, bottom: 3, left: 4),
            .range(lower: 1, upper: 2),
        ]
        for stored in values {
            let parts = Automation.parts(of: stored)
            #expect(!parts.isEmpty, "\(stored) has parts")
            #expect(Automation.applying(parts, to: stored) == stored, "\(stored) round trips")
            for name in parts.keys {
                let moved = Automation.applying([name: 42], to: stored)
                #expect(Automation.parts(of: moved)[name] == 42, "\(stored) part \(name)")
            }
        }
    }

    /// A knob that is one number, a switch, a menu choice, or a piece of text
    /// has no parts at all, so nothing there can be driven part by part.
    @Test func aKnobOfOneNumberHasNoParts() {
        for stored: ParamStored in [.number(3), .boolean(true), .option("a"), .text("b")] {
            #expect(Automation.parts(of: stored).isEmpty, "\(stored)")
            #expect(Automation.applying(["x": 9], to: stored) == stored, "\(stored)")
        }
    }

    /// A track of parts travels as the text it was written as, so a person can
    /// read and edit the rules in the file, and they come back working.
    @Test func aTrackOfPartsRoundTripsThroughItsFile() throws {
        let automation = Automation(tracks: [
            .init(name: "spot", parts: ["x": try Formula("width / 2 + sin(time) * 100"),
                                          "y": try Formula("height / 2")]),
            .init(name: "radius", formula: try Formula("time * 4")),
        ], loops: true, length: 4)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollin-parts-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try automation.write(to: url)

        let text = try String(contentsOf: url, encoding: .utf8)
        // JSON writes a slash as `\/`, so the check reads a fragment without one.
        #expect(text.contains("sin(time) * 100"), "the text itself is in the file")

        let read = try Automation.load(from: url)
        #expect(read == automation)
        #expect(read.track(named: "spot")?.parts.count == 2)
        #expect(read.track(named: "spot")?
            .partValues(at: 0, reading: ["width": 200, "height": 80]) == ["x": 100, "y": 40])
    }

    /// A file whose part rule cannot be read is refused when it is read, rather
    /// than loading as a part that quietly holds zero.
    @Test func aFileWithAnUnreadablePartIsRefused() throws {
        let json = """
        {"version": 3, "loops": false, "speed": 1, "start": 0,
         "tracks": [{"name": "spot", "parts": {"x": "sin((", "y": "1"}}]}
        """
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollin-parts-bad-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(json.utf8).write(to: url)
        #expect(throws: (any Error).self) { try Automation.load(from: url) }
    }

    /// Text that cannot be read costs that one part, never the knob beside it.
    @Test func aTypoCostsOnePartOnly() {
        let sketch = Self.made()
        sketch.spot = Vector2(7, 0)
        sketch.drive(sketch.$spot, x: "time * (", y: "time * 10")
        sketch.advance(time: 1, deltaTime: 0.5, frameRate: 2)
        #expect(sketch.spot == Vector2(7, 10))
    }

    /// A call that names no part at all leaves the knob alone rather than
    /// writing an empty track that would look like a rule and do nothing.
    @Test func noRuleAtAllLeavesTheKnobAlone() {
        let sketch = Self.made()
        sketch.drive(sketch.$spot)
        #expect(sketch.automation == nil)
        sketch.advance(time: 1, deltaTime: 0.5, frameRate: 2)
        #expect(sketch.spot == Vector2(10, 20))
    }

    /// One call carries the whole knob, so a second call replaces the first
    /// rather than adding to it. Give every part in one call.
    @Test func aSecondCallReplacesTheFirst() {
        let sketch = Self.made()
        sketch.spot = Vector2(7, 0)
        sketch.drive(sketch.$spot, x: "500")
        sketch.drive(sketch.$spot, y: "time * 10")
        #expect(sketch.automation?.tracks.count == 1)
        sketch.advance(time: 1, deltaTime: 0.5, frameRate: 2)
        #expect(sketch.spot == Vector2(7, 10))
    }
}
