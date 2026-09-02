@testable import Ollin
import Testing
import CoreGraphics
import Foundation

/// CPU checks on the `Clouds` value and its bake-cache key, plus Metal-gated render
/// probes for the cloudscape's promises: the weather claims more sky as coverage
/// rises, an overcast dims the whole scene's light, the wind's phase moves the
/// formations, an HDRI ignores clouds, and a bake is deterministic.
@Suite
struct CloudStateTests {

    @Test func parametersClampSane() {
        let c = Clouds(coverage: 3, density: -1, scale: 100, tallness: -2, phase: 5)
        #expect(c.coverage == 1)
        #expect(c.density == 0)
        #expect(c.scale == 4)
        #expect(c.tallness == 0)
        #expect(c.phase == 5)
    }

    @Test func presetsAreOrderedByCoverage() {
        #expect(Clouds.fair.coverage < Clouds.scattered.coverage)
        #expect(Clouds.scattered.coverage < Clouds.broken.coverage)
        #expect(Clouds.broken.coverage < Clouds.overcast.coverage)
    }

    @Test func theModifierRidesTheEnvironment() {
        let e = Environment.sky(sunElevation: 0.5).clouds(.broken)
        #expect(e.clouds == .broken)
        let parameters = Environment.sky().clouds(coverage: 0.3, phase: 2)
        #expect(parameters.clouds?.coverage == 0.3)
        #expect(parameters.clouds?.phase == 2)
    }

    @Test func theCacheKeySeparatesCloudsOnSkiesOnly() {
        // Two cloudscapes over one sky are two bakes; an HDRI ignores clouds, so a
        // stray value must not fragment its cache slot.
        let sky = Environment.sky().source
        let a = IBLKey(source: sky, clouds: .fair)
        let b = IBLKey(source: sky, clouds: .broken)
        let c = IBLKey(source: sky, clouds: .fair)
        #expect(a != b)
        #expect(a == c)
    }
}

/// Rendered probes over the baked environment (the `AerialRenderProbes` idiom): a
/// small scene lit and backdropped by a cloudy `.sky`, sampled at fixed pixels.
@Suite @MainActor
struct CloudRenderProbes {

    private func pixels(_ sketch: Sketch) throws -> (data: [UInt8], width: Int, height: Int) {
        let image = try #require(OllinApp.image(of: sketch, frame: 1))
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return (data, w, h)
    }

    private func meanLuminance(_ p: (data: [UInt8], width: Int, height: Int),
                               rows: Range<Int>) -> Double {
        var sum = 0.0
        var count = 0.0
        for y in rows {
            for x in stride(from: 0, to: p.width, by: 4) {
                let i = (y * p.width + x) * 4
                sum += 0.2126 * Double(p.data[i]) + 0.7152 * Double(p.data[i + 1])
                     + 0.0722 * Double(p.data[i + 2])
                count += 1
            }
        }
        return sum / max(count, 1)
    }

    /// How much of the upper sky band departs from a clear-sky gradient: the count of
    /// sampled sky pixels whose blue lead over red is small (cloud gray) rather than
    /// large (clear blue).
    private func cloudyFraction(_ p: (data: [UInt8], width: Int, height: Int)) -> Double {
        var cloudy = 0.0, total = 0.0
        for y in stride(from: 4, to: p.height / 3, by: 3) {
            for x in stride(from: 0, to: p.width, by: 3) {
                let i = (y * p.width + x) * 4
                let r = Double(p.data[i]), g = Double(p.data[i + 1]), b = Double(p.data[i + 2])
                let lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
                // Clear sky holds a strong blue lead relative to its brightness
                // (measured ~0.56); cloud bodies sit well under it (~0.2-0.45).
                if (b - r) / max(lum, 1) < 0.5 { cloudy += 1 }
                total += 1
            }
        }
        return cloudy / max(total, 1)
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func coverageClaimsMoreSky() throws {
        let fair = CloudSkyProbe(); fair.clouds = Clouds(coverage: 0.2, phase: 3)
        let broken = CloudSkyProbe(); broken.clouds = Clouds(coverage: 0.75, phase: 3)
        let a = cloudyFraction(try pixels(fair))
        let b = cloudyFraction(try pixels(broken))
        #expect(b > a + 0.15, "more coverage should claim more sky (fair \(a), broken \(b))")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func overcastDimsTheScene() throws {
        // The clouds bake into the lighting, so a gray lid must darken a floor lit
        // only by the environment.
        let fair = CloudSkyProbe(); fair.clouds = Clouds(coverage: 0.15)
        let overcast = CloudSkyProbe(); overcast.clouds = Clouds(coverage: 0.95, density: 1.4)
        let litRows = 200 ..< 240
        let a = meanLuminance(try pixels(fair), rows: litRows)
        let b = meanLuminance(try pixels(overcast), rows: litRows)
        #expect(b < a * 0.85, "an overcast should dim the scene's light (fair \(a), overcast \(b))")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func phaseMovesTheWeather() throws {
        let now = CloudSkyProbe(); now.clouds = Clouds(coverage: 0.5, phase: 0)
        let later = CloudSkyProbe(); later.clouds = Clouds(coverage: 0.5, phase: 8)
        #expect(try pixels(now).data != pixels(later).data)
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func anHDRIIgnoresClouds() throws {
        let plain = CloudHDRIProbe()
        let stray = CloudHDRIProbe(); stray.clouds = .overcast
        #expect(try pixels(plain).data == pixels(stray).data)
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func twoBakesMatch() throws {
        let a = CloudSkyProbe(); a.clouds = .scattered
        let b = CloudSkyProbe(); b.clouds = .scattered
        #expect(try pixels(a).data == pixels(b).data)
    }
}

// MARK: - Probe scenes (fixed cameras, no time, no rng)

private final class CloudSkyProbe: Sketch {
    var clouds: Clouds = .scattered
    override var canvasSize: CanvasSize { .square(256) }
    override func draw() {
        background(.black)
        camera(Camera3D(eye: Vector3(0, 1, 8), target: Vector3(0, 2.4, 0)))
        environment(.sky(turbidity: 2.4, sunElevation: 0.6).clouds(clouds))
        fill(Color(white: 0.6))
        withState { translate(0, -0.6, 0); drawBox(width: 30, height: 0.4, depth: 30) }
    }
}

private final class CloudHDRIProbe: Sketch {
    var clouds: Clouds?
    override var canvasSize: CanvasSize { .square(128) }
    override func draw() {
        background(.black)
        camera(Camera3D(eye: Vector3(0, 1, 8), target: Vector3(0, 1, 0)))
        var env = Environment.studio
        if let clouds { env = env.clouds(clouds) }
        environment(env)
        fill(Color(white: 0.6))
        withState { drawSphere(radius: 1) }
    }
}
