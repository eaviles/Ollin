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
        // 69 below it, so a layer that went missing or landed elsewhere could not pass.
        // The half-size layer keeps nearly all of that. What it costs is reflected
        // *detail*, the honest price of tracing a quarter as many rays, and this
        // reading is what says it costs nothing else.
        let full = try mirroredBoxMean(.plain, .detail)
        let half = try mirroredBoxMean(.plain, .performance)
        let empty = try mirroredBoxMean(.nothing, .detail)
        #expect(full - empty > 20, "the control: full \(full), empty \(empty)")
        #expect(half - empty > 0.9 * (full - empty),
                "expected the half-size layer to keep the mirror image, not dim it: full \(full), half \(half), empty \(empty)")
    }

    /// The upsample guide. Two mirror faces of one box meet at a vertical edge down the
    /// middle of the frame, each facing its own colored panel, so a texel that straddles
    /// them holds two different reflections. Read flat, a half-size layer hands each face
    /// a share of the other one's color for a pixel or two along the joint; guided by the
    /// reflection G-buffer's own normal, each face keeps its own.
    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func aMirrorEdgeKeepsItsOwnReflectionAtHalfSize() throws {
        // Blue minus red down the middle rows, column by column: strongly negative on the
        // left face (which reflects the red panel), strongly positive on the right one.
        func profile(_ quality: RenderQuality) throws -> [Double] {
            let scene = MirrorEdgeProbe()
            let image = try #require(OllinApp.image(of: scene, frame: 1, quality: quality))
            let w = image.width, h = image.height
            var data = [UInt8](repeating: 0, count: w * h * 4)
            let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                                bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return (0..<w).map { x in
                var sum = 0, count = 0
                for y in (h * 42 / 100)..<(h * 58 / 100) {
                    let i = (y * w + x) * 4
                    sum += Int(data[i + 2]) - Int(data[i]); count += 1
                }
                return Double(sum) / Double(count)
            }
        }
        let full = try profile(.detail)
        let half = try profile(.performance)
        // The joint is where the profile climbs fastest, and both tiers draw the box in
        // the same place, so the full-size picture locates it for the pair.
        func climb(_ column: Int) -> Double { full[column + 1] - full[column] }
        let joint = (1..<(full.count - 1)).max(by: { climb($0) < climb($1) }) ?? 0
        let left = joint - 2
        #expect(full[left] < -100, "the control: the left face reflects the red panel, \(full[left])")
        #expect(full[joint + 3] > 50, "the control: the right face reflects the blue one, \(full[joint + 3])")
        // The two pixels the joint runs between, one on each face. They are the whole
        // reading: a flat blend of the coarse layer's four taps hands each of them a
        // share of the other face's color, which measures here as about 50 and 100.
        for x in joint...(joint + 1) {
            #expect(abs(half[x] - full[x]) < 20,
                    "expected each face to keep its own reflection at the joint, column \(x): full \(full[x]), half \(half[x])")
        }
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

/// The upsample-guide scene: one mirror box turned a half-turn so two of its faces meet
/// at a vertical edge down the middle of the frame, with a red panel to the left of the
/// camera and a blue one to the right. Each face reflects one panel and not the other.
private final class MirrorEdgeProbe: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    private let box = Mesh.box(width: 2.4, height: 2.4, depth: 2.4)
    private let panel = Mesh.box(width: 9, height: 9, depth: 0.2)

    override func draw() {
        background(.black)
        camera(.orbiting(target: Vector3(0, 0, 0), radius: 8, azimuth: 0.785398, elevation: 0.0))
        environment(.night)
        rayTracedReflections()
        withState {
            fill(Color(white: 0.95))
            material(.metal(roughness: 0.04))
            drawMesh(box)
        }
        // Each face throws the eye ray back the way it came about its own normal, so a
        // panel that shows in one of them sits opposite the other. The red one lands
        // behind the camera, which also keeps it out of the picture.
        withState {
            material(.dielectric(roughness: 0.5))
            fill(Color(red: 1.0, green: 0.04, blue: 0.04))
            withState {
                translate(-8, 0, 8)
                drawMesh(panel)
            }
            fill(Color(red: 0.04, green: 0.04, blue: 1.0))
            withState {
                translate(8, 0, -8)
                drawMesh(panel)
            }
        }
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

/// Instanced copies inside the offline path-traced export (`--path-traced`).
///
/// A copy belongs to the traced scene the way the mesh it stands for does: it
/// throws a traced shadow, bounces light, and stands in a mirror. These probes read
/// the same mirror band the live suite above reads, so a copy missing from the
/// traced scene shows up as a floor that mirrors nothing, while the copy's own
/// raster body stays out of the band either way.
///
/// The sample counts are small on purpose: every reading here is a large signal
/// against an empty-scene control, so grain costs nothing and the suite stays quick.
@Suite(.serialized)
@MainActor
struct InstancedPathTracedTests {

    /// Red minus blue over the mirror band, rendered through the path-traced export.
    private func mirroredBoxMean(_ how: InstancedReflectionProbe.How,
                                 samples: Int = 24) throws -> Double {
        OllinApp.pathTracedExport = PathTracing(samplesPerPixel: samples, denoise: false)
        defer { OllinApp.pathTracedExport = nil }
        let image = try #require(OllinApp.image(of: InstancedReflectionProbe.make(how), frame: 1))
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

    /// Mean red over the box's own body, well inside its silhouette. A copy the
    /// traced layer does not carry has to keep rastering, or it leaves a hole.
    private func boxBodyRed(_ how: InstancedReflectionProbe.How,
                            samples: Int = 24) throws -> Double {
        OllinApp.pathTracedExport = PathTracing(samplesPerPixel: samples, denoise: false)
        defer { OllinApp.pathTracedExport = nil }
        let image = try #require(OllinApp.image(of: InstancedReflectionProbe.make(how), frame: 1))
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        var sum = 0, count = 0
        for y in (h * 35 / 100)..<(h * 41 / 100) {
            for x in (w * 44 / 100)..<(w * 56 / 100) {
                let i = (y * w + x) * 4
                sum += Int(data[i]); count += 1
            }
        }
        return Double(sum) / Double(count)
    }

    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func aPlainBoxShowsInTheTracedMirror() throws {
        // The control that gives the rest their teeth: through the traced export the
        // plain box reddens the band it mirrors in, and an empty scene does not.
        let there = try mirroredBoxMean(.plain)
        let gone = try mirroredBoxMean(.nothing)
        #expect(there - gone > 20,
                "expected a plain box to redden the traced mirror: with \(there), without \(gone)")
    }

    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func anInstancedCopyShowsInTheTracedMirror() throws {
        // The same box through the instanced call. This is the reading the export
        // could not make before: the copy is in the traced scene, so it mirrors.
        let plain = try mirroredBoxMean(.plain)
        let instanced = try mirroredBoxMean(.instanced)
        #expect(abs(plain - instanced) < 6,
                "expected a copy to mirror like the plain mesh it stands for: plain \(plain), instanced \(instanced)")
    }

    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func theGPUResidentFormsShowInTheTracedMirrorToo() throws {
        // The two forms whose placements the CPU never sees. Their instance
        // descriptors and hit records are written by a kernel, and the material slot
        // this export resolves a finish through rides the same record.
        let plain = try mirroredBoxMean(.plain)
        let gpu = try mirroredBoxMean(.gpuBuffer)
        let field = try mirroredBoxMean(.field)
        #expect(abs(plain - gpu) < 6,
                "expected a GPU-placed copy to mirror like the plain mesh: plain \(plain), gpu \(gpu)")
        #expect(abs(plain - field) < 8,
                "expected a field copy to mirror like the plain mesh: plain \(plain), field \(field)")
    }

    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func aFieldOverItsBudgetKeepsDrawingInTheExport() throws {
        // The budget's promise, and the trap this slice had to avoid: a field the
        // traced scene turned away must keep rastering over the traced layer. It is
        // out of the mirror, like the live path, but it is still in the picture.
        let budgeted = try mirroredBoxMean(.budgetedOutField)
        let empty = try mirroredBoxMean(.nothing)
        #expect(abs(budgeted - empty) < 3,
                "expected a budgeted-out field to leave the traced mirror alone: budgeted \(budgeted), empty \(empty)")
        let body = try boxBodyRed(.budgetedOutField)
        let nothing = try boxBodyRed(.nothing)
        #expect(body - nothing > 30,
                "expected a budgeted-out field to keep drawing its body: field \(body), empty \(nothing)")
    }
}

/// The material a copy wears in the path-traced export.
///
/// The export resolves a hit's finish through a per-geometry table, and every copy
/// of one base mesh shares a single geometry, so the geometry alone cannot tell two
/// instanced draws apart. Each run therefore carries its own slot in that table. A
/// slot that resolved wrongly would dress a copy in another draw's finish, which is
/// what this reads: two copies of one box in one frame, one glass and one opaque,
/// over a red wall. Glass shows the wall through it; the opaque one does not.
@Suite(.serialized)
@MainActor
struct InstancedPathTracedMaterialTests {

    /// Red minus green over one box's body: high where the red wall shows through,
    /// near zero on a white surface.
    private func bodies(_ how: InstancedMaterialProbe.How,
                        samples: Int = 32) throws -> (glass: Double, opaque: Double) {
        OllinApp.pathTracedExport = PathTracing(samplesPerPixel: samples, denoise: false)
        defer { OllinApp.pathTracedExport = nil }
        let image = try #require(OllinApp.image(of: InstancedMaterialProbe.make(how), frame: 1))
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        func mean(_ x0: Int, _ x1: Int) -> Double {
            var sum = 0, count = 0
            for y in (h * 45 / 100)..<(h * 55 / 100) {
                for x in (w * x0 / 100)..<(w * x1 / 100) {
                    let i = (y * w + x) * 4
                    sum += Int(data[i]) - Int(data[i + 1]); count += 1
                }
            }
            return Double(sum) / Double(count)
        }
        return (mean(28, 38), mean(62, 72))
    }

    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func twoPlainBoxesWearTheirOwnFinishes() throws {
        // The control: drawn on their own, the glass box shows the red wall and the
        // opaque one does not, so the reading separates the two finishes.
        let plain = try bodies(.plainPair)
        #expect(plain.glass - plain.opaque > 30,
                "the control: glass \(plain.glass), opaque \(plain.opaque)")
    }

    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func twoCopiesWearTheirOwnFinishesToo() throws {
        // The same pair through two instanced draws. One shared material slot, or a
        // slot pointing at the wall's own finish, would collapse this difference.
        let plain = try bodies(.plainPair)
        let copied = try bodies(.copiedPair)
        #expect(copied.glass - copied.opaque > 30,
                "expected each copy to wear its own finish: glass \(copied.glass), opaque \(copied.opaque)")
        #expect(abs(copied.glass - plain.glass) < 12,
                "expected a glass copy to read like the glass mesh it stands for: copy \(copied.glass), plain \(plain.glass)")
        #expect(abs(copied.opaque - plain.opaque) < 12,
                "expected an opaque copy to read like the opaque mesh it stands for: copy \(copied.opaque), plain \(plain.opaque)")
    }
}

/// Two boxes over a red wall, one glass and one opaque, drawn either on their own or
/// through two instanced calls. What the reading separates is the finish, which is
/// the part of a copy's surface the export resolves per run rather than per vertex.
private final class InstancedMaterialProbe: Sketch {
    enum How { case plainPair, copiedPair }
    var how: How = .plainPair

    static func make(_ how: How) -> InstancedMaterialProbe {
        let probe = InstancedMaterialProbe()
        probe.how = how
        return probe
    }

    override var canvasSize: CanvasSize { .square(256) }

    private let box = Mesh.box(width: 1.6, height: 1.6, depth: 1.6)

    override func draw() {
        background(.black)
        camera(Camera3D(eye: Vector3(0, 0, 6), target: .zero))
        ambientLight(Color(white: 0.35))
        directionalLight(Color(white: 0.8), direction: Vector3(-0.3, -0.4, -1))
        withState {
            // The wall, and the frame's one plain mesh: its finish is the first
            // entry of the table the copies index past.
            fill(Color(red: 1.0, green: 0.02, blue: 0.02))
            material(Material())
            translate(0, 0, -3)
            rotateX(Double.pi / 2)
            drawPlane(width: 24, depth: 24)
        }
        let left = Vector3(-1.2, 0, 0), right = Vector3(1.2, 0, 0)
        withState {
            fill(.white)
            material(.glass())
            switch how {
            case .plainPair: translate(left); drawMesh(box)
            case .copiedPair: drawMesh(box, instances: [MeshInstance(position: left)])
            }
        }
        withState {
            fill(.white)
            material(.dielectric(roughness: 0.6))
            switch how {
            case .plainPair: translate(right); drawMesh(box)
            case .copiedPair: drawMesh(box, instances: [MeshInstance(position: right)])
            }
        }
    }
}
