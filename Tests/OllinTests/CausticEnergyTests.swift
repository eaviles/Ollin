@testable import Ollin
import COllinShaders
import Foundation
import Metal
import simd
import Testing

/// The caustic's energy, stage by stage. Each stage is read against a value the
/// chain's own arithmetic does not produce: what a glass surface passes by the
/// Fresnel equations, the shadow the same glass casts, the twin scene lit by a
/// mirror's virtual light, the uniform emission plan. Every frame here is read in
/// linear light before the present pass, so nothing brighter than white is clipped
/// and no dither is in the numbers.
///
/// What the stages found when they were first run (2026-10-07): the deposit was
/// right and everything after it was not. The splat shaded a physically based
/// receiver at pi times its light and counted the incidence cosine twice, a
/// half-float layer lost 4% of a flat caustic and capped a focused one at a power
/// of two, the exit interface read Schlick's curve at the inside angle, a texel
/// planned below one ray delivered that fraction of its light, and a point light's
/// photons carried their cone's light at the distance of the glass rather than of
/// the receiver. A clear glass ball's caustic came to 1.5 times the light its
/// shadow took (more with the cap lifted), and a lamp's ball to 0.35 of it.
@Suite(.serialized)
@MainActor
struct CausticEnergyTests {

    // MARK: Support

    private struct Linear {
        var rgb: [Double]
        var width: Int
        var height: Int
        func luma(_ p: Int) -> Double { (rgb[p * 3] + rgb[p * 3 + 1] + rgb[p * 3 + 2]) / 3 }
    }

    private struct Rendered {
        var frame: Linear
        /// The flux every deposited photon carries, mean of the channels, summed:
        /// what the trace handed to the splat.
        var deposited: Double
        var viewProjection: simd_float4x4
    }

    /// One exported frame read before the present pass, with the photon buffer the
    /// frame's trace filled.
    private func render(_ sketch: Sketch) throws -> Rendered {
        let renderer = try OllinApp.headlessRenderer(for: sketch)
        OllinApp.isRenderingHeadless = true
        defer { OllinApp.isRenderingHeadless = false }
        renderer.automaticQuality = .detail
        renderer.capturesLinearFrame = true
        _ = try OllinApp.renderImage(of: sketch, frame: 1, fps: 60, renderer: renderer)
        let linear = try #require(renderer.lastLinearFrame)
        let count = linear.width * linear.height
        let halves = linear.color.contents().bindMemory(to: Float16.self, capacity: count * 4)
        var rgb = [Double](repeating: 0, count: count * 3)
        for p in 0..<count {
            for c in 0..<3 { rgb[p * 3 + c] = Double(Float(halves[p * 4 + c])) }
        }
        var deposited = 0.0
        if let photons = renderer.causticsPhotons {
            deposited = try fluxTotal(photons, renderer.device, renderer.commandQueue)
        }
        let camera = try #require(sketch.drawer.camera3D)
        let aspect = Double(linear.width) / Double(linear.height)
        return Rendered(frame: Linear(rgb: rgb, width: linear.width, height: linear.height),
                        deposited: deposited,
                        viewProjection: camera.projectionMatrix(aspect: aspect) * camera.viewMatrix)
    }

    private func fluxTotal(_ photons: MTLBuffer, _ device: MTLDevice,
                           _ queue: MTLCommandQueue) throws -> Double {
        let shared = try #require(device.makeBuffer(length: photons.length, options: .storageModeShared))
        let cb = try #require(queue.makeCommandBuffer())
        let blit = try #require(cb.makeBlitCommandEncoder())
        blit.copy(from: photons, sourceOffset: 0, to: shared, destinationOffset: 0, size: photons.length)
        blit.endEncoding()
        cb.commit()
        cb.waitUntilCompleted()
        let n = photons.length / MemoryLayout<OllinPhoton>.stride
        let records = shared.contents().bindMemory(to: OllinPhoton.self, capacity: n)
        var total = 0.0
        for i in 0..<n {
            let p = records[i].power
            total += Double(p.x + p.y + p.z) / 3
        }
        return total
    }

    /// The pixels of a frame outside an object's silhouette: the mask render draws
    /// the object alone, white under ambient light, and the silhouette is dilated
    /// three pixels for its anti-aliased rim.
    private func outside(_ mask: Linear) -> [Int] {
        let w = mask.width, h = mask.height
        var inside = [Bool](repeating: false, count: w * h)
        for y in 0..<h {
            for x in 0..<w where mask.rgb[(y * w + x) * 3 + 1] > 0.05 {
                for dy in -3...3 {
                    for dx in -3...3 {
                        let nx = x + dx, ny = y + dy
                        if nx >= 0, ny >= 0, nx < w, ny < h { inside[ny * w + nx] = true }
                    }
                }
            }
        }
        return (0..<(w * h)).filter { !inside[$0] }
    }

    /// Where each pixel's center meets the floor plane y = 0, nil off it.
    private func floorPoints(_ r: Rendered) -> [SIMD3<Double>?] {
        let inverse = simd_inverse(r.viewProjection)
        let w = r.frame.width, h = r.frame.height
        var out = [SIMD3<Double>?](repeating: nil, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                let nx = (Double(x) + 0.5) / Double(w) * 2 - 1
                let ny = 1 - (Double(y) + 0.5) / Double(h) * 2
                let a = inverse * SIMD4<Float>(Float(nx), Float(ny), 0, 1)
                let b = inverse * SIMD4<Float>(Float(nx), Float(ny), 1, 1)
                let p0 = SIMD3<Double>(Double(a.x / a.w), Double(a.y / a.w), Double(a.z / a.w))
                let p1 = SIMD3<Double>(Double(b.x / b.w), Double(b.y / b.w), Double(b.z / b.w))
                let d = p1 - p0
                guard abs(d.y) > 1e-9 else { continue }
                let t = -p0.y / d.y
                if t > 0 { out[y * w + x] = p0 + d * t }
            }
        }
        return out
    }

    private func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        return sorted.isEmpty ? .nan : sorted[sorted.count / 2]
    }

    /// What a flat glass slab passes head on, in at one face and out at the other:
    /// the Fresnel equations give 0.04 reflected at each face of index 1.5 at normal
    /// incidence, and at the 29 degrees of the tilted light the same to three
    /// places, so the slab passes 0.96 squared.
    private static let slabTransmission = 0.96 * 0.96

    // MARK: The deposit

    /// The photons a slab sends on carry the light falling on it times what its two
    /// faces pass: the emission cell's cross-section, the Fresnel weight at each
    /// interface, and nothing counted twice.
    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func aSlabDepositsTheLightItPasses() throws {
        let lit = try render(CausticSlab.make(tilt: 0, kind: .caustics))
        let expected = 1.5 * CausticSlab.side * CausticSlab.side * Self.slabTransmission
        #expect(abs(lit.deposited / expected - 1) < 0.005,
                "the slab's photons carry \(lit.deposited) where it passes \(expected)")
    }

    /// The photons a clear glass ball sends on carry the beam it intercepts times
    /// what its two surfaces pass, averaged over its disc. The full Fresnel
    /// equations give 0.836 for index 1.5; Schlick's curve read at the outer angle
    /// at both faces, 0.848; read at the inside angle on the way out, 0.878, which
    /// is what the trace did (0.862 measured, the tessellated sphere a little
    /// smaller than its radius). The band leaves the polygon and the footprint
    /// cull their percent.
    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func aBallDepositsTheBeamItsGlassPasses() throws {
        let lit = try render(CausticBall.make(.caustics))
        let beam = 1.5 * Double.pi
        let share = lit.deposited / beam
        #expect(share > 0.80 && share < 0.855,
                "the ball's photons carry \(share) of the beam it intercepts")
    }

    // MARK: The splat and the shading

    /// Where nothing focuses, the caustic adds back exactly the light the glass took
    /// from the direct path, times what the glass passes: a slab's caustic, read
    /// pixel by pixel against the shadow the same slab casts, is the slab's
    /// transmission. Run on both receiver models and with the light tilted, so a
    /// receiver shaded at pi times its light, an incidence cosine counted twice, or
    /// a layer that rounds its sums away each moves the ratio off.
    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing),
          arguments: [(0.0, true), (0.5, true), (0.0, false), (0.5, false)])
    func aSlabReturnsWhatItsShadowTook(tilt: Double, physicallyBased: Bool) throws {
        let bare = try render(CausticSlab.make(tilt: tilt, kind: .none, physicallyBased: physicallyBased))
        let shadowed = try render(CausticSlab.make(tilt: tilt, kind: .shadow, physicallyBased: physicallyBased))
        let lit = try render(CausticSlab.make(tilt: tilt, kind: .caustics, physicallyBased: physicallyBased))
        let mask = try render(CausticSlab.make(tilt: tilt, kind: .mask, physicallyBased: physicallyBased))
        let points = floorPoints(bare)
        var ratios: [Double] = []
        for p in outside(mask.frame) {
            // The middle of the shadow, away from the slab's edges and the sideways
            // step the tilted light takes through it.
            guard let q = points[p], abs(q.x) < 0.9, abs(q.z) < 0.9 else { continue }
            let removed = bare.frame.luma(p) - shadowed.frame.luma(p)
            guard removed > 0.01 else { continue }
            ratios.append((lit.frame.luma(p) - shadowed.frame.luma(p)) / removed)
        }
        #expect(ratios.count > 200, "the shadow's middle was not in view: \(ratios.count) pixels")
        let ratio = median(ratios)
        #expect(abs(ratio - Self.slabTransmission) < 0.01,
                "the caustic gave back \(ratio) of what the shadow took, where the slab passes \(Self.slabTransmission)")
    }

    /// A mirror's caustic is the light of its virtual source: a white mirror plate
    /// turning a light onto a wall lights the wall as the same light placed at its
    /// mirror image would, pixel by pixel. For a point light that holds only when a
    /// photon carries its cone's light at the length of the path it took, since a
    /// light with no falloff lights every distance alike and the virtual source sits
    /// at the unfolded distance.
    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing), arguments: [false, true])
    func aMirrorThrowsTheLightOfItsVirtualSource(point: Bool) throws {
        let lit = try render(CausticMirror.make(point: point, kind: .caustics))
        let shadowed = try render(CausticMirror.make(point: point, kind: .shadow))
        let twin = try render(CausticMirror.make(point: point, kind: .virtualLight))
        let mask = try render(CausticMirror.make(point: point, kind: .mask))
        var ratios: [Double] = []
        for p in outside(mask.frame) {
            let added = lit.frame.luma(p) - shadowed.frame.luma(p)
            let direct = twin.frame.luma(p)
            guard direct > 0.02, added > 0.02 else { continue }
            ratios.append(added / direct)
        }
        #expect(ratios.count > 500, "the thrown patch was not in view: \(ratios.count) pixels")
        let ratio = median(ratios)
        #expect(abs(ratio - 1) < 0.03,
                "the mirror threw \(ratio) of its virtual light's own")
    }

    // MARK: The live plan

    /// The live emission plan delivers the uniform plan's light in every frame, not
    /// only once it settles: a texel planned below one ray emits on that share of
    /// frames, so its photon carries the inverse share. Without it the first
    /// adaptive frame fell 17% short and the settling frames after it 5 to 14%.
    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func everyLiveFrameDeliversTheUniformPlansLight() throws {
        let sketch = CausticBall.make(.caustics)
        let size = sketch.canvasSize
        let width = size.width, height = size.height
        let device = try #require(MTLCreateSystemDefaultDevice())
        let renderer = try MetalRenderer(device: device,
                                         pixelFormat: sketch.colorOutput.drawablePixelFormat,
                                         sampleCount: ollinPreferredSampleCount(device),
                                         encoding: sketch.colorOutput.presentEncoding)
        sketch.setCanvasSize(width: Double(width), height: Double(height))
        sketch.setup()
        var fluxes: [Double] = []
        for k in 0..<16 {
            sketch.advance(time: Double(k) / 60, deltaTime: 1.0 / 60, frameRate: 60)
            sketch.performDraw()
            let drawer = sketch.drawer
            renderer.beginStatefulEncode(drawer)
            let cb = try #require(renderer.commandQueue.makeCommandBuffer())
            let meshBuffer = renderer.exportMeshBuffer(for: renderer.tracedMeshVertexCount(drawer))
            if let meshBuffer, !drawer.meshVertices.isEmpty {
                drawer.meshVertices.withUnsafeBytes { raw in
                    meshBuffer.contents().copyMemory(from: raw.baseAddress!, byteCount: raw.count)
                }
            }
            let shadow = renderer.encodeShadowPass(drawer, into: cb, meshBuffer: meshBuffer)
            _ = try #require(renderer.encodeCausticsPass(
                drawer, into: cb, meshBuffer: meshBuffer,
                causticAccel: shadow.causticAccel,
                causticGeoOffsets: shadow.causticGeoOffsets,
                causticGeoMats: shadow.causticGeoMats,
                width: width, height: height,
                supersample: false, pooled: false))
            cb.commit()
            cb.waitUntilCompleted()
            fluxes.append(try fluxTotal(try #require(renderer.causticsPhotons), device,
                                        renderer.commandQueue))
        }
        // Frame 0 has no feedback yet, so it plans uniformly: the reference.
        let uniform = fluxes[0]
        #expect(uniform > 1, "the uniform frame deposited nothing to speak of: \(uniform)")
        let worst = fluxes.dropFirst().map { abs($0 / uniform - 1) }.max() ?? 0
        #expect(worst < 0.02,
                "a live frame strayed \(worst) from the uniform plan's light: \(fluxes)")
    }
}

/// A clear glass ball of radius 1 hovering over a matte floor, lit from straight
/// above, seen from low on one side: the lighting invariant probe's scene.
private final class CausticBall: Sketch {
    enum Kind { case caustics }
    var kind = Kind.caustics

    static func make(_ kind: Kind) -> CausticBall {
        let s = CausticBall()
        s.kind = kind
        return s
    }

    override var canvasSize: CanvasSize { .square(192) }

    override func draw() {
        background(.black)
        perspective(eye: Vector3(0, 3.4, 8.3), target: Vector3(0, 0.7, 0),
                    fieldOfView: .pi / 3.6, near: 1, far: 40)
        toneMap(.reinhard)
        directionalLight(.white, direction: Vector3(-0.05, -1, 0.02), intensity: 1.5)
        castShadows()
        caustics()
        withState {
            material(.glass(thickness: 2.0))
            fill(.white)
            translate(0, 1.6, 0)
            drawSphere(radius: 1.0)
        }
        withState {
            material(.dielectric(roughness: 0.85))
            fill(Color(white: 0.55))
            translate(0, -0.5, 0)
            drawBox(width: 24, height: 1.0, depth: 20)
        }
    }
}

/// A flat glass slab high over a matte floor, seen from below its height so the
/// floor under it is in plain view. The slab moves with the light's tilt so its
/// shadow stays centered on the floor's origin.
private final class CausticSlab: Sketch {
    enum Kind { case none, shadow, caustics, mask }
    static let side = 3.4
    static let height = 2.4
    var tilt = 0.0
    var kind = Kind.caustics
    var physicallyBased = true

    static func make(tilt: Double, kind: Kind, physicallyBased: Bool = true) -> CausticSlab {
        let s = CausticSlab()
        s.tilt = tilt
        s.kind = kind
        s.physicallyBased = physicallyBased
        return s
    }

    override var canvasSize: CanvasSize { .square(192) }

    override func draw() {
        background(.black)
        perspective(eye: Vector3(0, 1.3, 7.5), target: Vector3(0, 0, 0),
                    fieldOfView: .pi / 3.6, near: 0.5, far: 40)
        toneMap(.reinhard)
        if kind == .mask {
            noLights()
            ambientLight(.white)
        } else {
            directionalLight(.white, direction: Vector3(-sin(tilt), -cos(tilt), 0), intensity: 1.5)
            castShadows()
        }
        if kind == .caustics { caustics() }
        if kind != .none {
            withState {
                material(kind == .mask ? .dielectric(roughness: 1) : .glass(thickness: 0.25))
                fill(.white)
                translate(tan(tilt) * Self.height, Self.height, 0)
                drawBox(width: Self.side, height: 0.25, depth: Self.side)
            }
        }
        withState {
            if physicallyBased { material(.dielectric(roughness: 0.85)) }
            fill(kind == .mask ? .black : Color(white: 0.55))
            translate(0, -0.5, 0)
            drawBox(width: 30, height: 1.0, depth: 30)
        }
    }
}

/// A white mirror plate turned 45 degrees under a light falling straight down,
/// throwing it onto a wall; the twin has no mirror and the light at the mirror's
/// image (a directional light turned toward the wall, a point light reflected
/// across the plate's plane, from (0, 5, 0) to (0, 2, 3)).
private final class CausticMirror: Sketch {
    enum Kind { case caustics, shadow, virtualLight, mask }
    var point = false
    var kind = Kind.caustics

    static func make(point: Bool, kind: Kind) -> CausticMirror {
        let s = CausticMirror()
        s.point = point
        s.kind = kind
        return s
    }

    override var canvasSize: CanvasSize { .square(192) }

    override func draw() {
        background(.black)
        perspective(eye: Vector3(4.5, 2, 4), target: Vector3(0, 2, -3),
                    fieldOfView: .pi / 3.6, near: 0.5, far: 40)
        toneMap(.reinhard)
        switch kind {
        case .mask:
            noLights()
            ambientLight(.white)
        case .virtualLight:
            if point {
                pointLight(.white, at: Vector3(0, 2, 3), intensity: 1.5)
            } else {
                directionalLight(.white, direction: Vector3(0, 0, -1), intensity: 1.5)
            }
        case .caustics, .shadow:
            if point {
                pointLight(.white, at: Vector3(0, 5, 0), intensity: 1.5)
            } else {
                directionalLight(.white, direction: Vector3(0, -1, 0), intensity: 1.5)
            }
            castShadows()
        }
        if kind == .caustics { caustics() }
        if kind != .virtualLight {
            withState {
                material(kind == .mask ? .dielectric(roughness: 1) : .polishedMetal)
                fill(.white)
                translate(0, 2, 0)
                rotateX(-.pi / 4)
                drawBox(width: 2, height: 0.04, depth: 2)
            }
        }
        withState {
            material(.dielectric(roughness: 0.85))
            fill(kind == .mask ? .black : Color(white: 0.55))
            translate(0, 2, -3.5)
            drawBox(width: 12, height: 12, depth: 1)
        }
    }
}
