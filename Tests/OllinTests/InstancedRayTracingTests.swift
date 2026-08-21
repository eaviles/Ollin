@testable import Ollin
import CoreGraphics
import Foundation
import Testing

/// Behavioral probes for instanced copies inside the ray-traced passes. A copy
/// drawn through `drawMesh(_:instances:)` must reach a traced reflection and a
/// traced point-light shadow the same way the plain `drawMesh` it replaces does:
/// the instanced call is a cost optimization, so the picture may not change.
///
/// Both probes are written as counterfactual pairs against the plain-mesh draw,
/// because that is the only reading that separates "the copy is missing" from
/// "the copy is there but shaded a little differently". A whole-frame snapshot
/// averages a missing reflection away.
/// RT-gated: without ray tracing the raster paths already carry the copies.
@Suite
@MainActor
struct InstancedRayTracingTests {

    /// Mean red-minus-blue over the band of the mirror floor holding the red box's
    /// reflected image. The box itself sits above that band, so its raster pixels stay
    /// out of the reading. Red minus blue rather than plain brightness: the night
    /// environment the floor otherwise mirrors is cool and near neutral, so the
    /// difference rises only where the red body actually reaches the mirror.
    private func mirroredBoxMean(_ how: InstancedReflectionProbe.How) throws -> Double {
        let scene = InstancedReflectionProbe.make(how)
        let image = try #require(OllinApp.image(of: scene, frame: 1))
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        var sum = 0, count = 0
        for y in (h * 58 / 100)..<(h * 74 / 100) {
            for x in (w * 40 / 100)..<(w * 60 / 100) {
                let i = (y * w + x) * 4
                sum += Int(data[i]) - Int(data[i + 2]); count += 1
            }
        }
        return Double(sum) / Double(count)
    }

    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func aPlainBoxShowsInTheMirrorFloor() throws {
        // The control that gives the next test its teeth: the plain draw must put a
        // clearly red image in the measured band, and removing the box must clear it.
        let there = try mirroredBoxMean(.plain)
        let gone = try mirroredBoxMean(.nothing)
        #expect(there - gone > 20,
                "expected a plain box to redden the floor it mirrors in: with \(there), without \(gone)")
    }

    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func anInstancedCopyShowsInTheMirrorFloorToo() throws {
        // The same box through the instanced call, placed identically. Any gap here is
        // the copy missing from the traced scene, not a shading difference.
        let plain = try mirroredBoxMean(.plain)
        let instanced = try mirroredBoxMean(.instanced)
        #expect(abs(plain - instanced) < 4,
                "expected an instanced copy to mirror like the plain mesh: plain \(plain), instanced \(instanced)")
    }

    /// Mean brightness of the floor patch the box's shadow falls on. The light stands
    /// off to one side, so the patch holds shadow rather than the box itself.
    private func shadowedFloorMean(_ how: InstancedShadowProbe.How) throws -> Double {
        let scene = InstancedShadowProbe.make(how)
        let image = try #require(OllinApp.image(of: scene, frame: 1))
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        var sum = 0, count = 0
        for y in (h * 46 / 100)..<(h * 55 / 100) {
            for x in (w * 10 / 100)..<(w * 26 / 100) {
                sum += Int(data[(y * w + x) * 4]); count += 1
            }
        }
        return Double(sum) / Double(count)
    }

    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func aCopyCarriesItsOwnColorIntoTheMirror() throws {
        // A copy's `color` multiplies the surface it was drawn with, and the mirror has
        // to show that rather than the untinted base mesh every copy shares.
        let white = try mirroredBoxMean(.whiteCopy)
        let tinted = try mirroredBoxMean(.tintedCopy)
        #expect(tinted - white > 20,
                "expected a tinted copy to mirror in its own color: white \(white), tinted \(tinted)")
    }

    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func aPlainBoxCastsATracedPointShadow() throws {
        // The control: a point light traces its shadow on a ray-tracing GPU, so the
        // plain box must darken the floor patch it stands over.
        let there = try shadowedFloorMean(.plain)
        let gone = try shadowedFloorMean(.nothing)
        #expect(gone - there > 20,
                "expected a plain box to shade the floor under it: with \(there), without \(gone)")
    }

    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func anInstancedCopyCastsATracedPointShadowToo() throws {
        // The same box through the instanced call. A copy that the traced structure
        // never held would leave this patch as bright as an empty floor.
        let plain = try shadowedFloorMean(.plain)
        let instanced = try shadowedFloorMean(.instanced)
        #expect(abs(plain - instanced) < 4,
                "expected an instanced copy to shade like the plain mesh: plain \(plain), instanced \(instanced)")
    }
}

/// The shadow probe scene: one box over a plain white floor under a single point light
/// standing above it, so the box's shadow lands in the measured patch.
private final class InstancedShadowProbe: Sketch {
    enum How { case plain, instanced, nothing }
    var how: How = .plain

    static func make(_ how: How) -> InstancedShadowProbe {
        let probe = InstancedShadowProbe()
        probe.how = how
        return probe
    }

    override var canvasSize: CanvasSize { .square(256) }

    private let box = Mesh.box(width: 1.6, height: 1.6, depth: 1.6)

    override func draw() {
        background(.black)
        camera(.orbiting(target: Vector3(0, 0.4, 0), radius: 9,
                         azimuth: 0.2, elevation: 0.45))
        pointLight(.white, at: Vector3(5, 6, 0), intensity: 1.0)
        castShadows()
        withState {
            fill(Color(white: 0.9))
            drawPlane(width: 16, depth: 12)
        }
        withState {
            fill(Color(white: 0.8))
            switch how {
            case .plain:
                translate(0, 1.6, 0)
                drawMesh(box)
            case .instanced:
                drawMesh(box, instances: [MeshInstance(position: Vector3(0, 1.6, 0))])
            case .nothing:
                break
            }
        }
    }
}

/// The probe scene: one red box over a near-mirror metal floor under a bundled
/// environment, its reflection the thing measured. `How` draws the box through the
/// plain call, through the instanced call at the same place, or not at all.
private final class InstancedReflectionProbe: Sketch {
    enum How { case plain, instanced, nothing, whiteCopy, tintedCopy }
    var how: How = .plain

    static func make(_ how: How) -> InstancedReflectionProbe {
        let probe = InstancedReflectionProbe()
        probe.how = how
        return probe
    }

    override var canvasSize: CanvasSize { .square(256) }

    private let box = Mesh.box(width: 1.6, height: 1.6, depth: 1.6)

    override func draw() {
        background(.black)
        camera(.orbiting(target: Vector3(0, 0.6, 0), radius: 9,
                         azimuth: 0.2, elevation: 0.30))
        environment(.night)
        rayTracedReflections()
        withState {
            fill(Color(white: 0.9))
            material(.metal(roughness: 0.05))
            drawPlane(width: 16, depth: 12)
        }
        withState {
            let red = Color(red: 1.0, green: 0.05, blue: 0.05)
            let up = Vector3(0, 1.5, 0)
            material(.dielectric(roughness: 0.5))
            switch how {
            case .plain:
                fill(red)
                translate(0, 1.5, 0)
                drawMesh(box)
            case .instanced:
                fill(red)
                drawMesh(box, instances: [MeshInstance(position: up)])
            case .nothing:
                break
            case .whiteCopy:
                fill(.white)
                drawMesh(box, instances: [MeshInstance(position: up)])
            case .tintedCopy:
                fill(.white)
                drawMesh(box, instances: [MeshInstance(position: up, color: red)])
            }
        }
    }
}
