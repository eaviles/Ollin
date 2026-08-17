@testable import Ollin
import Testing
import CoreGraphics
import Metal

/// Behavioral probes for the live-feed environment (`Environment.feed(_:)`): a feed's
/// frame must actually light the scene (the whole chain: registry, resolve, the wrap
/// shader, the bake), an unchanged frame must reuse its bake, a new frame must re-bake
/// and evict the stale one, and a feed with no frame yet (or one that has deallocated)
/// must fall back to the placeholder sky rather than leaving the scene unlit.
@Suite
@MainActor
struct FeedEnvironmentRenderProbes {

    private func pixels(of image: CGImage) -> [UInt8] {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return data
    }

    /// Mean of one channel over a fractional region (top-left origin).
    private func mean(_ data: [UInt8], width: Int, height: Int, channel: Int,
                      x: ClosedRange<Double>, y: ClosedRange<Double>) -> Double {
        var sum = 0, count = 0
        for py in Int(Double(height) * y.lowerBound)..<Int(Double(height) * y.upperBound) {
            for px in Int(Double(width) * x.lowerBound)..<Int(Double(width) * x.upperBound) {
                sum += Int(data[(py * width + px) * 4 + channel]); count += 1
            }
        }
        return Double(sum) / Double(max(count, 1))
    }

    private func makeRenderer() throws -> (MetalRenderer, MTLCommandBuffer)? {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let cb = queue.makeCommandBuffer() else { return nil }
        let renderer = try MetalRenderer(device: device, pixelFormat: ollinColorPixelFormat,
                                         sampleCount: ollinPreferredSampleCount(device))
        return (renderer, cb)
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theFeedsFrameColorsTheLighting() throws {
        // Two feeds differing only in their frame's color must light the sphere
        // differently, and each toward its own frame's hue. This walks the whole
        // chain: the registry, the resolve, the wrap shader, and the bake.
        let redFeed = StubFeed(color: Color(hex: 0xcc2020))
        let blueFeed = StubFeed(color: Color(hex: 0x2020cc))
        let red = try #require(OllinApp.image(of: FeedProbe.make(.feed(redFeed)), frame: 1))
        let blue = try #require(OllinApp.image(of: FeedProbe.make(.feed(blueFeed)), frame: 1))
        let dR = pixels(of: red), dB = pixels(of: blue)
        func redMinusBlue(_ d: [UInt8], _ img: CGImage) -> Double {
            mean(d, width: img.width, height: img.height, channel: 0,
                 x: 0.4...0.6, y: 0.4...0.6)
            - mean(d, width: img.width, height: img.height, channel: 2,
                   x: 0.4...0.6, y: 0.4...0.6)
        }
        let r = redMinusBlue(dR, red), b = redMinusBlue(dB, blue)
        #expect(r > 20, "expected the red feed to light the sphere red: \(r)")
        #expect(b < -20, "expected the blue feed to light the sphere blue: \(b)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func anUnchangedFrameReusesItsBakeAndANewOneReplacesIt() throws {
        guard let (renderer, cb) = try makeRenderer() else { return }
        let feed = StubFeed(color: Color(hex: 0xcc2020))
        let env = Environment.feed(feed)
        #expect(renderer.resolveIBL(for: env, commandBuffer: cb, blocking: true))
        let first = renderer.currentIBL
        #expect(first != nil)
        // The same frame again: a cache hit, the same maps object, one entry.
        #expect(renderer.resolveIBL(for: env, commandBuffer: cb, blocking: true))
        #expect(renderer.currentIBL === first)
        #expect(renderer.iblCacheStats.count == 1)
        // A new frame: a fresh bake, and the stale generation is evicted.
        feed.image = Image(width: 8, height: 8, color: Color(hex: 0x2020cc))
        #expect(renderer.resolveIBL(for: env, commandBuffer: cb, blocking: true))
        #expect(renderer.currentIBL !== first)
        #expect(renderer.iblCacheStats.count == 1)
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aFeedWithNoFrameYetLightsWithThePlaceholderSky() throws {
        guard let (renderer, cb) = try makeRenderer() else { return }
        let feed = StubFeed(color: nil)   // no frame has arrived
        let env = Environment.feed(feed)
        #expect(renderer.resolveIBL(for: env, commandBuffer: cb, blocking: true))
        #expect(renderer.currentIBL != nil)
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aDeallocatedFeedLightsWithThePlaceholderSky() throws {
        guard let (renderer, cb) = try makeRenderer() else { return }
        var feed: StubFeed? = StubFeed(color: Color(hex: 0xcc2020))
        let env = Environment.feed(feed!)
        feed = nil   // the registry holds it weakly, so it is gone now
        #expect(renderer.resolveIBL(for: env, commandBuffer: cb, blocking: true))
        #expect(renderer.currentIBL != nil)
    }

    @Test
    func theRegistryKeepsIdsStableAndNeverRecyclesIntoALiveRow() throws {
        let a = StubFeed(color: nil), b = StubFeed(color: nil)
        let envA1 = Environment.feed(a), envA2 = Environment.feed(a)
        let envB = Environment.feed(b)
        // The same feed keeps its id; a different feed gets its own.
        #expect(envA1.source == envA2.source)
        #expect(envA1.source != envB.source)
        // A feed that deallocates frees its row; a newcomer gets a fresh id, and
        // the survivor keeps answering to its own.
        var c: StubFeed? = StubFeed(color: nil)
        let envC = Environment.feed(c!)
        c = nil
        let d = StubFeed(color: nil)
        let envD = Environment.feed(d)
        #expect(envD.source != envC.source)
        guard case .feed(let idA) = envA1.source else { Issue.record("not a feed source"); return }
        #expect(FeedEnvironments.feed(for: idA) === a)
        guard case .feed(let idC) = envC.source else { Issue.record("not a feed source"); return }
        #expect(FeedEnvironments.feed(for: idC) == nil)
    }
}

/// A `VideoFeed` with a settable frame, so the probes control exactly what arrives.
private final class StubFeed: VideoFeed {
    var image: Image?
    init(color: Color?) {
        image = color.map { Image(width: 8, height: 8, color: $0) }
    }
    var frame: Image? { image }
    var frameSize: Vector2? { image?.size }
}

/// The probe scene: one matte white sphere under a fixed camera, lit only by the
/// environment under test, so the lighting's color is the frame's color.
private final class FeedProbe: Sketch {
    var probeEnvironment: Environment?

    static func make(_ environment: Environment) -> FeedProbe {
        let probe = FeedProbe()
        probe.probeEnvironment = environment
        return probe
    }

    override var canvasSize: CanvasSize { .square(192) }

    override func draw() {
        background(Color(white: 0.05))
        camera(.orbiting(target: .zero, radius: 5, azimuth: 0, elevation: 0.0,
                         fieldOfView: .pi / 4, near: 1, far: 20))
        if let probeEnvironment { environment(probeEnvironment) }
        fill(.white)
        material(.dielectric(roughness: 0.9))
        drawSphere(radius: 1.2)
    }
}
