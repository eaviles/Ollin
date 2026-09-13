import Foundation
@testable import Ollin
import Testing

/// The frame-rate value: a number stands in for one, the broadcast rates are
/// exact fractions, and the clock a video writer builds from it lands every
/// frame on that fraction.
struct FrameRateTests {

    @Test func aNumberStandsInForARate() {
        let whole: FrameRate = 60
        let decimal: FrameRate = 29.97
        #expect(whole.frames == 60 && whole.seconds == 1)
        #expect(decimal.frames == 2997 && decimal.seconds == 100)
        #expect(whole.framesPerSecond == 60)
        #expect(abs(decimal.framesPerSecond - 29.97) < 1e-12)
    }

    @Test func fractionsReduceAndCompareByValue() {
        #expect(FrameRate(60, per: 2) == 30)
        #expect(FrameRate(48, per: 2) == .film)
        #expect(FrameRate(30000, per: 1001) == .ntsc)
        #expect(FrameRate(0, per: 0).seconds == 1)        // a denominator of zero is taken as one
    }

    @Test func theBroadcastRatesAreExactFractions() {
        #expect(FrameRate.ntsc.frames == 30000 && FrameRate.ntsc.seconds == 1001)
        #expect(FrameRate.ntscFilm.frames == 24000 && FrameRate.ntscFilm.seconds == 1001)
        #expect(FrameRate.ntscDouble.frames == 60000 && FrameRate.ntscDouble.seconds == 1001)
        #expect(FrameRate.film == 24 && FrameRate.pal == 25)
        // 29.97 is not NTSC: the decimal misses the fraction by one part in a million.
        #expect(FrameRate(29.97) != .ntsc)
        #expect(abs(FrameRate(29.97).framesPerSecond - FrameRate.ntsc.framesPerSecond) < 1e-4)
    }

    @Test func aFrameLastsTheInverseOfTheRate() {
        for rate in [FrameRate.film, .pal, .ntsc, .ntscFilm, .ntscDouble, 60, 120, 29.97] {
            #expect(abs(rate.frameDuration * rate.framesPerSecond - 1) < 1e-12)
        }
        #expect(FrameRate(0, per: 1).frameDuration == .infinity)
    }

    @Test func framesInSecondsRoundToTheNearestFrame() {
        #expect(FrameRate.film.frames(in: 2.5) == 60)
        #expect(FrameRate.ntsc.frames(in: 10) == 300)          // 299.7 rounds up
        #expect(FrameRate(60, per: 1).seconds(for: 90) == 1.5)
    }

    @Test func namesRoundTripAndNumbersAreNotNames() {
        for (name, rate) in [("film", FrameRate.film), ("PAL", .pal), ("ntsc", .ntsc),
                             ("NTSCFilm", .ntscFilm), ("ntscdouble", .ntscDouble)] {
            #expect(FrameRate(named: name) == rate)
        }
        #expect(FrameRate(named: "60") == nil)
        #expect(FrameRate(named: "cinema") == nil)
    }

    @Test func aFlagParsesAsANameANumberOrAFraction() {
        #expect(FrameRate(parsing: "ntsc") == .ntsc)
        #expect(FrameRate(parsing: "24") == .film)
        #expect(FrameRate(parsing: " 29.97 ") == FrameRate(29.97))
        #expect(FrameRate(parsing: "30000/1001") == .ntsc)
        #expect(FrameRate(parsing: "0") == nil)
        #expect(FrameRate(parsing: "-24") == nil)
        #expect(FrameRate(parsing: "24/0") == nil)
        #expect(FrameRate(parsing: "fast") == nil)
    }

    @Test func itReadsAsItIsSaid() {
        #expect(FrameRate.film.description == "24 fps")
        #expect(FrameRate.ntsc.description == "29.97 fps")
        #expect(FrameRate.ntscFilm.description == "23.98 fps")
        #expect(FrameRate(29.5).description == "29.50 fps")
    }

    @Test func theMediaClockLandsEveryFrameOnTheRatesOwnFraction() {
        // A whole-number rate keeps the clock the exporters always wrote.
        let sixty = FrameRate(60, per: 1).mediaClock
        #expect(sixty.timescale == 60_000 && sixty.tick == 1000)
        // NTSC: frame k at k * 1001 / 30000 exactly, on the timescale every
        // broadcast file uses.
        let ntsc = FrameRate.ntsc.mediaClock
        #expect(ntsc.timescale == 30_000 && ntsc.tick == 1001)
        let tenFrames: Double = Double(10 * ntsc.tick) / Double(ntsc.timescale)
        let expectedTen: Double = 10 * 1001.0 / 30000
        #expect(tenFrames == expectedTen)
        // A decimal keeps its own fraction too.
        let decimal = FrameRate(29.97).mediaClock
        #expect(decimal.timescale == 2997 && decimal.tick == 100)
        // A whole rate too fine for the thousandfold clock falls back rather than trapping.
        let fine = FrameRate(3_000_000, per: 1).mediaClock
        #expect(fine.timescale > 0 && fine.tick == 1000)
    }
}
