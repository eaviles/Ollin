@testable import Ollin
import COllinShaders
import CoreGraphics
import Foundation
import simd
import Testing

/// Behavioral probes for `reflectionBounces`, the length of one traced reflection
/// chain. The shipped pair (2) shades a hit and that hit's own mirror image, then
/// ends at the environment. Where two mirrors face each other that cut is visible:
/// the corridor's tunnel of images stops at the third door and the sky stands in it.
///
/// The probe reads the panel of sky the pair leaves there, because that is the one
/// place in the frame where a chain is longer than two surfaces. Every reading is a
/// counterfactual against the default, since nothing else in the picture moves.
/// RT-gated: without ray tracing there is no traced reflection to lengthen.
@Suite
@MainActor
struct ReflectionBounceTests {

    /// Mean brightness of the deep panel: the image, inside the near mirror, of what
    /// the far mirror shows. The pair fills it with the environment's bright sky; a
    /// longer chain fills it with the corridor, which is darker.
    private func panelMean(_ bounces: Int?) throws -> Double {
        let image = try #require(OllinApp.image(of: MirrorTunnelProbe.make(bounces), frame: 1))
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        var sum = 0, count = 0
        for y in (h * 25 / 100)..<(h * 33 / 100) {
            for x in (w * 60 / 100)..<(w * 95 / 100) {
                let i = (y * w + x) * 4
                sum += Int(data[i]) + Int(data[i + 1]) + Int(data[i + 2]); count += 3
            }
        }
        return Double(sum) / Double(count)
    }

    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func aThirdSurfaceOpensTheTunnel() throws {
        // The reading with teeth: at the pair the panel is sky, and one more surface
        // puts the corridor back in it.
        let pair = try panelMean(2)
        let three = try panelMean(3)
        #expect(pair - three > 40,
                "expected a third surface to replace the sky panel with the corridor: pair \(pair), three \(three)")
    }

    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func theDefaultShadesThePair() throws {
        // No call is the pair, exactly. Not close: the same instructions run, so the
        // two frames are one frame.
        let byDefault = try panelMean(nil)
        let pair = try panelMean(2)
        #expect(byDefault == pair,
                "expected the default to shade the pair: default \(byDefault), asked for 2 \(pair)")
    }

    @Test func theCountIsClampedToWhatTheWalkCarries() {
        // Both ends of the range, on the CPU, since neither end can be read off the
        // picture: the pair is the floor (it is what keeps a polished corner from
        // piping the environment through itself), and the ceiling is what the walk is
        // built to carry. The shader bounds its own loop as well, so this clamp is the
        // outer of two; it is here that a sketch's number is answered for.
        let sketch = Sketch()
        sketch.reflectionBounces(1)
        #expect(sketch.drawer.reflectionBouncesSetting == 2, "a count under the pair clamps up to it")
        sketch.reflectionBounces(-7)
        #expect(sketch.drawer.reflectionBouncesSetting == 2, "so does a negative one")
        sketch.reflectionBounces(3)
        #expect(sketch.drawer.reflectionBouncesSetting == 3, "a count inside the range is taken as given")
        sketch.reflectionBounces(Int(OLLIN_MAX_REFLECTION_BOUNCES) * 12)
        #expect(sketch.drawer.reflectionBouncesSetting == Int(OLLIN_MAX_REFLECTION_BOUNCES),
                "a count past the ceiling clamps down to it")
    }

    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func theChainSettles() throws {
        // Each surface dims the one behind it, and the corridor's rays leave it, so the
        // panel stops moving well before the ceiling. That is why the ceiling can be a
        // small number: 3 or 4 is what a sketch can actually see.
        let opening = abs(try panelMean(3) - (try panelMean(2)))
        let settled = abs(try panelMean(Int(OLLIN_MAX_REFLECTION_BOUNCES)) - (try panelMean(5)))
        #expect(opening > 40 && settled < 1,
                "expected the tunnel to settle: the first step moves \(opening), the last \(settled)")
    }
}

/// The probe scene: a corridor of two facing mirrors with a bright block in it, the
/// eye standing between them and looking at one mirror at an angle, so every
/// reflected ray crosses the corridor and meets the other mirror. `bounces` is nil
/// for the default, the call never made.
private final class MirrorTunnelProbe: Sketch {
    var bounces: Int?

    static func make(_ bounces: Int?) -> MirrorTunnelProbe {
        let probe = MirrorTunnelProbe()
        probe.bounces = bounces
        return probe
    }

    override var canvasSize: CanvasSize { .square(256) }

    private let slab = Mesh.box(width: 0.4, height: 6, depth: 14)
    private let block = Mesh.box(width: 0.8, height: 0.8, depth: 0.8)

    override func draw() {
        background(.black)
        camera(.orbiting(target: Vector3(3, 0, 0), radius: 3.2,
                         azimuth: -1.216, elevation: 0.12))
        environment(.night)
        directionalLight(.white, direction: Vector3(0.3, 1, 0.4), intensity: 2.4)
        rayTracedReflections()
        if let bounces { reflectionBounces(bounces) }
        for side in [-1.0, 1.0] {
            withState {
                fill(Color(white: 0.95))
                material(.metal(roughness: 0.03))
                translate(side * 3.2, 0, 0)
                drawMesh(slab)
            }
        }
        withState {
            fill(Color(red: 1.0, green: 0.2, blue: 0.05))
            material(.dielectric(roughness: 0.35))
            translate(0.9, -0.7, 0.2)
            drawMesh(block)
        }
    }
}
