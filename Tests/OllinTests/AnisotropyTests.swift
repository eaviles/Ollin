@testable import Ollin
import Testing
import CoreGraphics

/// Packing checks for the anisotropic-specular fields: the strength clamps to its
/// signed range, and the rotation ships as cos/sin so the fragment never evaluates
/// the angle.
@Suite
struct AnisotropyPackingTests {

    @Test
    func anisotropyClampsAndPacks() {
        let m = Material(shading: .physicallyBased, roughness: 0.4,
                         anisotropy: 0.8, anisotropyRotation: .pi / 2)
        let g = m.gpuMaterial()
        #expect(abs(g.anisotropy.x - 0.8) < 1e-6)
        #expect(abs(g.anisotropy.y - Float(cos(Double.pi / 2))) < 1e-6)
        #expect(abs(g.anisotropy.z - 1) < 1e-6)

        let clamped = Material(shading: .physicallyBased, anisotropy: -3)
        #expect(clamped.anisotropy == -1)
    }

    @Test
    func theDefaultKeepsTheGateDown() {
        let g = Material(shading: .physicallyBased).gpuMaterial()
        #expect(g.anisotropy.x == 0)
    }
}

/// Behavioral probes for the anisotropic specular lobe: under a frontal light the
/// highlight on a sphere must stretch into a streak along the brushing direction,
/// the rotation must spin that streak, a negative strength must run it the other
/// way, and the environment gather must follow the stretch (the bent reflection
/// vector). A mean-diff snapshot can't pin a highlight's *shape*, so each probe
/// measures the extent of the bright region along each axis (peaks and extents,
/// not region means).
@Suite
@MainActor
struct AnisotropyRenderProbes {

    private func pixels(of image: CGImage) -> [UInt8] {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return data
    }

    /// The bright region's pixel extent along x and y: the bounding box of every
    /// pixel whose green channel clears `threshold`, over the sphere's disc.
    private func extents(_ image: CGImage, threshold: Int = 110) -> (x: Int, y: Int) {
        let d = pixels(of: image)
        var minX = Int.max, maxX = Int.min, minY = Int.max, maxY = Int.min
        for py in Int(Double(image.height) * 0.15)..<Int(Double(image.height) * 0.85) {
            for px in Int(Double(image.width) * 0.15)..<Int(Double(image.width) * 0.85) {
                if Int(d[(py * image.width + px) * 4 + 1]) > threshold {
                    minX = min(minX, px); maxX = max(maxX, px)
                    minY = min(minY, py); maxY = max(maxY, py)
                }
            }
        }
        guard maxX >= minX else { return (0, 0) }
        return (maxX - minX + 1, maxY - minY + 1)
    }

    private func meanAbsDiff(_ a: CGImage, _ b: CGImage) -> Double {
        let da = pixels(of: a), db = pixels(of: b)
        var sum = 0, count = 0
        for py in Int(Double(a.height) * 0.25)..<Int(Double(a.height) * 0.75) {
            for px in Int(Double(a.width) * 0.25)..<Int(Double(a.width) * 0.75) {
                let i = (py * a.width + px) * 4 + 1
                sum += abs(Int(da[i]) - Int(db[i])); count += 1
            }
        }
        return Double(sum) / Double(max(count, 1))
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theHighlightStretchesAlongTheBrushDirection() throws {
        // A brushed metal under a frontal light: the isotropic sphere's highlight is
        // round, the anisotropic one's must streak wide along the surface's tangent
        // axis (horizontal, on the world-derived frame a bare sphere gets).
        let iso = try #require(OllinApp.image(of: AnisoProbe.make(kind: .iso), frame: 1))
        let brushed = try #require(OllinApp.image(of: AnisoProbe.make(kind: .brushed), frame: 1))
        let a = extents(brushed), i = extents(iso)
        #expect(a.x > 0 && i.x > 0, "expected a highlight in both renders")
        #expect(Double(a.x) > 1.8 * Double(a.y),
                "expected a horizontal streak: \(a)")
        #expect(Double(i.x) < 1.4 * Double(i.y),
                "expected the isotropic highlight round: \(i)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theRotationSpinsTheStreak() throws {
        // A quarter-turn rotation must run the same streak vertically.
        let turned = try #require(OllinApp.image(of: AnisoProbe.make(kind: .turned), frame: 1))
        let e = extents(turned)
        #expect(e.y > 0, "expected a highlight")
        #expect(Double(e.y) > 1.8 * Double(e.x), "expected a vertical streak: \(e)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func negativeStrengthRunsTheStreakTheOtherWay() throws {
        // The sign swaps the two roughnesses, so -0.85 reads like the quarter turn.
        let neg = try #require(OllinApp.image(of: AnisoProbe.make(kind: .negative), frame: 1))
        let e = extents(neg)
        #expect(e.y > 0, "expected a highlight")
        #expect(Double(e.y) > 1.8 * Double(e.x), "expected a vertical streak: \(e)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theEnvironmentGatherFollowsTheStretch() throws {
        // Under an environment alone the bent reflection vector must move the gather:
        // the anisotropic sphere reads the studio differently from the isotropic one.
        let iso = try #require(OllinApp.image(of: AnisoProbe.make(kind: .isoEnv), frame: 1))
        let brushed = try #require(OllinApp.image(of: AnisoProbe.make(kind: .brushedEnv), frame: 1))
        let d = meanAbsDiff(iso, brushed)
        #expect(d > 2, "expected the bent gather to change the reflection: diff \(d)")
    }
}

/// The probe scene, one variant per case: a single metal sphere under a fixed frontal
/// camera, the anisotropy fields and the lighting route varied by `kind`.
private final class AnisoProbe: Sketch {
    enum Kind {
        case iso, brushed, turned, negative   // frontal directional: the streak's axis
        case isoEnv, brushedEnv               // IBL only: the bent gather
    }
    var kind: Kind = .iso

    static func make(kind: Kind) -> AnisoProbe {
        let probe = AnisoProbe()
        probe.kind = kind
        return probe
    }

    override var canvasSize: CanvasSize { .square(192) }

    override func draw() {
        background(Color(white: 0.05))
        camera(.orbiting(target: .zero, radius: 5, azimuth: 0, elevation: 0.0,
                         fieldOfView: .pi / 4, near: 1, far: 20))
        var metal = Material(shading: .physicallyBased, metallic: 1, roughness: 0.45)
        switch kind {
        case .iso: break
        case .brushed: metal.anisotropy = 0.85
        case .turned:
            metal.anisotropy = 0.85
            metal.anisotropyRotation = .pi / 2
        case .negative: metal.anisotropy = -0.85
        case .isoEnv, .brushedEnv:
            metal.roughness = 0.3
            if kind == .brushedEnv { metal.anisotropy = 0.9 }
        }
        switch kind {
        case .isoEnv, .brushedEnv:
            environment(.studio)
        default:
            directionalLight(.white, direction: Vector3(0, 0, -1), intensity: 1.5)
        }
        fill(Color(white: 0.75))
        material(metal)
        drawSphere(radius: 1.2)
    }
}
