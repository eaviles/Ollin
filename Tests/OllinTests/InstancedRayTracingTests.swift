@testable import Ollin
import COllinShaders
import CoreGraphics
import Foundation
import simd
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
    func theGPUResidentFormsCastATracedPointShadowToo() throws {
        // A point caster traces rather than rendering its cube map here, so a copy the
        // traced scene never held would leave the floor patch as bright as an empty one.
        let plain = try shadowedFloorMean(.plain)
        let gpu = try shadowedFloorMean(.gpuBuffer)
        let field = try shadowedFloorMean(.field)
        #expect(abs(plain - gpu) < 4,
                "expected a GPU-placed copy to shade like the plain mesh: plain \(plain), gpu \(gpu)")
        #expect(abs(plain - field) < 4,
                "expected a field copy to shade like the plain mesh: plain \(plain), field \(field)")
    }

    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func aGPUResidentCopyShowsInTheMirrorFloorToo() throws {
        // The same box again, placed by a matrix that lives in a compute buffer. Only
        // the count of those copies is known on the CPU, so this reads whether the
        // kernel that writes their instance descriptors put them where they belong.
        let plain = try mirroredBoxMean(.plain)
        let gpu = try mirroredBoxMean(.gpuBuffer)
        #expect(abs(plain - gpu) < 4,
                "expected a GPU-placed copy to mirror like the plain mesh: plain \(plain), gpu \(gpu)")
    }

    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func aGPUResidentCopyCarriesItsOwnColorIntoTheMirror() throws {
        // The tint rides the same GPU-written hit record as the placement, so a copy
        // that mirrored in the base mesh's color would say the record never landed.
        let white = try mirroredBoxMean(.whiteCopy)
        let tinted = try mirroredBoxMean(.tintedGPUBuffer)
        #expect(tinted - white > 20,
                "expected a GPU-placed copy to mirror in its own color: white \(white), tinted \(tinted)")
    }

    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func aFieldCopyShowsInTheMirrorFloorToo() throws {
        // A retained field holds its base meshes and its copies itself, so this reads
        // whether the build appended those meshes to the traced vertex list and whether
        // the kernel placed the copies over them.
        let plain = try mirroredBoxMean(.plain)
        let field = try mirroredBoxMean(.field)
        #expect(abs(plain - field) < 6,
                "expected a field copy to mirror like the plain mesh: plain \(plain), field \(field)")
    }

    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func aFieldCopyCarriesItsOwnColorIntoTheMirror() throws {
        // The field's baked surface reaches the mirror: the same field untinted has to
        // read clearly cooler, or the tint never made it into the hit record.
        let white = try mirroredBoxMean(.whiteField)
        let tinted = try mirroredBoxMean(.field)
        #expect(tinted - white > 20,
                "expected a tinted field copy to mirror in its own color: white \(white), tinted \(tinted)")
    }

    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func aFieldOverItsTracedBudgetStaysOutOfTheMirror() throws {
        // The budget is what keeps a field of a few hundred thousand copies from
        // spending the whole frame in the traced scene. A closed budget has to read
        // like an empty floor, while the same field with the default budget does not.
        let budgeted = try mirroredBoxMean(.budgetedOutField)
        let empty = try mirroredBoxMean(.nothing)
        let included = try mirroredBoxMean(.field)
        #expect(abs(budgeted - empty) < 2,
                "expected a budgeted-out field to leave the mirror alone: budgeted \(budgeted), empty \(empty)")
        #expect(included - budgeted > 20,
                "the control: the same field inside its budget mirrors, included \(included), budgeted \(budgeted)")
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

/// The half-resolution reflection tier. `.performance` renders the deferred reflection
/// layer at half the drawable and the lit fragments read it scaled, so the picture has to
/// hold: the mirror image must land in the same place and keep its color, only coarser.
/// A tier that shifted or dropped the layer would read here as a mirrored band that lost
/// its subject, which is what the empty-scene control measures the distance to.
@Suite
@MainActor
struct ReflectionResolutionTierTests {

    private func mirroredBoxMean(_ how: InstancedReflectionProbe.How,
                                 _ quality: RenderQuality) throws -> Double {
        let scene = InstancedReflectionProbe.make(how)
        let image = try #require(OllinApp.image(of: scene, frame: 1, quality: quality))
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
    func theHalfSizeLayerStillPutsTheMirrorImageWhereItBelongs() throws {
        // The band reads the box's reflection either way, and the empty scene sits about
        // 68 below it, so a layer that went missing or landed elsewhere could not pass.
        // The half-size layer does read weaker, by about 15% of the signal, and that is
        // the documented cost of the tier rather than a fault: the layer carries its hit
        // coverage per pixel, so a coarser one smears that coverage at every silhouette
        // and each smeared pixel falls part of the way back to the environment.
        let full = try mirroredBoxMean(.plain, .detail)
        let half = try mirroredBoxMean(.plain, .performance)
        let empty = try mirroredBoxMean(.nothing, .detail)
        #expect(full - empty > 20, "the control: full \(full), empty \(empty)")
        #expect(half - empty > 40,
                "expected the half-size layer to still hold the mirror image: half \(half), empty \(empty)")
        #expect(full - half < 20,
                "expected the half-size layer to dim rather than drop the image: full \(full), half \(half)")
    }

    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func aCopyReachesTheHalfSizeLayerToo() throws {
        // The two features meet here: a copy is in the traced scene, and the layer that
        // traces it is half size. Neither may lose the other.
        let plain = try mirroredBoxMean(.plain, .performance)
        let instanced = try mirroredBoxMean(.instanced, .performance)
        #expect(abs(plain - instanced) < 4,
                "expected an instanced copy to mirror at the lower tier too: plain \(plain), instanced \(instanced)")
    }
}

/// The shadow probe scene: one box over a plain white floor under a single point light
/// standing above it, so the box's shadow lands in the measured patch.
private final class InstancedShadowProbe: Sketch {
    enum How { case plain, instanced, nothing, gpuBuffer, field }
    var how: How = .plain

    static func make(_ how: How) -> InstancedShadowProbe {
        let probe = InstancedShadowProbe()
        probe.how = how
        return probe
    }

    override var canvasSize: CanvasSize { .square(256) }

    private let box = Mesh.box(width: 1.6, height: 1.6, depth: 1.6)

    /// The same box placed by a matrix that lives on the GPU.
    private lazy var placements: ComputeBuffer<OllinMeshInstance> = {
        var one = OllinMeshInstance()
        one.model = MeshInstance(position: Vector3(0, 1.6, 0)).matrix
        one.color = SIMD4<Float>(1, 1, 1, 1)
        return ComputeBuffer([one])
    }()

    /// The same box held by a retained field.
    private lazy var field: MeshField = {
        let f = MeshField()
        f.place(box, at: [MeshInstance(position: Vector3(0, 1.6, 0))])
        return f
    }()

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
            case .gpuBuffer:
                drawMesh(box, instances: placements)
            case .field:
                drawMeshField(field)
            }
        }
    }
}

/// The probe scene: one red box over a near-mirror metal floor under a bundled
/// environment, its reflection the thing measured. `How` draws the box through the
/// plain call, through the instanced call at the same place, or not at all.
private final class InstancedReflectionProbe: Sketch {
    enum How {
        case plain, instanced, nothing, whiteCopy, tintedCopy, gpuBuffer, tintedGPUBuffer
        case field, whiteField, budgetedOutField
    }
    var how: How = .plain

    static func make(_ how: How) -> InstancedReflectionProbe {
        let probe = InstancedReflectionProbe()
        probe.how = how
        return probe
    }

    override var canvasSize: CanvasSize { .square(256) }

    private let box = Mesh.box(width: 1.6, height: 1.6, depth: 1.6)

    /// The GPU-resident placement of the same copy, seeded rather than written by
    /// a kernel: where the matrices come from does not change what the traced
    /// scene has to do with them, and a seeded buffer keeps the probe readable.
    private lazy var placements: ComputeBuffer<OllinMeshInstance> = {
        var one = OllinMeshInstance()
        one.model = MeshInstance(position: Vector3(0, 1.5, 0)).matrix
        one.color = SIMD4<Float>(1, 1, 1, 1)
        return ComputeBuffer([one])
    }()

    /// The same copy again, this time held by a retained field. A field bakes its
    /// surface color when a mesh is placed, so the red arrives as the copy's own
    /// tint rather than through the draw-time `fill`.
    private lazy var field: MeshField = {
        let f = MeshField()
        f.place(box, at: [MeshInstance(position: Vector3(0, 1.5, 0),
                                       color: Color(red: 1.0, green: 0.05, blue: 0.05))])
        return f
    }()

    /// The same tinted field with its traced budget closed, so its copies stay
    /// out of the traced passes while still drawing.
    private lazy var budgetedField: MeshField = {
        let f = MeshField()
        f.tracedCopyBudget = 0
        f.place(box, at: [MeshInstance(position: Vector3(0, 1.5, 0),
                                       color: Color(red: 1.0, green: 0.05, blue: 0.05))])
        return f
    }()

    /// The untinted field, the control the tinted one is read against.
    private lazy var plainField: MeshField = {
        let f = MeshField()
        f.place(box, at: [MeshInstance(position: Vector3(0, 1.5, 0))])
        return f
    }()

    /// The same placement wearing a per-copy tint.
    private lazy var tintedPlacements: ComputeBuffer<OllinMeshInstance> = {
        var one = OllinMeshInstance()
        one.model = MeshInstance(position: Vector3(0, 1.5, 0)).matrix
        one.color = SIMD4<Float>(1, 0.05, 0.05, 1)
        return ComputeBuffer([one])
    }()

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
            case .gpuBuffer:
                fill(red)
                drawMesh(box, instances: placements)
            case .tintedGPUBuffer:
                fill(.white)
                drawMesh(box, instances: tintedPlacements)
            case .field:
                drawMeshField(field)
            case .whiteField:
                drawMeshField(plainField)
            case .budgetedOutField:
                drawMeshField(budgetedField)
            }
        }
    }
}
