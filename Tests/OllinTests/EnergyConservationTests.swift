@testable import Ollin
import Testing
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// The white-furnace pins for the raster image-based lighting: a white metal sphere
/// inside a constant gray environment must render the environment back at every
/// roughness. The background pixels show the field directly, so the sphere-to-
/// background ratio measures the specular lobe's kept energy with no calibration
/// (the auto-exposure normalization cancels out of the ratio). An uncompensated
/// single-scatter lobe keeps 36% at roughness 1; these pins hold the
/// multiple-scattering compensation level from both sides, so a regression that
/// loses the bounces and one that over-fills the lobe both go red.
@Suite
@MainActor
struct EnergyConservationTests {

    /// One furnace scene: a white metal sphere, a fixed head-on camera, the constant
    /// gray environment as the only light.
    private final class FurnaceProbe: Sketch {
        var rough = 1.0
        var envURL = URL(fileURLWithPath: "/dev/null")

        static func make(rough: Double, envURL: URL) -> FurnaceProbe {
            let p = FurnaceProbe()
            p.rough = rough
            p.envURL = envURL
            return p
        }

        override var canvasSize: CanvasSize { .square(192) }

        override func draw() {
            background(.black)
            camera(Camera3D(eye: Vector3(0, 0, 10), target: .zero,
                            projection: .perspective(fieldOfView: .pi / 4.2)))
            environment(.hdri(url: envURL))
            withState {
                fill(.white)
                material(.metal(roughness: rough))
                drawSphere(radius: 2)
            }
        }
    }

    /// Write the constant gray environment once per run: an 8x4 equirect whose every
    /// pixel is the same mid gray, so the lat-long mapping is constant everywhere.
    private func makeGrayEnvironment() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollin-energy-furnace-env.png")
        let w = 8, h = 4
        var bytes = [UInt8](repeating: 188, count: w * h * 4)
        for i in stride(from: 3, to: bytes.count, by: 4) { bytes[i] = 255 }
        let ctx = try #require(CGContext(
            data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try #require(ctx.makeImage())
        let dest = try #require(CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, nil)
        #expect(CGImageDestinationFinalize(dest))
        return url
    }

    /// Linear-light mean of the render inside the sphere's disc and out in the
    /// background, as (disc, background). The disc radius follows the probe's fixed
    /// projection (radius-2 sphere at distance 10, the canvas 192), pulled in for
    /// margin against the silhouette's blend.
    private func furnaceMeans(_ image: CGImage) -> (disc: Double, bg: Double) {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        func linear(_ b: UInt8) -> Double {
            let c = Double(b) / 255
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        var discSum = 0.0, bgSum = 0.0
        var discN = 0, bgN = 0
        let cx = Double(w) / 2, cy = Double(h) / 2
        for py in 0..<h {
            for px in 0..<w {
                let dx = Double(px) - cx, dy = Double(py) - cy
                let d = (dx * dx + dy * dy).squareRoot()
                guard d < 40 || d > 60 else { continue }
                let i = (py * w + px) * 4
                let v = (linear(data[i]) + linear(data[i + 1]) + linear(data[i + 2])) / 3
                if d < 40 { discSum += v; discN += 1 } else { bgSum += v; bgN += 1 }
            }
        }
        return (discSum / Double(max(discN, 1)), bgSum / Double(max(bgN, 1)))
    }

    @Test(.enabled(if: Snapshot.hasMetal), arguments: [0.05, 0.5, 1.0])
    func aWhiteMetalKeepsTheFurnaceLevel(rough: Double) throws {
        let env = try makeGrayEnvironment()
        let image = try #require(OllinApp.image(of: FurnaceProbe.make(rough: rough, envURL: env),
                                                frame: 1))
        let (disc, bg) = furnaceMeans(image)
        #expect(bg > 0.1, "expected the environment as the background, read \(bg)")
        let kept = disc / bg
        #expect(kept > 0.965 && kept < 1.02,
                "roughness \(rough) kept \(kept * 100)% of the field")
    }
}
