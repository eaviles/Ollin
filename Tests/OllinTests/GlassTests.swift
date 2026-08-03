@testable import Ollin
import Testing
import CoreGraphics

/// Behavioral probes for the transmissive (glass) material: the invariants a mean-diff
/// snapshot can't pin. Transmission must be *inert without an environment* (byte-equal
/// to the plain dielectric it would otherwise be), absorption must deepen with the
/// interior span, and on a ray-tracing GPU the traced walk must show the actual scene
/// through the glass where the environment path can't.
@Suite
@MainActor
struct GlassRenderProbes {

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

    @Test(.enabled(if: Snapshot.hasMetal))
    func withoutAnEnvironmentGlassIsAPlainDielectric() throws {
        // No environment means nothing to transmit: the glass sphere must render
        // byte-identical to the same sphere as an opaque dielectric (the documented
        // gate; the transmission block and the direct-light diffKeep never engage).
        let glass = try #require(OllinApp.image(of: GlassProbe.make(kind: .noEnvGlass), frame: 1))
        let plain = try #require(OllinApp.image(of: GlassProbe.make(kind: .noEnvDielectric), frame: 1))
        #expect(pixels(of: glass) == pixels(of: plain))
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func absorptionDeepensWithTheInteriorSpan() throws {
        // Two green-attenuated solid spheres differing only in thickness: the thicker
        // body's interior span is longer, so its center must come out darker.
        let thin = try #require(OllinApp.image(of: GlassProbe.make(kind: .attenuationThin), frame: 1))
        let thick = try #require(OllinApp.image(of: GlassProbe.make(kind: .attenuationThick), frame: 1))
        let dThin = pixels(of: thin), dThick = pixels(of: thick)
        func luma(_ d: [UInt8], _ img: CGImage) -> Double {
            mean(d, width: img.width, height: img.height, channel: 1,
                 x: 0.42...0.58, y: 0.42...0.58)
        }
        let a = luma(dThin, thin), b = luma(dThick, thick)
        #expect(a - b > 8, "expected the thicker body darker at center: thin \(a), thick \(b)")
    }

    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func theTracedWalkShowsTheSceneThroughTheGlass() throws {
        // A red wall stands behind a thin glass pane, out of the environment's picture.
        // The environment-refraction base path can only show the studio behind the
        // pane; the traced walk passes through the pane's own shell and hits the wall,
        // so the pane's interior must go red only when rayTracedReflections() is on.
        let traced = try #require(OllinApp.image(of: GlassProbe.make(kind: .paneTraced), frame: 1))
        let envOnly = try #require(OllinApp.image(of: GlassProbe.make(kind: .paneEnvOnly), frame: 1))
        let dT = pixels(of: traced), dE = pixels(of: envOnly)
        func redness(_ d: [UInt8], _ img: CGImage) -> Double {
            mean(d, width: img.width, height: img.height, channel: 0,
                 x: 0.40...0.60, y: 0.40...0.60)
            - mean(d, width: img.width, height: img.height, channel: 2,
                   x: 0.40...0.60, y: 0.40...0.60)
        }
        let r = redness(dT, traced), e = redness(dE, envOnly)
        #expect(r - e > 25, "expected the wall's red through the traced pane: traced \(r), env-only \(e)")
    }
}

/// The probe scene, one variant per case: a single glass body under a fixed camera,
/// with the environment / tracing / thickness varied by `kind`.
private final class GlassProbe: Sketch {
    enum Kind {
        case noEnvGlass, noEnvDielectric      // no environment: must match exactly
        case attenuationThin, attenuationThick
        case paneTraced, paneEnvOnly
    }
    var kind: Kind = .noEnvGlass

    static func make(kind: Kind) -> GlassProbe {
        let probe = GlassProbe()
        probe.kind = kind
        return probe
    }

    override var canvasSize: CanvasSize { .square(192) }

    override func draw() {
        background(Color(white: 0.05))
        camera(.orbiting(target: .zero, radius: 5, azimuth: 0, elevation: 0.0,
                         fieldOfView: .pi / 4, near: 1, far: 20))
        switch kind {
        case .noEnvGlass, .noEnvDielectric:
            directionalLight(.white, direction: Vector3(-0.4, -1, -0.3), intensity: 1)
            fill(Color(hue: 0.58, saturation: 0.5, brightness: 0.9))
            material(kind == .noEnvGlass ? .glass() : .dielectric(roughness: 0))
            drawSphere(radius: 1.2)
        case .attenuationThin, .attenuationThick:
            environment(.studio)
            fill(.white)
            let t = kind == .attenuationThin ? 0.6 : 3.0
            material(.glass(thickness: t, attenuationColor: Color(hex: 0x2e8f5b),
                            attenuationDistance: 0.8))
            drawSphere(radius: 1.2)
        case .paneTraced, .paneEnvOnly:
            environment(.studio)
            if kind == .paneTraced { rayTracedReflections() }
            // The red wall the environment knows nothing about.
            withState {
                fill(Color(hex: 0xd94430))
                material(.dielectric(roughness: 0.8))
                translate(0, 0, -2.5)
                drawBox(width: 8, height: 8, depth: 0.4)
            }
            fill(.white)
            material(.glass())
            drawSphere(radius: 1.2)
        }
    }
}
