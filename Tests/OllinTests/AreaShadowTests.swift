@testable import Ollin
import Testing
import CoreGraphics
import Foundation

/// What a rectangle light's shadow needs from a sketch, which is `castShadows()`
/// and nothing else. The default ray count follows the device, and an explicit
/// `shadowSamples` is for a render that must look the same on every machine,
/// which is why the Guide's softbox figures name one; these keep the two
/// agreeing, so the explicit count is never mistaken for what makes the
/// shadow show.
///
/// Nothing here diffs a committed image. The shadow is found by comparing a
/// render against the same set unshadowed, so the probes read the same on
/// any GPU that traces.
@Suite(.serialized)
@MainActor
struct AreaShadowTests {

    enum Setting {
        case none, castOnly, samples(Int)
    }

    private func pixels(of image: CGImage) -> [UInt8] {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return data
    }

    private func luminance(_ d: [UInt8], _ i: Int) -> Double {
        0.2126 * Double(d[i * 4]) + 0.7152 * Double(d[i * 4 + 1]) + 0.0722 * Double(d[i * 4 + 2])
    }

    private func render(_ setting: Setting) throws -> [UInt8] {
        let sketch = SoftboxSet()
        sketch.setting = setting
        return pixels(of: try #require(OllinApp.image(of: sketch, frame: 1)))
    }

    /// The pixels a shadowed render darkens against the unshadowed one by a
    /// clear margin, on floor that is lit: where the shadow is.
    private func shadow(in shadowed: [UInt8], against lit: [UInt8]) -> [Int] {
        (0..<(lit.count / 4)).filter { i in
            let a = luminance(lit, i)
            return a > 30 && luminance(shadowed, i) < 0.85 * a
        }
    }

    private func mean(_ d: [UInt8], over mask: [Int]) -> Double {
        mask.map { luminance(d, $0) }.reduce(0, +) / Double(max(1, mask.count))
    }

    /// `castShadows()` alone throws the panel's shadow: thousands of floor
    /// pixels under the spheres read about half as bright as unshadowed.
    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func castShadowsAloneThrowsTheAreaShadow() throws {
        let lit = try render(.none), alone = try render(.castOnly)
        let mask = shadow(in: alone, against: lit)
        #expect(mask.count > 5000, "\(mask.count) shadowed pixels; the set throws about 16,000")
        let depth = 1 - mean(alone, over: mask) / max(1, mean(lit, over: mask))
        #expect(depth > 0.3, "the floor under the spheres is darkened by \(depth) with castShadows() alone")
    }

    /// The count the default resolves to and an explicit count draw the same
    /// shadow: the floor under the spheres reads within three levels of the
    /// fully sampled render, and the shadow covers the same floor.
    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func theDefaultCountAgreesWithAnExplicitOne() throws {
        let lit = try render(.none), full = try render(.samples(48))
        let mask = shadow(in: full, against: lit)
        #expect(mask.count > 5000)
        let reference = mean(full, over: mask)
        for count in [8, 16] {
            let explicit = try render(.samples(count))
            #expect(abs(mean(explicit, over: mask) - reference) < 3,
                    "shadowSamples(\(count)) reads \(mean(explicit, over: mask)) under the spheres against \(reference) at 48")
        }
        let alone = try render(.castOnly)
        #expect(abs(mean(alone, over: mask) - reference) < 3,
                "the default count reads \(mean(alone, over: mask)) under the spheres against \(reference) at 48")
        let aloneMask = shadow(in: alone, against: lit)
        #expect(abs(Double(aloneMask.count - mask.count)) < 0.1 * Double(mask.count),
                "the default count shadows \(aloneMask.count) pixels against \(mask.count) at 48")
    }
}

/// The Guide's softbox set: a matte, a glass and a chrome sphere on a pale
/// floor under one warm panel from the front left, the camera looking down
/// from the front, so every sphere throws its shadow onto floor in frame.
private final class SoftboxSet: Sketch {
    var setting: AreaShadowTests.Setting = .castOnly
    override var canvasSize: CanvasSize { .size(528, 396) }

    override func draw() {
        background(Color(hex: 0x14161B))
        environment(.studio.intensified(to: 0.12))
        rectangleLight(Color(hue: 0.09, saturation: 0.3, brightness: 1.0),
                       at: Vector3(-2.8, 2.6, 2.2), direction: Vector3(0.68, -0.5, -0.53),
                       width: 2.0, height: 1.5, intensity: 30)
        switch setting {
        case .none: break
        case .castOnly: castShadows()
        case .samples(let n): castShadows(); shadowSamples(n)
        }

        camera(Camera3D(eye: Vector3(0.3, 3.2, 6.0), target: Vector3(0, 0.3, -0.2),
                        projection: .perspective(fieldOfView: .pi / 4.4)))

        withState {
            translate(0, -0.5, 0)
            fill(Color(white: 0.72))
            material(.dielectric(roughness: 0.55))
            drawBox(width: 16, height: 1, depth: 12)
        }

        let finishes: [(Color, Material)] = [
            (Color(hue: 0.01, saturation: 0.8, brightness: 0.85), .dielectric(roughness: 0.4)),
            (Color(hue: 0.1, saturation: 0.45, brightness: 1.0),
             .glass(thickness: 1, attenuationColor: Color(hue: 0.09, saturation: 0.75, brightness: 0.9),
                    attenuationDistance: 0.9)),
            (Color(white: 0.95), .metal(roughness: 0.04)),
        ]
        for (i, f) in finishes.enumerated() {
            withState {
                translate(-2.1 + Double(i) * 2.1, 0.7, 0)
                fill(f.0)
                material(f.1)
                drawSphere(radius: 0.7)
            }
        }
    }
}
