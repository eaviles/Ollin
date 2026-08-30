import Ollin
import Testing

/// Pure-CPU checks on `StringArt`: the winding repeats exactly, the pins ring
/// the rim, every chord honors the span and no-repeat rules, the thread seeks
/// the dark (and the light when inverted), and the stops stop. No GPU.
@Suite
struct StringArtTests {
    /// White paper with a dark left half, small enough to keep the tests
    /// fast. The winding should live almost entirely over that half.
    private func darkLeftHalves() -> Image {
        let n = 64
        let image = Image(width: n, height: n, color: .white)
        for y in 0 ..< n {
            for x in 0 ..< n / 2 {
                image[x, y] = Color(white: 0.08)
            }
        }
        return image
    }

    @Test
    func theSamePictureWindsTheSameThread() {
        let a = StringArt(of: darkLeftHalves(), center: .zero, radius: 100,
                          pins: 60, resolution: 96)
        let b = StringArt(of: darkLeftHalves(), center: .zero, radius: 100,
                          pins: 60, resolution: 96)
        a.step(60)
        b.step(60)
        #expect(a.sequence == b.sequence)
        #expect(a.sequence.count > 30)
    }

    @Test
    func pinsRingTheRimClockwiseFromTheTop() {
        let center = Vector2(100, 100)
        let art = StringArt(of: darkLeftHalves(), center: center, radius: 50,
                            pins: 40, resolution: 64)
        #expect(art.pins.count == 40)
        for pin in art.pins {
            #expect(abs(pin.distance(to: center) - 50) < 1e-9)
        }
        // Pin 0 at the top; a quarter of the way round sits at the right,
        // which is clockwise on a y-down canvas.
        #expect(art.pins[0].distance(to: Vector2(100, 50)) < 1e-9)
        #expect(art.pins[10].distance(to: Vector2(150, 100)) < 1e-9)
    }

    @Test
    func everyChordHonorsTheMinimumSpan() {
        let art = StringArt(of: darkLeftHalves(), center: .zero, radius: 100,
                            pins: 60, minSpan: 9, resolution: 96)
        art.step(80)
        for i in 1 ..< art.sequence.count {
            let gap = abs(art.sequence[i] - art.sequence[i - 1])
            #expect(min(gap, 60 - gap) >= 9)
        }
    }

    @Test
    func noPinPairRepeats() {
        let art = StringArt(of: darkLeftHalves(), center: .zero, radius: 100,
                            pins: 40, resolution: 96)
        art.step(200)
        var seen = Set<[Int]>()
        for i in 1 ..< art.sequence.count {
            let pair = [min(art.sequence[i], art.sequence[i - 1]),
                        max(art.sequence[i], art.sequence[i - 1])]
            #expect(!seen.contains(pair))
            seen.insert(pair)
        }
    }

    @Test
    func theThreadSeeksTheDark() {
        let art = StringArt(of: darkLeftHalves(), center: .zero, radius: 100,
                            pins: 60, resolution: 96)
        let chords = art.step(40)
        #expect(chords.count == 40)
        let meanX = chords.map { ($0.from.x + $0.to.x) / 2 }.reduce(0, +)
                    / Double(chords.count)
        // The dark half is the left one, so the chords' midpoints live left
        // of center by a clear margin.
        #expect(meanX < -15)
    }

    @Test
    func invertedWindsTheLight() {
        let art = StringArt(of: darkLeftHalves(), center: .zero, radius: 100,
                            pins: 60, inverted: true, resolution: 96)
        let chords = art.step(40)
        #expect(chords.count == 40)
        let meanX = chords.map { ($0.from.x + $0.to.x) / 2 }.reduce(0, +)
                    / Double(chords.count)
        #expect(meanX > 15)
    }

    @Test
    func aBlankPageWindsNothing() {
        let art = StringArt(of: Image(width: 32, height: 32, color: .white),
                            center: .zero, radius: 100, pins: 40, resolution: 64)
        #expect(art.step() == nil)
        #expect(art.isFinished)
        #expect(art.chordCount == 0)
        #expect(art.step(10).isEmpty)
    }

    @Test
    func theChordCapStopsTheWinding() {
        let art = StringArt(of: darkLeftHalves(), center: .zero, radius: 100,
                            pins: 60, chords: 12, resolution: 96)
        let chords = art.step(100)
        #expect(chords.count == 12)
        #expect(art.isFinished)
        #expect(art.chordCount == 12)
    }

    @Test
    func theThreadContourFollowsTheSequence() {
        let art = StringArt(of: darkLeftHalves(), center: .zero, radius: 100,
                            pins: 60, resolution: 96)
        let chords = art.step(25)
        let thread = art.thread
        #expect(!thread.isClosed)
        #expect(thread.points.count == art.sequence.count)
        #expect(thread.points == art.sequence.map { art.pins[$0] })
        // The chords returned along the way are the same winding.
        #expect(chords.first?.from == art.pins[art.sequence[0]])
        #expect(chords.last?.to == thread.points.last)
    }
}
