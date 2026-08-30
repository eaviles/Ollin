import CoreGraphics
import Foundation
import Metal
@testable import Ollin
import Testing

/// Probes for the ocean: the wave spectrum, the inverse transform of it, and the
/// surface that comes out.
///
/// The claim worth testing is the one a picture cannot show: that `waveHeight` is
/// a *measurement* rather than a dial. The scale is worked out on the CPU from a
/// closed form of the spectrum, so the surface the GPU draws has to stand the
/// height that was asked for, at any grid size and for any wind. These read the
/// field back through a shader that maps one of its channels into gray, and
/// measure it. Metal-gated.
@Suite
@MainActor
struct OceanTests {

    // MARK: The height is a measurement

    /// The headline. A sea asked for a 4 unit significant wave height stands 4
    /// units: four times the standard deviation of the height field, measured off
    /// the GPU's own output.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theSurfaceStandsTheHeightItWasAsked() throws {
        let asked = 4.0
        let measured = try significantHeight(of: Ocean(waveHeight: asked, seed: 3))
        #expect(abs(measured - asked) / asked < 0.2,
                "asked for \(asked), the surface stands \(measured)")
    }

    /// Twice the height is twice the surface, which is what says the scale is
    /// carried through rather than tuned at one setting.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aTallerSeaIsTallerInProportion() throws {
        let low = try significantHeight(of: Ocean(waveHeight: 2, seed: 5))
        let high = try significantHeight(of: Ocean(waveHeight: 4, seed: 5))
        #expect(abs(high / low - 2) < 0.15, "\(low) doubled should be \(high)")
    }

    /// The same sea on a finer grid is the same height. The grid decides how much
    /// detail the field carries, and the closed form is what keeps that from
    /// changing how tall the water stands (a spectrum summed over more modes would
    /// otherwise grow with its resolution).
    @Test(.enabled(if: Snapshot.hasMetal))
    func theHeightHoldsWhenTheGridChanges() throws {
        let sea = Ocean(waveHeight: 4, seed: 11)
        let coarse = try significantHeight(of: sea, resolution: 128)
        let fine = try significantHeight(of: sea, resolution: 256)
        #expect(abs(fine - coarse) / coarse < 0.25,
                "128 stands \(coarse) and 256 stands \(fine)")
    }

    /// Wind moves the energy between short chop and long swell without changing
    /// how tall the water stands. Counted along a row of the field: a light wind
    /// crosses the still line far more often than a strong one, while both keep
    /// their asked-for height.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theWindMovesTheEnergyNotTheHeight() throws {
        let light = Ocean(waveHeight: 3, windSpeed: 7, seed: 9)
        let strong = Ocean(waveHeight: 3, windSpeed: 22, seed: 9)
        let lightCrossings = try crossings(of: light)
        let strongCrossings = try crossings(of: strong)
        #expect(lightCrossings > strongCrossings * 1.4,
                "a light wind should raise shorter waves (\(lightCrossings) crossings against \(strongCrossings))")
        let lightHeight = try significantHeight(of: light)
        let strongHeight = try significantHeight(of: strong)
        #expect(abs(lightHeight - strongHeight) / strongHeight < 0.3,
                "both were asked for 3 units and stand \(lightHeight) and \(strongHeight)")
    }

    // MARK: What the sea is made of

    /// A sea with no chop cannot fold, so nothing foams. The fold is the Jacobian
    /// of the sideways shift, and with no shift it is exactly 1 everywhere.
    @Test(.enabled(if: Snapshot.hasMetal))
    func flatWaterNeverFoams() throws {
        let image = try #require(OllinApp.image(
            of: SeaProbe.make(Ocean(waveHeight: 4, choppiness: 0, seed: 2),
                              channel: 3, scale: 0.25, bias: 0), frame: 1))
        #expect(brightest(image) <= 3, "a sea with no chop should show no fold at all")
    }

    /// Pointed waves do fold, which is where foam belongs.
    @Test(.enabled(if: Snapshot.hasMetal))
    func pointedWavesFold() throws {
        let image = try #require(OllinApp.image(
            of: SeaProbe.make(Ocean(waveHeight: 5, choppiness: 1.5, seed: 2),
                              channel: 3, scale: 0.25, bias: 0), frame: 1))
        #expect(brightest(image) > 40, "steep crests should fold somewhere")
    }

    /// The same seed is the same sea, frame for frame, which is what makes a
    /// sketch reproduce.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theSameSeedIsTheSameSea() throws {
        let first = try #require(OllinApp.image(of: SeaProbe.make(Ocean(seed: 4)), frame: 1))
        let again = try #require(OllinApp.image(of: SeaProbe.make(Ocean(seed: 4)), frame: 1))
        #expect(maxDifference(first, again) == 0)
        let other = try #require(OllinApp.image(of: SeaProbe.make(Ocean(seed: 5)), frame: 1))
        #expect(maxDifference(first, other) > 20, "a different seed should be different water")
    }

    /// A sea given a loop repeats exactly on it: every wave's frequency is rounded
    /// down to a multiple of one step, so the whole surface comes back to where it
    /// started. This is what lets an export loop.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theSeaRepeatsOnItsLoop() throws {
        let sea = Ocean(waveHeight: 3, loopSeconds: 6, seed: 8)
        let start = try #require(OllinApp.image(of: SeaProbe.make(sea, at: 0), frame: 1))
        let round = try #require(OllinApp.image(of: SeaProbe.make(sea, at: 6), frame: 1))
        let halfway = try #require(OllinApp.image(of: SeaProbe.make(sea, at: 3), frame: 1))
        #expect(maxDifference(start, round) <= 2, "the loop should close")
        #expect(maxDifference(start, halfway) > 20, "and the water should move in between")
    }

    // MARK: The drawn water

    /// The surface draws, and it moves. The grid exists only inside the draw, so
    /// this is the one check that the vertex stage really reads the field.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theWaterDrawsAndMoves() throws {
        let first = try #require(OllinApp.image(of: DrawnSeaProbe(), frame: 1))
        let later = try #require(OllinApp.image(of: DrawnSeaProbe(), frame: 40))
        #expect(maxDifference(first, later) > 12, "the water should not stand still")
    }

    // MARK: The closed form, with no GPU

    /// The amplitude the CPU works out scales with the height asked for, which is
    /// the whole point of it: the sum over the spectrum is the sea's shape, and
    /// the height is one factor over the top of it.
    @Test func theAmplitudeFollowsTheHeight() {
        let low = Ocean(waveHeight: 2).amplitude(resolution: 64)
        let high = Ocean(waveHeight: 6).amplitude(resolution: 64)
        #expect(abs(high / low - 3) < 1e-9)
    }

    /// A sea with no waves asks for no amplitude rather than for a division by
    /// nothing.
    @Test func aStillSeaAsksForNothing() {
        #expect(Ocean(waveHeight: 0).amplitude(resolution: 64) == 0)
    }

    /// The grid is rounded to the power of two the transform can climb, and to the
    /// *nearest* one, so 200 texels is 256 rather than 128.
    @Test func theGridIsRoundedToWhatTheLadderCanClimb() {
        #expect(Ocean.roundedResolution(256) == 256)
        #expect(Ocean.roundedResolution(200) == 256)
        #expect(Ocean.roundedResolution(140) == 128)
        #expect(Ocean.roundedResolution(3) == 32)
        #expect(Ocean.roundedResolution(4000) == 1024)
    }

    // MARK: Helpers

    /// Four times the standard deviation of the field's height channel, read back
    /// through the probe's own mapping.
    private func significantHeight(of ocean: Ocean, resolution: Int = 128) throws -> Double {
        let scale = 0.4 / max(0.001, ocean.waveHeight)
        let image = try #require(OllinApp.image(
            of: SeaProbe.make(ocean, channel: 1, scale: scale, resolution: resolution), frame: 1))
        let px = pixels(of: image)
        var sum = 0.0, count = 0.0
        for i in stride(from: 0, to: px.bytes.count, by: 4) {
            let h = (Double(px.bytes[i + 1]) / 255 - 0.5) / scale
            sum += h * h
            count += 1
        }
        return 4 * (sum / max(1, count)).squareRoot()
    }

    /// How often the middle row of the field crosses the still line: a plain
    /// reading of how short the waves are.
    private func crossings(of ocean: Ocean) throws -> Double {
        let scale = 0.4 / max(0.001, ocean.waveHeight)
        let image = try #require(OllinApp.image(
            of: SeaProbe.make(ocean, channel: 1, scale: scale), frame: 1))
        let px = pixels(of: image)
        var total = 0.0
        for row in stride(from: 8, to: px.height, by: 8) {
            var previous = 0.0
            for x in 0 ..< px.width {
                let h = Double(px.bytes[(row * px.width + x) * 4 + 1]) / 255 - 0.5
                if x > 0, (h > 0) != (previous > 0) { total += 1 }
                previous = h
            }
        }
        return total
    }

    private func pixels(of image: CGImage) -> (bytes: [UInt8], width: Int, height: Int) {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        if let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                               bytesPerRow: w * 4, space: space, bitmapInfo: info) {
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return (data, w, h)
    }

    private func brightest(_ image: CGImage) -> Int {
        let px = pixels(of: image)
        var worst = 0
        for i in stride(from: 0, to: px.bytes.count, by: 4) {
            worst = max(worst, Int(px.bytes[i + 1]))
        }
        return worst
    }

    private func maxDifference(_ a: CGImage, _ b: CGImage) -> Int {
        let pa = pixels(of: a), pb = pixels(of: b)
        var worst = 0
        for i in 0 ..< min(pa.bytes.count, pb.bytes.count) {
            worst = max(worst, abs(Int(pa.bytes[i]) - Int(pb.bytes[i])))
        }
        return worst
    }
}

/// One channel of a wave field, mapped into gray so an 8-bit read can measure it.
/// The canvas is the field's own size, so one pixel is one texel and nothing is
/// resampled on the way out.
private final class SeaProbe: Sketch {
    var ocean = Ocean.breeze
    var channel = 1
    var mapScale = 0.1
    var bias = 0.5
    var at = 0.0
    var resolution = 128

    static func make(_ ocean: Ocean, channel: Int = 1, scale: Double = 0.1,
                     bias: Double = 0.5, at: Double = 0, resolution: Int = 128) -> SeaProbe {
        let s = SeaProbe()
        s.ocean = ocean; s.channel = channel; s.mapScale = scale
        s.bias = bias; s.at = at; s.resolution = resolution
        return s
    }

    override var canvasSize: CanvasSize { .square(resolution) }

    override func draw() {
        background(.black)
        let sea = makeOceanField(ocean, at: at, resolution: resolution)
        let mapped = sea.layer.filtered(.shader(Shader("""
        float4 shade(float2 uv, ShaderInfo info) {
            float4 field = sampleRaw(info, uv);
            float v = \(bias) + field[\(channel)] * \(mapScale);
            return float4(v, v, v, 1.0);
        }
        """)))
        drawImage(mapped.image, 0, 0)
    }
}

/// The water as it is actually drawn: the grid the vertex stage builds, seen from
/// just above the surface.
private final class DrawnSeaProbe: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(hex: 0x8FB6D4))
        light(.directional(.white, direction: Vector3(0, -0.3, -0.95)))
        camera(.perspective(eye: Vector3(0, 6, -60), target: Vector3(0, 2, 120)))
        let sea = makeOceanField(Ocean(waveHeight: 3, patchSize: 200, seed: 6), resolution: 128)
        drawOcean(sea, segments: 96, tiles: 3)
    }
}

/// The ocean's GPU cost on this machine: the field (a spectrum pass, the
/// butterfly ladder, and a resolve) and the draw (a grid worked out from vertex
/// indices, shaded per pixel off the same field). Run through
/// `Scripts/benchmark.sh ocean`.
@Suite
@MainActor
struct OceanBenchmarkTests {

    @Test(.benchmark)
    func seaCostByGridAndField() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let renderer = try MetalRenderer(device: device, pixelFormat: ollinColorPixelFormat,
                                         sampleCount: ollinPreferredSampleCount(device))
        let res = 1080
        let viewport = SIMD2<Float>(Float(res), Float(res))

        func measure(segments: Int, resolution: Int) -> Double {
            let sketch = OceanBenchScene()
            sketch.setCanvasSize(width: Double(res), height: Double(res))
            sketch.segments = segments
            sketch.resolution = resolution
            sketch.setup()
            sketch.advance(time: 1, deltaTime: 1 / 60, frameRate: 60)
            sketch.performDraw()
            return renderer.benchmarkGPUMilliseconds(sketch.drawer, viewport: viewport,
                                                     width: res, height: res, iterations: 20)
        }

        print("\n=== Ollin ocean benchmark (\(res)² px, sky environment + sun) ===")
        for (segments, resolution) in [(160, 256), (320, 256), (320, 512), (512, 512)] {
            let ms = measure(segments: segments, resolution: resolution)
            print(String(format: "%4d segments over a %4d field: GPU %6.2f ms (%.0f fps)",
                         segments, resolution, ms, 1000 / max(ms, 0.0001)))
        }
        print("=== end ===\n")
    }
}

/// The benchmark's sea: the example's own camera and sea state, so the numbers
/// measure what the example draws.
@MainActor
private final class OceanBenchScene: Sketch {
    var segments = 320
    var resolution = 256

    override func draw() {
        background(Color(hex: 0x8FB6D4))
        environment(.sky(turbidity: 2.6, sunElevation: 0.13))
        light(.directional(Color(hex: 0xFFF1DC), direction: Vector3(0, -0.13, -0.99),
                           intensity: 1.1))
        camera(.perspective(eye: Vector3(0, 4.6, -95), target: Vector3(0, 2.6, 220),
                            fieldOfView: .pi / 3.4))
        let sea = makeOceanField(Ocean(waveHeight: 2.6, windSpeed: 12, windDirection: 90,
                                   choppiness: 1.25, patchSize: 170, seed: 7),
                             resolution: resolution)
        drawOcean(sea, segments: segments, tiles: 7)
    }
}
