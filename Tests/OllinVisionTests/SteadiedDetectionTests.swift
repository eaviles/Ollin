import Foundation
import Ollin
import Testing
@testable import OllinVision

/// The detectors' results held steady, on what the detectors really found:
/// the recordings in `Recordings` are a table of things, a desk of
/// rectangles, and a dancer, each read frame by frame through the real
/// detector (`SteadiedRecordingWriter` makes them). Nothing in the first two
/// pictures moves, so every step a box takes there is shake and every time
/// one goes away is a blink.
@Suite struct SteadiedDetectionTests {

    static func objects(_ name: String) throws -> (frames: [[Detection]], rate: Double) {
        let recording = try SteadiedRecording.load(name)
        return (recording.frames.map { $0.map(\.detection) }, recording.rate)
    }

    static func rectangles(_ name: String) throws -> (frames: [[DetectedRectangle]], rate: Double) {
        let recording = try SteadiedRecording.load(name)
        return (recording.frames.map { $0.map(\.rectangle) }, recording.rate)
    }

    /// The things that were showing on every drawn frame of a run.
    static func lasting(_ measure: SteadiedMeasure) -> [Int] {
        measure.stepsByThing.filter { $0.value.count == measure.drawnFrames }.keys.sorted()
    }

    static func p95(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        return sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
    }

    // MARK: The table of things

    @Test func theTablesThingsStopBlinking() throws {
        let (frames, rate) = try Self.objects("objects-noisy")
        // As found, a thing comes and goes dozens of times in ten seconds.
        let raw = SteadiedMeasure.raw(frames, rate: rate, skip: 15)
        #expect(raw.appeared > 50, "\(raw.appeared)")

        let steady = SteadiedMeasure.run(frames, rate: rate, steadier: Steadier<Detection>(), skip: 15)
        // Steadied, the three the detector finds on every frame are there on
        // every frame, and the two it finds on and off come and go a few times
        // between them rather than a hundred.
        #expect(Self.lasting(steady).count >= 3, "\(Self.lasting(steady))")
        #expect(steady.appeared <= 3 && steady.letGo <= 3, "appeared \(steady.appeared), let go \(steady.letGo)")
    }

    @Test func theTablesThingsMoveUnderAPixel() throws {
        let (frames, rate) = try Self.objects("objects-noisy")
        let steady = SteadiedMeasure.run(frames, rate: rate, steadier: Steadier<Detection>(), skip: 15)
        let lasting = Self.lasting(steady)
        #expect(lasting.count >= 3)
        // The detector gives one of the cups two boxes of different sizes, a
        // frame of one and a frame of the other, and no smoothing makes those
        // one box. The others are held to under a pixel a frame.
        let calm = lasting.filter { Self.p95(steady.stepsByThing[$0]!) < 1 }
        #expect(calm.count >= 3, "\(lasting.map { Self.p95(steady.stepsByThing[$0]!) })")

        // The same things as found step several pixels at a time.
        var shake: [Double] = []
        for (a, b) in zip(frames, frames.dropFirst()) {
            for thing in a {
                guard let same = b.first(where: { $0.label == thing.label && abs($0.boundsN.x - thing.boundsN.x) < 0.02 })
                else { continue }
                shake.append(SteadiedMeasure.step(from: thing.steadyPoints, to: same.steadyPoints))
            }
        }
        #expect(Self.p95(shake) > 4, "\(Self.p95(shake)) px")
    }

    @Test func aSteadiedDetectionKeepsItsLabelAndConfidence() throws {
        let (frames, rate) = try Self.objects("objects-noisy")
        var steadier = Steadier<Detection>()
        var labels = Set<String>()
        for found in frames.prefix(60) {
            for _ in 0..<Int(SteadiedMeasure.drawRate / rate) {
                for thing in steadier.steady(found, deltaTime: 1 / SteadiedMeasure.drawRate) {
                    #expect(thing.value.label == thing.found.label)
                    #expect(thing.value.confidence == thing.found.confidence)
                    labels.insert(thing.value.label)
                }
            }
        }
        #expect(labels.isSuperset(of: ["cup", "bowl", "sandwich"]), "\(labels.sorted())")

        let moved = Detection(label: "cup", confidence: 0.7, boundsN: Rectangle(x: 0.1, y: 0.2, width: 0.3, height: 0.4))
            .steadied(at: [Vector2(0.2, 0.3), Vector2(0.6, 0.8)])
        #expect(moved.label == "cup" && moved.confidence == 0.7)
        #expect(abs(moved.boundsN.x - 0.2) < 1e-12 && abs(moved.boundsN.width - 0.4) < 1e-12)
        #expect(abs(moved.boundsN.y - 0.3) < 1e-12 && abs(moved.boundsN.height - 0.5) < 1e-12)
    }

    // MARK: The desk of rectangles

    @Test func theDesksRealRectanglesStayAndTheInventedOnesNeverShow() throws {
        let (frames, rate) = try Self.rectangles("rectangles-noisy")
        // As found there are seven or eight quads a frame, most of them a
        // different quad about the round cup every time.
        let raw = SteadiedMeasure.raw(frames, rate: rate, skip: 15)
        #expect(Double(raw.shownFrames) / Double(raw.drawnFrames) > 6.5)
        #expect(raw.appeared > 200, "\(raw.appeared)")

        // Steadied with the detector's own settings, the rectangles that are
        // really there stay for the whole run and hardly move.
        let steady = SteadiedMeasure.run(frames, rate: rate, steadier: Steadier<DetectedRectangle>(), skip: 15)
        let lasting = Self.lasting(steady)
        #expect(lasting.count >= 3, "\(lasting)")
        for id in lasting {
            let steps = steady.stepsByThing[id]!.sorted()
            #expect(steps[steps.count / 2] < 1, "thing \(id): \(steps[steps.count / 2]) px")
        }
        // And once one is showing it is never let go.
        #expect(steady.appeared <= 3 && steady.letGo == 0, "appeared \(steady.appeared), let go \(steady.letGo)")
        // Every thing that showed at all moved little: the invented quads,
        // which jump a hundred pixels at a time, are not among them.
        for (id, steps) in steady.stepsByThing {
            #expect(Self.p95(steps) < 20, "thing \(id): p95 \(Self.p95(steps)) px")
        }
    }

    @Test func aRectangleThatIsShowingIsFollowedMoreLooselyThanItWasAdmitted() throws {
        let (frames, rate) = try Self.rectangles("rectangles-noisy")
        // The detector gives a real rectangle slightly different corners from
        // frame to frame. Held to the overlap it was admitted at, one of the
        // three that last is let go partway and another is let go and found again.
        var strict = DetectedRectangle.steadiness
        strict.minKeptOverlap = strict.minOverlap
        let held = SteadiedMeasure.run(frames, rate: rate, steadier: Steadier<DetectedRectangle>(strict), skip: 15)
        #expect(Self.lasting(held).count == 2, "\(Self.lasting(held))")
        #expect(held.letGo >= 1)
    }

    @Test func theRectangleDetectorsOwnSettingsAreWhatKeepTheInventedOnesOut() throws {
        let (frames, rate) = try Self.rectangles("rectangles-noisy")
        #expect(DetectedRectangle.steadiness == Steadiness(appearDelay: 0.25, minOverlap: 0.8, minKeptOverlap: 0.5))
        // With the settings a box gets, the quads about the cup overlap one
        // another enough to pass for things that hop.
        let loose = SteadiedMeasure.run(frames, rate: rate, steadier: Steadier<DetectedRectangle>(Steadiness()), skip: 15)
        let hopping = loose.stepsByThing.values.filter { $0.count > 300 && Self.p95($0) > 40 }
        #expect(hopping.count >= 2, "\(loose.stepsByThing.mapValues { Self.p95($0) })")
    }

    @Test func aSteadiedRectangleKeepsItsCornersInTheDetectorsOrder() {
        let rectangle = DetectedRectangle(confidence: 0.9, topLeftN: Vector2(0.1, 0.8), topRightN: Vector2(0.5, 0.8),
                                          bottomRightN: Vector2(0.5, 0.3), bottomLeftN: Vector2(0.1, 0.3))
        #expect(rectangle.steadyPoints == [Vector2(0.1, 0.8), Vector2(0.5, 0.8), Vector2(0.5, 0.3), Vector2(0.1, 0.3)])
        #expect(rectangle.steadyConfidence == 0.9)
        let moved = rectangle.steadied(at: [Vector2(0.2, 0.9), Vector2(0.6, 0.9), Vector2(0.6, 0.4), Vector2(0.2, 0.4)])
        #expect(moved.topLeftN == Vector2(0.2, 0.9) && moved.topRightN == Vector2(0.6, 0.9))
        #expect(moved.bottomRightN == Vector2(0.6, 0.4) && moved.bottomLeftN == Vector2(0.2, 0.4))
        #expect(moved.confidence == 0.9)
    }

    // MARK: The dancer

    @Test func aMovingThingIsOneThingAndIsFollowed() throws {
        let (frames, rate) = try Self.objects("objects-film")
        // The detector loses the dancer on nearly a third of the frames, in
        // runs of up to seven.
        let found = frames.filter { !$0.isEmpty }.count
        #expect(found < 230 && found > 180, "\(found)")
        let raw = SteadiedMeasure.raw(frames, rate: rate, skip: 15)
        #expect(raw.appeared > 20)

        let steady = SteadiedMeasure.run(frames, rate: rate, steadier: Steadier<Detection>(), skip: 15)
        #expect(steady.appeared <= 2, "\(steady.appeared)")
        // Showing nine frames in ten, against seven in ten as found.
        #expect(Double(steady.shownFrames) / Double(steady.drawnFrames) > 0.85)
        // A box some 400 pixels wide whose edges swing with his arms: half
        // the time under 18 pixels behind where it was last found.
        let behind = steady.behind.sorted()
        #expect(behind[behind.count / 2] < 18, "\(behind[behind.count / 2]) px")
        #expect(Self.p95(behind) < 65, "\(Self.p95(behind)) px")
    }
}
