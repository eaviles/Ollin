import Testing
import Foundation
@testable import Ollin

/// `handDrawn(...)`: a line made to look drawn by hand. The wobble is read
/// along the line from its own start and drawn from the seed alone, so a
/// moved line carries it and the same seed draws the same line; every point
/// stays within the amplitudes asked; an open line's ends run short or long
/// along their heading; a closed outline stays closed and keeps its corners;
/// a mark keeps what it recorded and gains the blot where the pen landed.
@Suite struct HandDrawnTests {

    static let line = Contour([Vector2(20, 100), Vector2(420, 100)], closed: false)

    @Test func theSameSeedDrawsTheSameLineAndItTravelsWithItsAnchor() {
        let a = Self.line.handDrawn(seed: 4)
        let again = Self.line.handDrawn(seed: 4)
        #expect(a == again)
        let offset = Vector2(37, -12)
        let moved = Contour(Self.line.points.map { $0 + offset }, closed: false).handDrawn(seed: 4)
        try? #require(moved.points.count == a.points.count)
        for (p, q) in zip(a.points, moved.points) {
            #expect((q - p - offset).length < 1e-9, "the wobble moves whole with the line")
        }
        let other = Self.line.handDrawn(seed: 5)
        #expect(other != a, "another seed draws another line")
    }

    @Test func aLineWobblesWithinItsAmplitudeAndNotAtAll() {
        let bent = Self.line.handDrawn(wobble: 2, bow: 1.5, overshoot: 0, seed: 1)
        #expect(bent.points.count > 100, "the line is resampled every few points")
        var farthest = 0.0
        for p in bent.points {
            #expect(abs(p.y - 100) <= 3.5 + 1e-9, "a point sits \(p.y - 100) off the line")
            farthest = max(farthest, abs(p.y - 100))
        }
        #expect(farthest > 0.6, "the line is bent, by \(farthest) at most")
        let still = Self.line.handDrawn(wobble: 0, bow: 0, overshoot: 0, seed: 1)
        #expect(still.points.allSatisfy { abs($0.y - 100) < 1e-9 })
        #expect(abs(still.points.first!.x - 20) < 1e-9 && abs(still.points.last!.x - 420) < 1e-9)
    }

    @Test func anOpenLinesEndsRunShortOrLongAlongTheirHeading() {
        var longer = false, shorter = false
        for seed in 0 ..< 12 {
            let bent = Self.line.handDrawn(wobble: 0, bow: 0, overshoot: 6, seed: seed)
            let first = bent.points.first!, last = bent.points.last!
            #expect(abs(first.y - 100) < 1e-9 && abs(last.y - 100) < 1e-9, "an end moves along the line only")
            #expect(first.x >= 20 - 6 - 1e-9 && first.x <= 20 + 6 + 1e-9)
            #expect(last.x <= 420 + 6 + 1e-9 && last.x >= 420 - 6 - 1e-9)
            if first.x < 20 - 0.5 || last.x > 420 + 0.5 { longer = true }
            if first.x > 20 + 0.5 || last.x < 420 - 0.5 { shorter = true }
        }
        #expect(longer && shorter, "over a dozen seeds some ends run long and some short")
    }

    @Test func aClosedOutlineStaysClosedAndKeepsItsCorners() {
        let square = Contour([Vector2(100, 100), Vector2(300, 100), Vector2(300, 300), Vector2(100, 300)])
        let bent = square.handDrawn(wobble: 1.5, bow: 2, overshoot: 8, seed: 2)
        #expect(bent.isClosed)
        #expect(bent.points.count >= 4 * 60)
        for corner in square.points {
            let nearest = bent.points.map { $0.distance(to: corner) }.min() ?? .infinity
            #expect(nearest < 3.5 + 1e-9, "the corner at \(corner) sits \(nearest) from the bent outline")
        }
        // Each side bows: its middle sits off the straight side by about the bow.
        let midTop = bent.points.filter { abs($0.x - 200) < 2 && $0.y < 200 }
        #expect(!midTop.isEmpty)
        let sag = midTop.map { abs($0.y - 100) }.max() ?? 0
        #expect(sag > 0.8 && sag <= 3.5, "the top side sags \(sag)")
        // The shape still fills: its center is inside, and a corner's outside stays out.
        let shape = Shape(contours: [square]).handDrawn(seed: 2)
        #expect(shape.contains(Vector2(200, 200)))
        #expect(!shape.contains(Vector2(60, 60)))
        #expect(shape.contours.first?.isClosed == true)
    }

    @Test func aMarkKeepsWhatItRecordedAndGainsTheBlot() {
        let mark = StrokeMark(samples: (0 ... 40).map { i in
            StrokeMark.Sample(position: Vector2(20 + Double(i) * 10, 60), width: 1,
                              opacity: i < 20 ? 1 : 0.4, speed: 300 + Double(i))
        })
        let bent = mark.handDrawn(wobble: 1, bow: 1, overshoot: 0, blot: 10, seed: 7)
        #expect(bent.count > 100)
        #expect(bent.samples.allSatisfy { $0.speed != nil }, "the speeds ride along")
        #expect(abs(bent.samples.first!.width - 1.5) < 0.02, "the landing swells by half")
        var walked = 0.0
        var settled = 1.0
        for (a, b) in zip(bent.samples, bent.samples.dropFirst()) {
            walked += a.position.distance(to: b.position)
            if walked > 50 { settled = b.width; break }
        }
        #expect(settled < 1.02, "the blot settles within a few blot lengths")
        #expect(abs(bent.samples.first!.opacity - 1) < 1e-9 && abs(bent.samples.last!.opacity - 0.4) < 1e-9)
        let plain = mark.handDrawn(wobble: 0, bow: 0, overshoot: 0, blot: 0, seed: 7)
        #expect(plain.samples.allSatisfy { abs($0.width - 1) < 1e-9 })
        #expect(abs(plain.length - mark.length) < 1e-6)
    }
}
