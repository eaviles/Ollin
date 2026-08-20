@testable import Ollin
import Testing

/// Pure CPU checks on the star an opening makes: the far-field diffraction bake
/// behind `lensFlare()`. No Metal device, so these run everywhere.
@Suite
struct ApertureStarTests {

    /// The pattern's brightness at one point.
    private func level(_ star: StarPattern, _ x: Int, _ y: Int) -> Double {
        let x = min(star.size - 1, max(0, x)), y = min(star.size - 1, max(0, y))
        let index = (y * star.size + x) * 4
        return (Double(star.pixels[index]) + Double(star.pixels[index + 1])
                + Double(star.pixels[index + 2])) / 3
    }

    /// The brightness around a circle at `radius` texels from the middle, which
    /// is where the arms show up as peaks.
    private func ring(_ star: StarPattern, radius: Double, steps: Int = 144) -> [Double] {
        let center = Double(star.size) / 2
        return (0..<steps).map { step in
            let angle = Double(step) / Double(steps) * 2 * Double.pi
            return level(star, Int(center + radius * cos(angle)),
                         Int(center + radius * sin(angle)))
        }
    }

    /// Peaks around the ring that stand clear of the floor between them.
    private func arms(_ profile: [Double]) -> Int {
        guard let high = profile.max(), let low = profile.min(), high > low else { return 0 }
        let bar = low + (high - low) * 0.3
        var count = 0
        for index in profile.indices {
            let before = profile[(index + profile.count - 1) % profile.count]
            let after = profile[(index + 1) % profile.count]
            if profile[index] > before && profile[index] >= after && profile[index] > bar {
                count += 1
            }
        }
        return count
    }

    /// The one that matters, and it is not a number anyone chose: a slit spreads
    /// light across itself, so each pair of opposite blades throws one arm. An
    /// even-sided opening has its blades in parallel pairs, so the arms land on
    /// top of each other and you count the blades. An odd-sided one has no
    /// parallel pair, so every blade throws its own and you count twice.
    @Test(arguments: [(5, 10), (6, 6), (7, 14), (8, 8)])
    func theArmsCountTheBlades(blades: Int, expected: Int) {
        let star = ApertureStar.bake(blades: blades, size: 256)
        #expect(arms(ring(star, radius: 40)) == expected,
                "\(blades) blades should throw \(expected) arms")
    }

    /// A round opening has no edges to line up, so it makes rings and no arms.
    @Test func aRoundOpeningHasNoArms() {
        let star = ApertureStar.bake(blades: 0, size: 256)
        let profile = ring(star, radius: 40)
        let high = profile.max() ?? 0, low = profile.min() ?? 0
        #expect(high > 0, "the pattern is empty")
        #expect((high - low) / high < 0.5,
                "a round opening should be even around the ring: \(low) to \(high)")
        // And a bladed one is nothing like even, or the check above proves little.
        let bladed = ring(ApertureStar.bake(blades: 6, size: 256), radius: 40)
        let bladedHigh = bladed.max() ?? 0, bladedLow = bladed.min() ?? 0
        #expect((bladedHigh - bladedLow) / bladedHigh > 0.9,
                "six blades should be far from even: \(bladedLow) to \(bladedHigh)")
    }

    /// Nearly all of a star's light is in its core, and the core sits on the
    /// source. The arms are the faint remainder, which is why a photograph only
    /// shows them when the source is far brighter than the scene.
    @Test func theCoreSitsInTheMiddleAndHoldsMostOfTheLight() {
        let star = ApertureStar.bake(blades: 6, size: 256)
        let core = level(star, star.size / 2, star.size / 2)
        #expect(core > 100 * (ring(star, radius: 40).max() ?? 1),
                "the core should tower over the arms: \(core)")
        for offset in [16, 48, 96] {
            #expect(level(star, star.size / 2 + offset, star.size / 2) < core)
            #expect(level(star, star.size / 2, star.size / 2 + offset) < core)
        }
    }

    /// Light bending around a smaller opening spreads further, which is why
    /// stopping down grows the star at the same time as it shrinks the ghosts.
    @Test func aSmallerOpeningThrowsAWiderStar() {
        let star = ApertureStar.bake(blades: 6, size: 64)
        let wide = star.halfAngle(irisRadiusMillimeters: 12)
        let tight = star.halfAngle(irisRadiusMillimeters: 3)
        #expect(tight > wide * 3.9 && tight < wide * 4.1,
                "a quarter of the opening should be four times the spread: \(wide) to \(tight)")
        #expect(star.halfAngle(irisRadiusMillimeters: 0) == 0)
    }

    /// The pattern has to reach nothing at the edge of what was measured. The
    /// arms run further than the bake does, and left alone they would end in a
    /// straight cut across the picture.
    @Test func theArmsFadeBeforeTheEdge() {
        let star = ApertureStar.bake(blades: 6, size: 128)
        let half = Double(star.size) / 2
        let inside = ring(star, radius: half * 0.8).max() ?? 0
        let edge = ring(star, radius: half - 1).max() ?? 0
        #expect(inside > 0, "the pattern should be present inside the fade: \(inside)")
        #expect(edge < inside * 0.05,
                "it should be nearly gone by its own edge: \(inside) to \(edge)")
        // Past the edge there is nothing at all, so the corners of the square
        // never show a shape of their own.
        #expect(level(star, 0, 0) == 0 && level(star, star.size - 1, star.size - 1) == 0)
    }

    /// The star's color comes from taking the spectrum a wavelength at a time,
    /// so a wavelength has to look like the color the eye sees it as.
    @Test func aWavelengthLooksLikeItsOwnColor() {
        let red = ApertureStar.linearColor(ofWavelength: 660)
        let green = ApertureStar.linearColor(ofWavelength: 540)
        let blue = ApertureStar.linearColor(ofWavelength: 450)
        #expect(red.x > red.y && red.x > red.z, "660nm should read red: \(red)")
        #expect(green.y > green.x && green.y > green.z, "540nm should read green: \(green)")
        #expect(blue.z > blue.x && blue.z > blue.y, "450nm should read blue: \(blue)")
        // Nothing outside the visible band contributes.
        #expect(ApertureStar.linearColor(ofWavelength: 900).max() < 0.01)
    }

    /// The bake is a one-time cost keyed on the blade count, so the same opening
    /// has to come back the same way.
    @Test func theSameOpeningBakesTheSameStar() {
        let first = ApertureStar.bake(blades: 6, size: 64)
        let second = ApertureStar.bake(blades: 6, size: 64)
        #expect(first.pixels == second.pixels)
        #expect(first == second)
        #expect(first != ApertureStar.bake(blades: 8, size: 64))
    }
}
