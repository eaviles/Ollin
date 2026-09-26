@testable import Ollin
import Testing
import CoreGraphics
import Foundation

/// The film look: `.halation` and `.filmGrain`, each checked as the invariants the
/// technique promises rather than as a picture, because both can look right
/// while being wrong. A glow that merely tints the whole highlight still reads
/// as a warm picture, and noise that is the same at every tone still reads as
/// grain. The invariants:
///
/// Halation:
/// - a frame with nothing above the threshold, or an amount of zero, comes back
///   byte for byte;
/// - a white core stays white and the ring around it is warm (red rises more
///   than blue), and the halo is gone far from the highlight;
/// - the tint is the halo's color: a blue tint lifts blue and leaves red;
/// - a wider radius reaches farther;
/// - the halo lands where there is room: the same highlight lifts a mid-gray
///   neighbor more than a near-white one.
///
/// Film grain:
/// - black and white take no grain, byte for byte;
/// - the mean of a flat region is kept, to the level;
/// - the spread at mid-gray is the amount, in display levels;
/// - the grain follows the tone: most at mid-gray, and the same at a dark tone
///   as at the light tone the same distance from the ends;
/// - the same seed draws the same picture, another seed another one, and a
///   fractional seed is its own;
/// - bigger grain is smoother.
@Suite
@MainActor
struct FilmLookTests {

    private func pixels(of image: CGImage) -> [UInt8] {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return data
    }

    private func render(_ scene: FilmProbe.Scene, _ filter: Filter?) throws -> [UInt8] {
        pixels(of: try #require(OllinApp.image(of: FilmProbe.make(scene, filter: filter), frame: 1)))
    }

    private func rgb(_ data: [UInt8], _ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) {
        let i = (y * FilmProbe.side + x) * 4
        return (Int(data[i]), Int(data[i + 1]), Int(data[i + 2]))
    }

    /// The bytes that differ between two renders, over the three color channels.
    private func differing(_ a: [UInt8], _ b: [UInt8]) -> Int {
        var n = 0
        for i in stride(from: 0, to: a.count, by: 4) {
            if a[i] != b[i] || a[i + 1] != b[i + 1] || a[i + 2] != b[i + 2] { n += 1 }
        }
        return n
    }

    private func mean(_ data: [UInt8], channel: Int = 1) -> Double {
        var sum = 0
        for i in stride(from: channel, to: data.count, by: 4) { sum += Int(data[i]) }
        return Double(sum) / Double(data.count / 4)
    }

    private func spread(_ data: [UInt8], channel: Int = 1) -> Double {
        let m = mean(data, channel: channel)
        var sum = 0.0
        for i in stride(from: channel, to: data.count, by: 4) { sum += (Double(data[i]) - m) * (Double(data[i]) - m) }
        return (sum / Double(data.count / 4)).squareRoot()
    }

    /// The mean absolute difference between horizontally adjacent pixels.
    private func roughness(_ data: [UInt8]) -> Double {
        let side = FilmProbe.side
        var sum = 0
        for y in 0 ..< side {
            for x in 1 ..< side {
                sum += abs(Int(data[(y * side + x) * 4 + 1]) - Int(data[(y * side + x - 1) * 4 + 1]))
            }
        }
        return Double(sum) / Double(side * (side - 1))
    }

    // MARK: Halation

    @Test func nothingAboveTheThresholdComesBackByteForByte() throws {
        let plain = try render(.midTones, nil)
        let filtered = try render(.midTones, .halation())
        #expect(differing(plain, filtered) == 0)
    }

    @Test func anAmountOfZeroComesBackByteForByte() throws {
        let plain = try render(.disk(on: 0.35), nil)
        let filtered = try render(.disk(on: 0.35), .halation(amount: 0))
        #expect(differing(plain, filtered) == 0)
    }

    @Test func theCoreStaysWhiteAndTheRingIsWarm() throws {
        let plain = try render(.disk(on: 0.35), nil)
        let filtered = try render(.disk(on: 0.35), .halation(threshold: 0.8, radius: 8))
        let c = FilmProbe.side / 2
        // The core: white in, white out.
        #expect(rgb(plain, c, c) == (255, 255, 255))
        #expect(rgb(filtered, c, c) == (255, 255, 255))
        // Just outside the disk: lifted, and red more than blue.
        let before = rgb(plain, c + FilmProbe.diskRadius + 3, c)
        let after = rgb(filtered, c + FilmProbe.diskRadius + 3, c)
        #expect(after.r - before.r >= 20, "red rose by \(after.r - before.r)")
        #expect(after.r - before.r > (after.b - before.b) + 10,
                "red rose by \(after.r - before.r), blue by \(after.b - before.b)")
        // Far away: the halo is gone.
        let farBefore = rgb(plain, 4, 4), farAfter = rgb(filtered, 4, 4)
        #expect(abs(farAfter.r - farBefore.r) <= 1 && abs(farAfter.b - farBefore.b) <= 1)
    }

    @Test func theTintIsTheHalosColor() throws {
        let plain = try render(.disk(on: 0.35), nil)
        let blue = try render(.disk(on: 0.35), .halation(threshold: 0.8, radius: 8, tint: Color(red: 0, green: 0, blue: 1)))
        let c = FilmProbe.side / 2
        let before = rgb(plain, c + FilmProbe.diskRadius + 3, c)
        let after = rgb(blue, c + FilmProbe.diskRadius + 3, c)
        #expect(after.b - before.b >= 20, "blue rose by \(after.b - before.b)")
        #expect(abs(after.r - before.r) <= 1, "red moved by \(after.r - before.r)")
    }

    @Test func aWiderRadiusReachesFarther() throws {
        let plain = try render(.disk(on: 0.35), nil)
        let narrow = try render(.disk(on: 0.35), .halation(threshold: 0.8, radius: 3))
        let wide = try render(.disk(on: 0.35), .halation(threshold: 0.8, radius: 20))
        let c = FilmProbe.side / 2
        let x = c + FilmProbe.diskRadius + 18
        let lift = { (data: [UInt8]) in self.rgb(data, x, c).r - self.rgb(plain, x, c).r }
        #expect(lift(narrow) <= 2, "the narrow halo reached 18 px out by \(lift(narrow))")
        #expect(lift(wide) >= 8, "the wide halo lifted 18 px out by \(lift(wide))")
    }

    @Test func theHaloLandsWhereThereIsRoom() throws {
        let c = FilmProbe.side / 2
        let x = c + FilmProbe.diskRadius + 3
        func lift(on gray: Double) throws -> Int {
            let plain = try render(.disk(on: gray), nil)
            let filtered = try render(.disk(on: gray), .halation(threshold: 0.8, radius: 8))
            return rgb(filtered, x, c).r - rgb(plain, x, c).r
        }
        let onGray = try lift(on: 0.35), onWhite = try lift(on: 0.96)
        #expect(onGray > onWhite * 3, "lifted a gray neighbor by \(onGray), a near-white one by \(onWhite)")
    }

    @Test func eachChannelTakesTheHaloItHasRoomFor() throws {
        // Over a red field, under a tint carrying as much red as green, the
        // ring's green rises many times more than its red: red is nearly full
        // there and has no room, green has all of it. Without the room rule the
        // red would take the whole halo and clip, a few times the green's rise
        // rather than a dozen.
        let plain = try render(.diskOnRed, nil)
        let filtered = try render(.diskOnRed, .halation(threshold: 0.8, radius: 8,
                                                        tint: Color(red: 1, green: 1, blue: 0)))
        let c = FilmProbe.side / 2
        let before = rgb(plain, c + FilmProbe.diskRadius + 3, c)
        let after = rgb(filtered, c + FilmProbe.diskRadius + 3, c)
        let redLift = after.r - before.r, greenLift = after.g - before.g
        #expect(greenLift >= 60, "green rose by \(greenLift)")
        #expect(greenLift > redLift * 8, "green rose by \(greenLift), red by \(redLift)")
    }

    // MARK: Film grain

    @Test func blackAndWhiteTakeNoGrain() throws {
        for scene in [FilmProbe.Scene.flat(0), .flat(1)] {
            let plain = try render(scene, nil)
            let grained = try render(scene, .filmGrain(amount: 0.3, size: 2, seed: 3))
            #expect(differing(plain, grained) == 0)
        }
    }

    @Test func theMeanIsKept() throws {
        let plain = try render(.flat(0.5), nil)
        let grained = try render(.flat(0.5), .filmGrain(amount: 0.15, size: 2, seed: 1))
        #expect(abs(mean(plain) - mean(grained)) < 1, "mean \(mean(plain)) became \(mean(grained))")
        #expect(spread(grained) > 20)
    }

    /// The spread at mid-gray is the amount, in display levels, and the grain follows
    /// the tone from there: most at mid-gray, and the same at a dark tone as at the
    /// light tone the same distance from the ends.
    @Test func theGrainFollowsTheTone() throws {
        func spreadAt(_ gray: Double) throws -> Double {
            spread(try render(.flat(gray), .filmGrain(amount: 0.1, size: 2, seed: 5)))
        }
        let dark = try spreadAt(0.1), mid = try spreadAt(0.5), light = try spreadAt(0.9)
        #expect(mid > 22 && mid < 29, "a tenth of the way to white is 25.5 levels; measured \(mid)")
        #expect(mid > dark * 1.3 && mid > light * 1.3, "dark \(dark), mid \(mid), light \(light)")
        #expect(abs(dark - light) < 0.25 * mid, "dark \(dark) against light \(light)")
    }

    @Test func theSeedPicksThePattern() throws {
        let a = try render(.flat(0.5), .filmGrain(amount: 0.1, size: 2, seed: 7))
        let again = try render(.flat(0.5), .filmGrain(amount: 0.1, size: 2, seed: 7))
        let other = try render(.flat(0.5), .filmGrain(amount: 0.1, size: 2, seed: 8))
        let fractional = try render(.flat(0.5), .filmGrain(amount: 0.1, size: 2, seed: 7.5))
        #expect(differing(a, again) == 0)
        #expect(differing(a, other) > a.count / 8)
        #expect(differing(a, fractional) > a.count / 8)
    }

    @Test func biggerGrainIsSmoother() throws {
        let fine = try render(.flat(0.5), .filmGrain(amount: 0.1, size: 1, seed: 2))
        let coarse = try render(.flat(0.5), .filmGrain(amount: 0.1, size: 6, seed: 2))
        #expect(roughness(fine) > roughness(coarse) * 2,
                "fine \(roughness(fine)), coarse \(roughness(coarse))")
        // Both carry the same spread, since the amount is a spread and not a
        // per-node value.
        #expect(abs(spread(fine) - spread(coarse)) < 0.15 * spread(fine),
                "fine \(spread(fine)), coarse \(spread(coarse))")
    }

    @Test func everySeedHasItsOwnPattern() {
        let seeds: [Double] = [0, 1, 2, 3, 1.5, 100_000, -1]
        let patterns = seeds.map { Filter.grainPattern(of: $0) }
        #expect(Set(patterns).count == seeds.count)
        #expect(patterns.allSatisfy { $0 >= 0 && $0 < 4093 })
    }
}

/// A layer drawn one of three ways, shown plain or through a filter.
private final class FilmProbe: Sketch {
    enum Scene {
        /// A sweep of mid-tones with a colored disk, nothing near white.
        case midTones
        /// A white disk on a flat gray.
        case disk(on: Double)
        /// A white disk on a field that is nearly full red and a little green.
        case diskOnRed
        /// One flat gray.
        case flat(Double)
    }

    static let side = 128
    static let diskRadius = 20

    var scene: Scene = .flat(0.5)
    var filter: Filter? = nil

    static func make(_ scene: Scene, filter: Filter?) -> FilmProbe {
        let probe = FilmProbe()
        probe.scene = scene
        probe.filter = filter
        return probe
    }

    override var canvasSize: CanvasSize { .square(Self.side) }

    override func draw() {
        background(.black)
        let layer = makeRenderTarget()
        withTarget(layer) {
            noStroke()
            switch scene {
            case .midTones:
                for x in 0 ..< Self.side {
                    fill(Color(white: 0.1 + 0.5 * Double(x) / Double(Self.side - 1)))
                    drawRect(Double(x), 0, 1, Double(Self.side))
                }
                fill(Color(red: 0.5, green: 0.3, blue: 0.2))
                drawCircle(Double(Self.side / 2), Double(Self.side / 2), Double(Self.diskRadius))
            case .disk(let gray):
                background(Color(white: gray))
                fill(.white)
                drawCircle(Double(Self.side / 2), Double(Self.side / 2), Double(Self.diskRadius))
            case .diskOnRed:
                background(Color(red: 0.9, green: 0.2, blue: 0.2))
                fill(.white)
                drawCircle(Double(Self.side / 2), Double(Self.side / 2), Double(Self.diskRadius))
            case .flat(let gray):
                background(Color(white: gray))
            }
        }
        if let filter {
            drawImage(layer.filtered(filter).image, 0, 0)
        } else {
            drawImage(layer.image, 0, 0)
        }
    }
}
