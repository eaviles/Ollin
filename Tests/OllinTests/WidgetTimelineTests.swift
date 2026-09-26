import CoreGraphics
import Foundation
import Testing
@testable import Ollin

/// A widget's run, checked against the invariants the surface promises rather than
/// against a picture: the moments land on a grid counted from midnight, the
/// clock a picture is drawn on is the time of day, each picture gets a sketch
/// of its own and exactly one draw, the same moment always draws the same
/// picture, and two pictures differ exactly when the sketch's own clock says
/// they should. Every picture renders, so the suite wants Metal.
@MainActor
@Suite
struct WidgetTimelineTests {

    // MARK: Probes

    /// Writes down the clock it was drawn on, and counts its own lives.
    final class ClockProbe: Sketch {
        static var log: [(time: Double, deltaTime: Double, date: Date)] = []
        static var setups = 0
        static var draws = 0

        override var canvasSize: CanvasSize { .square(32) }
        override var widgetTimeline: WidgetTimeline { .every(minutes: 15, count: 4) }

        override func setup() { Self.setups += 1 }

        override func draw() {
            Self.draws += 1
            Self.log.append((time, deltaTime, date))
            background(.white)
        }

        static func reset() { log = []; setups = 0; draws = 0 }
    }

    /// A hand on a dial, one turn a day: two moments of the same day draw
    /// different pictures, and the same moment draws the same one.
    final class DialProbe: Sketch {
        override var canvasSize: CanvasSize { .square(48) }
        override var widgetTimeline: WidgetTimeline { .every(minutes: 15, count: 4) }

        override func draw() {
            background(.white)
            stroke(.black)
            strokeWeight(3)
            let angle = time / 86_400 * .pi * 2
            drawLine(width / 2, height / 2,
                     width / 2 + cos(angle) * 20, height / 2 + sin(angle) * 20)
        }
    }

    /// The same hand turning once per step, so every picture of a run catches
    /// it in the same place. The aliasing is real and worth pinning: a piece
    /// whose period divides the spacing never appears to move at all.
    final class AliasedProbe: Sketch {
        override var canvasSize: CanvasSize { .square(48) }
        override var widgetTimeline: WidgetTimeline { .every(minutes: 15, count: 4) }

        override func draw() {
            background(.white)
            stroke(.black)
            strokeWeight(3)
            let angle = time / (15 * 60) * .pi * 2
            drawLine(width / 2, height / 2,
                     width / 2 + cos(angle) * 20, height / 2 + sin(angle) * 20)
        }
    }

    private func pixels(of image: CGImage) -> [UInt8] {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return data
    }

    /// A moment of a fixed day, so nothing here depends on when the suite runs.
    private func moment(hour: Int, minute: Int, second: Int = 0) -> Date {
        var parts = DateComponents()
        parts.year = 2026; parts.month = 9; parts.day = 16
        parts.hour = hour; parts.minute = minute; parts.second = second
        return Calendar.current.date(from: parts)!
    }

    // MARK: The grid

    @Test("The pictures land on a grid counted from midnight")
    func momentsLandOnTheGrid() {
        let timeline = WidgetTimeline.every(minutes: 15, count: 4)
        let moments = timeline.moments(from: moment(hour: 14, minute: 7, second: 33))

        #expect(moments.count == 4)
        #expect(moments[0] == moment(hour: 14, minute: 0))
        #expect(moments[3] == moment(hour: 14, minute: 45))
        // Stepping by exactly the spacing is what lets a piece reason about
        // what passed between one picture and the next.
        for k in 1..<moments.count {
            #expect(moments[k].timeIntervalSince(moments[k - 1]) == 15 * 60)
        }
        // The first picture is never in the future, so the system has one to
        // put up the instant it asks.
        #expect(moments[0] <= moment(hour: 14, minute: 7, second: 33))
    }

    @Test("Two passes carry on the same grid")
    func passesAgreeOnTheGrid() {
        let timeline = WidgetTimeline.every(minutes: 15, count: 4)
        // Anywhere inside one step is the same step.
        #expect(timeline.gridMoment(atOrBefore: moment(hour: 9, minute: 0))
                == timeline.gridMoment(atOrBefore: moment(hour: 9, minute: 14, second: 59)))
        // And the pass that starts later is on the same grid, not on one of
        // its own: this is what keeps a piece stepping at the quarter hours
        // however often the system comes back.
        let later = timeline.moments(from: moment(hour: 9, minute: 40))
        #expect(later[0] == moment(hour: 9, minute: 30))
        #expect(later.contains(moment(hour: 10, minute: 15)))
    }

    @Test("A spacing that does not divide the day starts over at midnight")
    func theGridRestartsAtMidnight() {
        let timeline = WidgetTimeline.every(minutes: 7, count: 2)
        #expect(timeline.gridMoment(atOrBefore: moment(hour: 0, minute: 3)) == moment(hour: 0, minute: 0))
        #expect(timeline.gridMoment(atOrBefore: moment(hour: 0, minute: 13)) == moment(hour: 0, minute: 7))
    }

    @Test("A run says how long it covers, and refuses nonsense")
    func theShapeOfARun() {
        #expect(WidgetTimeline.every(minutes: 15, count: 4).span == 45 * 60)
        #expect(WidgetTimeline.every(hours: 1, count: 2).spacing == 3600)
        // A spacing of zero would be an endless run of one moment, and a count
        // of zero no picture at all.
        #expect(WidgetTimeline(spacing: 0, count: 0).spacing >= 1)
        #expect(WidgetTimeline(spacing: 0, count: 0).count == 1)
    }

    // MARK: The clock

    @Test("The clock a picture is drawn on is the time of day, and each picture gets its own sketch and exactly one draw")
    func theClockIsTheTimeOfDay() {
        ClockProbe.reset()
        let frames = OllinApp.widgetFrames(from: moment(hour: 14, minute: 7)) { ClockProbe() }

        #expect(frames.count == 4)
        #expect(ClockProbe.log.count == 4)
        // Nothing carries from one picture to the next, which is what makes a
        // moment draw the same whether it opened a pass or closed one.
        #expect(ClockProbe.setups == 4)
        #expect(ClockProbe.draws == 4)
        // Seconds since midnight, so `time / 3600` is the hour and the piece
        // reads the same at this moment tomorrow.
        #expect(ClockProbe.log[0].time == 14 * 3600)
        #expect(ClockProbe.log[3].time == 14 * 3600 + 45 * 60)
        // What really passed between this picture and the one before it.
        #expect(ClockProbe.log.allSatisfy { $0.deltaTime == 15 * 60 })
        // And the moment itself, for anything the calendar decides.
        #expect(ClockProbe.log[0].date == moment(hour: 14, minute: 0))
        #expect(frames[0].date == moment(hour: 14, minute: 0))
    }

    @Test("A caller can ask for fewer pictures than the sketch declared, drawn at the size that was asked for")
    func theSizeIsTheWidgetSize() {
        ClockProbe.reset()
        // The snapshot the system asks for before anything else is one picture.
        let frames = OllinApp.widgetFrames(from: moment(hour: 8, minute: 0),
                                           size: .size(120, 80), count: 1) { ClockProbe() }
        #expect(frames.count == 1)
        #expect(ClockProbe.draws == 1)
        let image = try! #require(frames.first?.image)
        #expect(image.width == 120)
        #expect(image.height == 80)
    }

    // MARK: The pictures

    @Test("The same moment always draws the same picture")
    func aMomentIsAPicture() {
        // Two passes that overlap, asked for at unrelated moments: only the
        // grid makes their moments line up at all, and only one picture per
        // moment makes the pictures match once they do.
        let early = OllinApp.widgetFrames(from: moment(hour: 11, minute: 2)) { DialProbe() }
        let late = OllinApp.widgetFrames(from: moment(hour: 11, minute: 19)) { DialProbe() }

        #expect(early[1].date == late[0].date)
        #expect(pixels(of: early[1].image) == pixels(of: late[0].image))
        #expect(pixels(of: early[3].image) == pixels(of: late[2].image))
    }

    @Test("Two pictures differ exactly when the clock says they should")
    func picturesDifferAsTheClockSays() {
        let turning = OllinApp.widgetFrames(from: moment(hour: 6, minute: 0)) { DialProbe() }
        let bytes = turning.map { pixels(of: $0.image) }
        // A hand that turns once a day is somewhere else a quarter hour later.
        for k in 1..<bytes.count {
            #expect(bytes[k] != bytes[0], "picture \(k) did not move")
        }

        // And the aliasing is not a bug in the run: a piece whose period is the
        // spacing is caught in the same place every time, so it never appears
        // to move at all.
        let aliased = OllinApp.widgetFrames(from: moment(hour: 6, minute: 0)) { AliasedProbe() }
        let still = aliased.map { pixels(of: $0.image) }
        for k in 1..<still.count {
            #expect(still[k] == still[0], "picture \(k) moved when the clock said it could not")
        }
    }

    // MARK: The moment a frame stands for

    @Test("At a desk, the moment a frame stands for is now")
    func theMomentIsNowAtADesk() {
        let sketch = ClockProbe()
        #expect(abs(sketch.date.timeIntervalSinceNow) < 1)
    }

    @Test("A day schedule asks about the moment being drawn")
    func aDayScheduleFollowsTheFrame() {
        final class DayPiece: Sketch {
            override var installation: Installation {
                Installation(schedule: [.from(6, "day"), .from(18, "night")])
            }
        }
        let piece = DayPiece()
        piece.heldDate = moment(hour: 22, minute: 0)
        // The picture is drawn now for a moment that has not come, so the
        // question the piece asks has to be about the moment, not the clock.
        #expect(piece.scheduledPeriod == "night")
        piece.heldDate = moment(hour: 9, minute: 0)
        #expect(piece.scheduledPeriod == "day")
    }
}
