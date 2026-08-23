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
        #expect(Automation.blend(.rect(x: 0, y: 0, width: 10, height: 20),
                                 .rect(x: 10, y: 10, width: 20, height: 20), 0.5)
                == .rect(x: 5, y: 5, width: 15, height: 20))
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
