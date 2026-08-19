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

    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func aGlassFieldAbsorbsLikeAGlassMesh() throws {
        // The same green-attenuated glass body, once as a mesh sphere and once as a
        // marched field of the same radius, with a white slab behind. A field owns no
        // triangles for the traced transmission walk to hit, so it has to hand the walk
        // its own far interface; without that the walk takes the slab for the exit and
        // absorbs over the run to it, which reads far darker than the mesh and moves
        // when the slab does. Two things are pinned: the two shapes agree, and the
        // field's tint doesn't follow the slab.
        let meshImg = try #require(OllinApp.image(of: GlassProbe.make(kind: .absorbingMesh), frame: 1))
        let fieldImg = try #require(OllinApp.image(of: GlassProbe.make(kind: .absorbingField), frame: 1))
        let farImg = try #require(OllinApp.image(of: GlassProbe.make(kind: .absorbingFieldFarSlab), frame: 1))
        func center(_ img: CGImage, _ channel: Int) -> Double {
            mean(pixels(of: img), width: img.width, height: img.height, channel: channel,
                 x: 0.45...0.55, y: 0.47...0.53)
        }
        // The tint has to be there at all, or agreeing on nothing would pass.
        let meshTint = center(meshImg, 1) - center(meshImg, 0)
        #expect(meshTint > 60, "expected the mesh body visibly green-tinted: \(meshTint)")
        for channel in 0...2 {
            let m = center(meshImg, channel), f = center(fieldImg, channel)
            #expect(abs(m - f) < 6,
                    "channel \(channel): field \(f) should absorb like the mesh \(m)")
        }
        for channel in 0...2 {
            let near = center(fieldImg, channel), far = center(farImg, channel)
            #expect(abs(near - far) < 6,
                    "channel \(channel): the field's absorption followed the slab, \(near) to \(far)")
        }
        // Both bodies sit in the same place, so the interior compares pixel by pixel.
        // A mean alone would miss a banded interior: a march that resolves the exit at
        // some radii and not at others prints the body in thin rings that average away.
        let (meanDiff, peakDiff) = interiorDifference(meshImg, fieldImg)
        #expect(meanDiff < 8, "the field's interior differs from the mesh's by \(meanDiff)")
        #expect(peakDiff < 40, "the field's interior is banded, peaking at \(peakDiff)")
    }

    /// Mean and worst per-pixel channel difference over a disc well inside both
    /// silhouettes. The mask is a disc, not a square: the body fills most of the frame,
    /// so a square's corners reach the rim and read its anti-aliasing (analytic on the
    /// field, multisampled on the mesh) as if it were interior disagreement.
    private func interiorDifference(_ a: CGImage, _ b: CGImage) -> (Double, Double) {
        let da = pixels(of: a), db = pixels(of: b)
        var sum = 0.0, count = 0.0, peak = 0.0
        let radius = 0.13 * Double(a.width)          // ~57% of the body's screen radius
        let cx = 0.5 * Double(a.width), cy = 0.5 * Double(a.height)
        for py in 0..<a.height {
            for px in 0..<a.width {
                let dx = Double(px) - cx, dy = Double(py) - cy
                guard dx * dx + dy * dy <= radius * radius else { continue }
                for channel in 0...2 {
                    let i = (py * a.width + px) * 4 + channel
                    let d = abs(Double(da[i]) - Double(db[i]))
                    sum += d; count += 1; peak = max(peak, d)
                }
            }
        }
        return (sum / max(count, 1), peak)
    }
}

/// The probe scene, one variant per case: a single glass body under a fixed camera,
/// with the environment / tracing / thickness varied by `kind`.
private final class GlassProbe: Sketch {
    enum Kind {
        case noEnvGlass, noEnvDielectric      // no environment: must match exactly
        case attenuationThin, attenuationThick
        case paneTraced, paneEnvOnly
        case absorbingMesh, absorbingField, absorbingFieldFarSlab
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
        case .absorbingMesh, .absorbingField, .absorbingFieldFarSlab:
            environment(.studio.intensity(1.4))
            rayTracedReflections()
            // The white slab the interior ray would otherwise mistake for the body's exit.
            withState {
                translate(0, 0, kind == .absorbingFieldFarSlab ? -9 : -3)
                fill(.white)
                material(.matte)
                drawBox(width: 24, height: 16, depth: 0.2)
            }
            fill(.white)
            material(.glass(thickness: 1.6,
                            attenuationColor: Color(hue: 0.33, saturation: 0.95, brightness: 0.7),
                            attenuationDistance: 2))
            if kind == .absorbingMesh {
                drawSphere(radius: 0.95)
            } else {
                drawSDF3D(.sphere(radius: 0.95))
            }
        }
    }
}
