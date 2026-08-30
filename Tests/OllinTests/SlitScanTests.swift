import Ollin
import Testing

/// Pure-CPU checks on `SlitScan`: delays index the history newest-to-oldest,
/// the capacity rolls, mismatched frames are skipped, and a delay map reads
/// its brightness. No GPU.
@Suite @MainActor
struct SlitScanTests {
    private func solidFrame(_ gray: Double, side: Int = 4) -> Image {
        Image(width: side, height: side, color: Color(white: gray))
    }

    /// Delay 0 reads the newest frame, delay 1 the oldest held, and a middle
    /// delay lands between them.
    @Test func delayIndexesTheHistory() throws {
        let history = SlitScan(capacity: 5)
        for gray in [0.1, 0.5, 0.9] { history.append(solidFrame(gray)) }

        let newest = try #require(history.image(delay: { _ in 0 }))
        let oldest = try #require(history.image(delay: { _ in 1 }))
        let middle = try #require(history.image(delay: { _ in 0.5 }))
        #expect(abs(newest[0, 0].luminance - Color(white: 0.9).luminance) < 0.01)
        #expect(abs(oldest[0, 0].luminance - Color(white: 0.1).luminance) < 0.01)
        #expect(abs(middle[0, 0].luminance - Color(white: 0.5).luminance) < 0.01)
    }

    /// The delay closure is positional: a left-to-right ramp reads newest on
    /// the left edge and oldest on the right.
    @Test func positionalDelayReadsAcrossTime() throws {
        let history = SlitScan(capacity: 4)
        for gray in [0.2, 0.8] { history.append(solidFrame(gray, side: 8)) }
        let scanned = try #require(history.image(delay: { uv in uv.x }))
        #expect(abs(scanned[7, 0].luminance - Color(white: 0.2).luminance) < 0.01)
        #expect(abs(scanned[0, 0].luminance - Color(white: 0.8).luminance) < 0.01)
    }

    /// The buffer rolls: pushing past capacity drops the oldest frame.
    @Test func capacityRolls() throws {
        let history = SlitScan(capacity: 3)
        for gray in [0.1, 0.3, 0.5, 0.7] { history.append(solidFrame(gray)) }
        #expect(history.count == 3)
        let oldest = try #require(history.image(delay: { _ in 1 }))
        #expect(abs(oldest[0, 0].luminance - Color(white: 0.3).luminance) < 0.01)
    }

    /// A frame of the wrong size is skipped, not mixed in.
    @Test func mismatchedFramesAreSkipped() {
        let history = SlitScan(capacity: 4)
        history.append(solidFrame(0.5, side: 4))
        history.append(solidFrame(0.9, side: 7))
        #expect(history.count == 1)
    }

    /// Before any push there is nothing to compose.
    @Test func emptyHistoryYieldsNil() {
        let history = SlitScan(capacity: 4)
        #expect(history.image(delay: { _ in 0 }) == nil)
    }

    /// A delay-map image reads its brightness: a black map shows the newest
    /// frame everywhere, a white map the oldest.
    @Test func mapDelaysByBrightness() throws {
        let history = SlitScan(capacity: 4)
        for gray in [0.2, 0.8] { history.append(solidFrame(gray)) }
        let black = try #require(history.image(delay: Image(width: 2, height: 2, color: .black)))
        let white = try #require(history.image(delay: Image(width: 2, height: 2, color: .white)))
        #expect(abs(black[0, 0].luminance - Color(white: 0.8).luminance) < 0.01)
        #expect(abs(white[0, 0].luminance - Color(white: 0.2).luminance) < 0.01)
    }

    /// `clear` empties the history and lets a new size take over.
    @Test func clearResetsTheHistory() {
        let history = SlitScan(capacity: 4)
        history.append(solidFrame(0.5, side: 4))
        history.clear()
        #expect(history.count == 0)
        history.append(solidFrame(0.5, side: 9))
        #expect(history.count == 1)
    }
}
