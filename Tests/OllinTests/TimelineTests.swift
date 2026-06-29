@testable import Ollin
import Testing

/// Pure CPU checks on `Timeline`: the segment walk, per-segment easing, looping,
/// and the `Tweenable` conformances. No Metal, so these run everywhere including CI.
@Suite
struct TimelineTests {

    private func close(_ a: Double, _ b: Double, _ eps: Double = 1e-9) -> Bool {
        abs(a - b) <= eps
    }

    /// A two-segment Double timeline interpolates linearly within each segment and
    /// holds at the ends past its bounds.
    @Test func linearSegments() {
        let tl = Timeline(0.0)
            .to(100, in: 1, ease: .linear)
            .to(0, in: 1, ease: .linear)

        #expect(close(tl.value, 0))           // clock 0 -> start
        tl.advance(by: 0.5)
        #expect(close(tl.value, 50))          // halfway up the first segment
        tl.advance(by: 0.5)
        #expect(close(tl.value, 100))         // end of first segment
        tl.advance(by: 0.5)
        #expect(close(tl.value, 50))          // halfway down the second
        tl.advance(by: 0.5)
        #expect(close(tl.value, 0))           // end
        tl.advance(by: 1.0)
        #expect(close(tl.value, 0))           // holds at the last target past the end
    }

    /// `duration`, `progress`, and `isFinished` track the clock.
    @Test func progressAndFinish() {
        let tl = Timeline(0.0).to(10, in: 2, ease: .linear)
        #expect(close(tl.duration, 2))
        #expect(close(tl.progress, 0))
        #expect(!tl.isFinished)
        tl.advance(by: 1)
        #expect(close(tl.progress, 0.5))
        #expect(!tl.isFinished)
        tl.advance(by: 1.5)
        #expect(close(tl.progress, 1))
        #expect(tl.isFinished)
    }

    /// `hold` keeps the previous target steady for its duration.
    @Test func holdSegment() {
        let tl = Timeline(0.0)
            .to(5, in: 1, ease: .linear)
            .hold(for: 1)
            .to(0, in: 1, ease: .linear)
        tl.advance(by: 1.5)                    // 0.5s into the hold
        #expect(close(tl.value, 5))
        tl.advance(by: 0.5)                    // end of the hold
        #expect(close(tl.value, 5))
        tl.advance(by: 0.5)                    // halfway down the final segment
        #expect(close(tl.value, 2.5))
    }

    /// A looping timeline wraps the clock at the total duration.
    @Test func loopsWrap() {
        let tl = Timeline(0.0).to(10, in: 1, ease: .linear)
        tl.loops = true
        tl.advance(by: 1.25)                   // wraps to 0.25
        #expect(close(tl.value, 2.5))
        #expect(!tl.isFinished)                // a looping timeline never finishes
        #expect(close(tl.progress, 0.25))
    }

    /// Easing shapes the segment: an ease-out is past the linear midpoint at t=0.5.
    @Test func perSegmentEasing() {
        let tl = Timeline(0.0).to(1, in: 1, ease: .easeOut)
        tl.advance(by: 0.5)
        #expect(tl.value > 0.5)                // ease-out is ahead of linear mid-flight
    }

    /// `Vector3` interpolates component-wise through a timeline.
    @Test func vector3Timeline() {
        let tl = Timeline(Vector3.zero).to(Vector3(2, 4, 6), in: 1, ease: .linear)
        tl.advance(by: 0.5)
        #expect(close(tl.value.x, 1))
        #expect(close(tl.value.y, 2))
        #expect(close(tl.value.z, 3))
    }
}
