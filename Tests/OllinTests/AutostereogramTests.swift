import Foundation
import Ollin
import Testing

/// Laws for the autostereogram. The whole picture rests on one rule, and it is
/// exactly measurable: two columns a separation apart hold the same color, and the
/// separation is what the depth map asked for.
@Suite
struct AutostereogramTests {
    private let settings = Autostereogram(repeatWidth: 60, relief: 0.25)

    /// The rule the eyes read: wherever the construction paired two columns, those
    /// two pixels are the same color. Asked of every pixel of every row.
    @Test func pairedColumnsHoldTheSameColor() {
        let depth = ramp(width: 240, height: 30)
        guard let picture = depth.autostereogram(settings, seed: 7) else {
            Issue.record("no picture")
            return
        }
        var pairs = 0
        for y in 0 ..< depth.height {
            for x in 0 ..< depth.width {
                let separation = separationAt(depth, x: x, y: y)
                let left = x - separation / 2
                let right = left + separation
                guard left >= 0, right < depth.width else { continue }
                #expect(same(picture[left, y], picture[right, y]),
                        "row \(y): \(left) and \(right) differ")
                pairs += 1
            }
        }
        #expect(pairs > 3000, "only \(pairs) pairs were checked")
    }

    /// A flat depth map is a plain repeat: every column matches the one a whole
    /// repeat to its left, and nothing else has moved.
    @Test func aFlatDepthIsAPlainRepeat() {
        let flat = Image(width: 240, height: 8, color: .black)     // all far
        guard let picture = flat.autostereogram(settings, seed: 3) else {
            Issue.record("no picture")
            return
        }
        for y in 0 ..< 8 {
            for x in 60 ..< 240 {
                #expect(same(picture[x, y], picture[x - 60, y]),
                        "column \(x) does not repeat the one 60 to its left")
            }
        }
    }

    /// The relief is the whole trick: where the depth map is white, the repeat is
    /// shorter, and by exactly the fraction asked for.
    @Test func aNearShapeShortensTheRepeat() {
        // A picture that is white everywhere, so the shortened repeat is the only
        // repeat in it.
        let near = Image(width: 240, height: 8, color: .white)
        guard let picture = near.autostereogram(settings, seed: 5) else {
            Issue.record("no picture")
            return
        }
        let shortened = Int((60.0 * (1 - 0.25)).rounded())
        #expect(shortened == 45)
        for y in 0 ..< 8 {
            for x in shortened ..< 240 {
                #expect(same(picture[x, y], picture[x - shortened, y]),
                        "column \(x) does not repeat the one \(shortened) to its left")
            }
        }
        // And it is not still repeating at the far spacing.
        var matchesAtFar = 0
        for x in 60 ..< 240 where same(picture[x, 0], picture[x - 60, 0]) { matchesAtFar += 1 }
        #expect(matchesAtFar < 120, "the far repeat survived at \(matchesAtFar) of 180 columns")
    }

    /// Which way white means is a switch, and it really does turn the relief over.
    @Test func theSenseOfTheDepthMapCanBeTurnedOver() {
        let white = Image(width: 200, height: 4, color: .white)
        let near = Autostereogram(repeatWidth: 60, relief: 0.25, whiteIsNear: true)
        let far = Autostereogram(repeatWidth: 60, relief: 0.25, whiteIsNear: false)
        guard let a = white.autostereogram(near, seed: 1),
              let b = white.autostereogram(far, seed: 1) else {
            Issue.record("no picture")
            return
        }
        // White as near shortens the repeat to 45; white as far leaves it at 60.
        #expect(same(a[100, 0], a[100 - 45, 0]))
        #expect(same(b[100, 0], b[100 - 60, 0]))
    }

    /// The same seed makes the same picture, and a different one does not.
    @Test func theSeedDecidesThePattern() {
        let depth = ramp(width: 180, height: 6)
        guard let a = depth.autostereogram(settings, seed: 11),
              let b = depth.autostereogram(settings, seed: 11),
              let c = depth.autostereogram(settings, seed: 12) else {
            Issue.record("no picture")
            return
        }
        var sameAsFirst = 0, sameAsOther = 0
        for y in 0 ..< 6 {
            for x in 0 ..< 180 {
                if same(a[x, y], b[x, y]) { sameAsFirst += 1 }
                if same(a[x, y], c[x, y]) { sameAsOther += 1 }
            }
        }
        #expect(sameAsFirst == 180 * 6)
        #expect(sameAsOther < 180 * 6 / 2, "a different seed drew nearly the same picture")
    }

    /// A pattern handed in is the pattern used, rather than noise.
    @Test func aGivenPatternIsTheOneRepeated() {
        let depth = Image(width: 200, height: 6, color: .black)
        let tile = Image(width: 20, height: 6, color: Color(red: 0.9, green: 0.2, blue: 0.4))
        guard let picture = depth.autostereogram(settings, pattern: tile) else {
            Issue.record("no picture")
            return
        }
        for y in 0 ..< 6 {
            for x in 0 ..< 200 {
                #expect(same(picture[x, y], Color(red: 0.9, green: 0.2, blue: 0.4)),
                        "\(x),\(y) is \(picture[x, y])")
            }
        }
    }

    /// The shape can be read back out, which is the only honest way to say the
    /// picture works without a pair of eyes. For each pixel, the smallest shift
    /// that matches the pixel to its left is the separation the eyes would pair
    /// at, and that separation has to be the one the depth map asked for.
    @Test func theShapeCanBeReadBackOutOfThePicture() {
        let depth = ramp(width: 300, height: 20)
        guard let picture = depth.autostereogram(settings, seed: 21) else {
            Issue.record("no picture")
            return
        }
        var read = 0, agreed = 0
        for y in 0 ..< depth.height {
            // Start past one full repeat, so there is always something to match.
            for x in 70 ..< depth.width {
                var found: Int?
                for shift in 40 ... 62 where same(picture[x, y], picture[x - shift, y]) {
                    found = shift
                    break
                }
                guard let found else { continue }
                read += 1
                // The pair straddles the depth it stands for: a pixel is the right
                // half of a pairing whose depth was read at the middle, half a
                // separation back. Comparing against the depth *at* the pixel is
                // off by that much, and reads as a band of disagreement along every
                // edge of the shape.
                let wanted = separationAt(depth, x: x - found / 2, y: y)
                // Within a pixel: the separation is rounded when it is laid down.
                if abs(found - wanted) <= 1 { agreed += 1 }
            }
        }
        #expect(read > 2000, "only \(read) pixels could be paired at all")
        // The edges of the shape are genuinely ambiguous, so this is a majority
        // rather than a unanimity.
        // 4362 of 4502 at this size. What is left is the shape's own edges, where
        // the depth changes inside the span of one pair and neither end of it is
        // the answer. Those columns are where a viewer sees the edge shimmer.
        #expect(Double(agreed) / Double(read) > 0.95,
                "only \(agreed) of \(read) read back the separation they were given")
    }

    /// A picture with no room for one repeat cannot hide anything. (An `Image`
    /// never has a zero side, since the type itself refuses one, so the width is
    /// the only way to be too small.)
    @Test func aPictureNarrowerThanItsRepeatIsRefused() {
        #expect(Image(width: 40, height: 10, color: .black).autostereogram(settings) == nil)
        #expect(Image(width: 60, height: 10, color: .black).autostereogram(settings) == nil)
        #expect(Image(width: 61, height: 10, color: .black).autostereogram(settings) != nil)
    }

    // MARK: - Helpers

    /// The separation the settings ask for at a pixel, worked out here from the
    /// depth rather than taken from the code.
    private func separationAt(_ depth: Image, x: Int, y: Int) -> Int {
        let color = depth[x, y]
        let level = 0.2126 * linear(color.red) + 0.7152 * linear(color.green)
            + 0.0722 * linear(color.blue)
        return Int((60.0 * (1 - 0.25 * level)).rounded())
    }

    private func linear(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    private func ramp(width: Int, height: Int) -> Image {
        let picture = Image(width: width, height: height, color: .black)
        for y in 0 ..< height {
            for x in 0 ..< width {
                // A shape in the middle, so there is real relief to pair against.
                let inside = x > width / 3 && x < width * 2 / 3 && y > height / 4
                picture[x, y] = Color(white: inside ? 1 : 0)
            }
        }
        return picture
    }

    private func same(_ a: Color, _ b: Color) -> Bool {
        abs(a.red - b.red) < 0.005 && abs(a.green - b.green) < 0.005
            && abs(a.blue - b.blue) < 0.005
    }
}
