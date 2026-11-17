@testable import Ollin
import COllinShaders
import CoreGraphics
import Foundation
import Metal
import Testing
import simd

/// A field of many parts is written with skips: ahead of a combine's second operand,
/// an instruction that steps the walk past the operand and the combine where the point
/// is so far from the operand's box that the combine would hand back its first operand
/// untouched. The claim these tests hold is that the field is the same field: the same
/// distance and the same color, bit for bit, at every point, with the skips and without
/// them. What changes is how much of the program a march step reads.
@Suite
struct FieldSkipTests {
    /// A seeded source, so the fields and the points are the same on every run.
    struct Dice {
        var state: UInt64
        mutating func next() -> Float {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            z ^= z >> 31
            return Float(z >> 40) / Float(1 << 24)
        }
        mutating func signed(_ extent: Float) -> Double { Double((next() * 2 - 1) * extent) }
        mutating func point(_ extent: Float) -> Vector3 { Vector3(signed(extent), signed(extent), signed(extent)) }
    }

    /// Short capsules scattered through a cube and joined one after another by a
    /// smooth union: the shape a loop in a sketch builds.
    static func capsules(_ count: Int, seed: UInt64, extent: Float = 3, melt: Double = 0.12) -> SDF3D {
        var dice = Dice(state: seed)
        func capsule() -> SDF3D {
            let a = dice.point(extent)
            let b = a + dice.point(0.6)
            return SDF3D.line(from: a, to: b, radius: 0.12 + Double(dice.next()) * 0.1)
        }
        var field = capsule()
        for _ in 1 ..< count { field = field.smoothUnion(capsule(), k: melt) }
        return field
    }

    /// The same capsules laid along a path, so neighbors in the chain are neighbors
    /// in space and a run of them fits in a small box.
    static func strand(_ count: Int, seed: UInt64) -> SDF3D {
        var dice = Dice(state: seed)
        func point(_ i: Int) -> Vector3 {
            let t = Double(i) / Double(count)
            return Vector3(cos(t * 9) * (1 + 2 * t), t * 6 - 3, sin(t * 9) * (1 + 2 * t))
        }
        var field = SDF3D.line(from: point(0), to: point(1), radius: 0.15)
        for i in 1 ..< count {
            field = field.smoothUnion(SDF3D.line(from: point(i), to: point(i + 1),
                                                 radius: 0.1 + Double(dice.next()) * 0.08), k: 0.1)
        }
        return field
    }

    /// One part under every combine a skip can stand ahead of, and under the ones it
    /// cannot, around a body they all touch or miss by turns.
    static func everyCombine(seed: UInt64, rounds: Int = 3) -> SDF3D {
        var dice = Dice(state: seed)
        func part() -> SDF3D {
            let size = 0.25 + Double(dice.next()) * 0.3
            let shape: SDF3D
            switch Int(dice.next() * 5) {
            case 0:  shape = .sphere(radius: size)
            case 1:  shape = .box(size: size * 1.4)
            case 2:  shape = .torus(radius: size, tube: size * 0.3)
            case 3:  shape = .capsule(radius: size * 0.5, height: size * 2)
            default: shape = .roundBox(size: size * 1.4, radius: size * 0.2)
            }
            return shape.at(dice.point(2.2))
        }
        var field = SDF3D.sphere(radius: 1.1)
        for round in 0 ..< rounds {
            field = field.union(part())
            field = field.smoothUnion(part(), k: 0.3)
            field = field.subtract(part())
            field = field.smoothSubtract(part(), k: 0.2)
            field = field.chamferUnion(part(), radius: 0.15)
            field = field.chamferSubtract(part(), radius: 0.15)
            field = field.stairsUnion(part(), radius: 0.2, steps: 3)
            field = field.stairsSubtract(part(), radius: 0.2, steps: 3)
            field = field.columnsUnion(part(), radius: 0.2, count: 3)
            field = field.columnsSubtract(part(), radius: 0.2, count: 3)
            field = field.engrave(part(), depth: 0.08)
            field = field.groove(part(), depth: 0.1, width: 0.12)
            field = field.tongue(part(), height: 0.1, width: 0.12)
            if round == 1 {
                // The combines no skip stands ahead of, with chains on both sides.
                field = field.intersect(SDF3D.box(size: 5.5))
                field = field.pipe(part(), radius: 0.05).union(field)
            }
        }
        return field
    }

    /// Parts under every transform and modifier, and chains inside chains.
    static func everyScope(seed: UInt64, light: Bool = false) -> SDF3D {
        var dice = Dice(state: seed)
        func knot() -> SDF3D {
            let pair = SDF3D.sphere(radius: 0.3).smoothUnion(SDF3D.box(size: 0.35).at(0.3, 0.1, 0), k: 0.1)
            return light ? pair : pair.union(SDF3D.capsule(radius: 0.1, height: 0.7).at(-0.2, 0.2, 0.1))
        }
        var field = SDF3D.roundBox(size: 1.2, radius: 0.2)
        let scoped: [SDF3D] = [
            knot().rotated(0.7, axis: Vector3(0.3, 1, 0.2)),
            knot().scaled(1.6),
            knot().scaled(x: 1.5, y: 0.7, z: 1.1),
            knot().stretched(x: 0.3, y: 0, z: 0.2),
            knot().at(0.6, 0, 0).mirrored(x: true, y: false, z: true),
            knot().repeated(spacing: Vector3(1.1, 0, 0), count: 1),
            knot().at(0.9, 0, 0).repeatedRadially(count: 5),
            knot().twisted(0.8),
            knot().bent(0.5),
            knot().rounded(0.05),
            knot().onion(0.04),
            knot().displaced(amplitude: 0.03, frequency: 9),
            SDF3D.ellipsoid(radiusX: 0.5, radiusY: 0.2, radiusZ: 0.3),
        ]
        for (i, part) in scoped.enumerated() {
            let placed = part.at(dice.point(2.6))
            field = i % 3 == 2 ? field.union(placed) : field.smoothUnion(placed, k: 0.15)
        }
        return light ? field : field.smoothUnion(capsules(12, seed: seed &+ 7, extent: 2.5), k: 0.1)
    }

    /// A body that its own blend or modifier grows past the box of its parts, and a
    /// small sphere beside the swell: at points between them the body is nearer than
    /// the box of its parts says, and nearer than the sphere. A skip that measured to
    /// the parts' box alone would step past the body there.
    static func swollen(_ kind: Int) -> SDF3D {
        let twin = SDF3D.sphere(radius: 0.5).at(0.1, 0, 0)
        switch kind {
        case 0:   // a smooth union of two overlapping spheres swells by a quarter of its blend
            return SDF3D.sphere(radius: 0.3).at(0, 2.05, 0)
                .union(SDF3D.sphere(radius: 0.5).smoothUnion(twin, k: 1.0))
        case 1:   // a rounded box grows by its rounding
            return SDF3D.sphere(radius: 0.3).at(0, 2.1, 0)
                .union(SDF3D.box(size: 0.8).rounded(0.3))
        default:  // a chamfered union swells by up to 0.71 of its size
            return SDF3D.sphere(radius: 0.3).at(0.05, 2.25, 0)
                .union(SDF3D.sphere(radius: 0.5).chamferUnion(twin, radius: 0.8))
        }
    }

    static let fieldCount = 8
    static func field(_ index: Int) -> (name: String, field: SDF3D) {
        switch index {
        case 5:  return ("a smooth blend that swells past its parts", swollen(0))
        case 6:  return ("a rounded box beside a probe", swollen(1))
        case 7:  return ("a chamfered blend that swells past its parts", swollen(2))
        case 0:  return ("64 scattered capsules", capsules(64, seed: 11))
        case 1:  return ("126 scattered capsules", capsules(126, seed: 12))
        case 2:  return ("a strand of 90 capsules", strand(90, seed: 13))
        case 3:  return ("every combine", everyCombine(seed: 14))
        default: return ("every scope", everyScope(seed: 15))
        }
    }

    static func programs(_ field: SDF3D) -> (skipping: [SDFNode3D], plain: [SDFNode3D],
                                             skipBounds: SDF3D.FlattenResult, plainBounds: SDF3D.FlattenResult) {
        var skipping: [SDFNode3D] = [], plain: [SDFNode3D] = []
        let a = field.flatten(defaultFill: .white, skips: true, into: &skipping)
        let b = field.flatten(defaultFill: .white, into: &plain)
        return (skipping, plain, a, b)
    }

    static func bytes(_ nodes: [SDFNode3D]) -> [UInt8] { nodes.withUnsafeBytes { Array($0) } }

    /// The points a field is read at: through its box and a margin around it, and
    /// along rays into it, which is where a march reads.
    static func points(in bounds: SDF3D.FlattenResult, count: Int, seed: UInt64) -> [SIMD3<Float>] {
        var dice = Dice(state: seed)
        let center = (bounds.lo + bounds.hi) / 2, half = (bounds.hi - bounds.lo) / 2 * 1.4
        return (0 ..< count).map { _ in
            center + half * SIMD3(dice.next() * 2 - 1, dice.next() * 2 - 1, dice.next() * 2 - 1)
        }
    }

    @Test(arguments: 0 ..< fieldCount)
    func aSkippedFieldIsTheSameFieldAtEveryPoint(_ index: Int) throws {
        let (name, field) = Self.field(index)
        let (skipping, plain, bounds, _) = Self.programs(field)
        #expect(skipping.contains { $0.kind == 9 }, "\(name): the program was written with no skip")
        var skipped = FieldTwin(skipping), whole = FieldTwin(plain)
        var differing = 0
        for p in Self.points(in: bounds, count: 6_000, seed: UInt64(100 + index)) {
            let a = try skipped.value(at: p), b = try whole.value(at: p)
            if a.distance.bitPattern != b.distance.bitPattern || a.color != b.color { differing += 1 }
        }
        #expect(differing == 0, "\(name): \(differing) of 6000 points read a different distance or color with the skips")
        // The fields of many parts are also where a skip pays: fewer instructions read.
        // (The three single bodies beside a probe are there for the points between.)
        if index < 5 {
            #expect(skipped.reads < whole.reads,
                    "\(name): no skip was taken (\(skipped.reads) instructions read against \(whole.reads))")
        }
    }

    @Test(arguments: 0 ..< fieldCount)
    func takingTheSkipsOutLeavesTheProgramItWasWrittenFrom(_ index: Int) {
        let (name, field) = Self.field(index)
        let (skipping, plain, skipBounds, plainBounds) = Self.programs(field)
        #expect(Self.bytes(SDF3D.strippingSkips(skipping)) == Self.bytes(plain),
                "\(name): the program without its skips is not the program flattened without them")
        #expect(skipBounds.lo == plainBounds.lo && skipBounds.hi == plainBounds.hi,
                "\(name): the bounds moved with the skips")
        #expect(skipBounds.valueDepth == plainBounds.valueDepth && skipBounds.pointDepth == plainBounds.pointDepth)
    }

    /// A voxelized scope's end counts the instructions back to its start, and the walk
    /// steps back by that count to read the child again. The count takes in the skips
    /// written inside the scope, and is the plain one again once they are taken out.
    @Test
    func aVoxelizedScopeKeepsItsCountThroughTheSkips() throws {
        let field = Self.capsules(20, seed: 8).voxelized(size: 0.2)
        let (skipping, plain, _, _) = Self.programs(field)
        let end = try #require(skipping.last)
        #expect(skipping.first?.kind == 5 && end.kind == 6)
        #expect(Int(end.extra) == skipping.count - 1, "the scope's end points \(end.extra) back in a program of \(skipping.count)")
        #expect(skipping.count > plain.count)
        #expect(Self.bytes(SDF3D.strippingSkips(skipping)) == Self.bytes(plain))
    }

    /// The row this slice was planned on: a field of separate parts costs what is
    /// near the ray. Sixty-four capsules are 127 instructions; a march step of the
    /// program with skips reads a fraction of them.
    @Test
    func aFieldOfSeparatePartsReadsAFractionOfItsInstructionsAStep() throws {
        for (name, field, most) in [("scattered", Self.capsules(64, seed: 11), 0.66),
                                    ("a strand", Self.strand(64, seed: 13), 0.72)] {
            let (skipping, plain, bounds, _) = Self.programs(field)
            var skipped = FieldTwin(skipping), whole = FieldTwin(plain)
            for p in Self.points(in: bounds, count: 4_000, seed: 21) {
                _ = try skipped.value(at: p)
                _ = try whole.value(at: p)
            }
            let share = Double(skipped.reads) / Double(whole.reads)
            print("Ollin: \(name), 64 capsules: \(plain.count) instructions, \(skipping.count) with skips,"
                  + String(format: " %.1f read a step (%.0f%% of the program)",
                           Double(skipped.reads) / Double(skipped.walks), share * 100))
            #expect(share < most, "\(name): a step read \(Int(share * 100))% of the program")
        }
    }

    @Test
    @MainActor
    func aFieldOfAFewPartsIsWrittenAsItAlwaysWas() throws {
        final class Blob: Sketch {
            var parts = 3
            override func draw() {
                camera(.perspective(eye: Vector3(0, 0, 6), target: .zero, fieldOfView: .pi / 4))
                drawSDF3D(FieldSkipTests.capsules(parts, seed: 5))
            }
        }
        let small = Blob()
        try small.runSetup()
        small.advance(time: 0, deltaTime: 1.0 / 60, frameRate: 60)
        small.performDraw()
        #expect(!small.drawer.sdf3DNodes.contains { $0.kind == 9 }, "a field of three parts was written with skips")

        // The limit is on the field's own instructions: 126 capsules are 251 of them,
        // and the program that carries their skips is longer than the limit and drawn.
        let heavy = Blob()
        heavy.parts = 126
        try heavy.runSetup()
        heavy.advance(time: 0, deltaTime: 1.0 / 60, frameRate: 60)
        heavy.performDraw()
        let group = try #require(heavy.drawer.sdf3DGroups.first, "the 251-instruction field was not drawn")
        #expect(Int(group.nodeCount) > SDF3D.maxNodes, "the heavy field carries \(group.nodeCount) instructions")
        #expect(SDF3D.strippingSkips(heavy.drawer.sdf3DNodes).count == 251)

        let over = Blob()
        over.parts = 129
        try over.runSetup()
        over.advance(time: 0, deltaTime: 1.0 / 60, frameRate: 60)
        over.performDraw()
        #expect(over.drawer.sdf3DGroups.isEmpty, "a field of 257 instructions was drawn past the limit")
    }
}

// MARK: - The same pixels

/// The twin proves the arithmetic; these prove the fragment. Each scene is drawn
/// twice on one renderer, its fields written with skips and without, and the two
/// pictures are compared byte for byte. The scenes hold what the twin does not
/// walk: a voxelized field, a flat program stood up, a fractal, a noise
/// displacement, and a field's shadow, on itself and in a map.
@Suite
@MainActor
struct FieldSkipPictureTests {
    final class Scene: Sketch {
        var build: () -> SDF3D = { .sphere(radius: 1) }
        var shadowed = false
        override var canvasSize: CanvasSize { .size(180, 150) }
        let floor = Mesh.plane(width: 14, depth: 14)
        override func draw() {
            background(Color(white: 0.08))
            camera(.perspective(eye: Vector3(0, 3.2, 8.5), target: Vector3(0, 0.3, 0), fieldOfView: .pi / 4))
            directionalLight(.white, direction: Vector3(0.4, -0.75, -0.5), intensity: 1.1)
            ambientLight(Color(white: 0.2))
            if shadowed {
                castShadows()
                withState { translate(0, -2.2, 0); fill(Color(white: 0.8)); drawMesh(floor) }
            }
            fill(Color(red: 0.9, green: 0.5, blue: 0.2))
            material(.glossy)
            drawSDF3D(build())
        }
    }

    nonisolated static func cluster(_ seed: UInt64, _ count: Int = 14) -> SDF3D {
        var dice = FieldSkipTests.Dice(state: seed)
        var field = SDF3D.sphere(radius: 0.5).colored(Color(red: 0.2, green: 0.6, blue: 0.9))
        for i in 0 ..< count {
            let part = (i % 2 == 0 ? SDF3D.sphere(radius: 0.3 + Double(dice.next()) * 0.2)
                                   : SDF3D.box(size: 0.5)).at(dice.point(2))
                .colored(Color(hue: Double(dice.next()), saturation: 0.6, brightness: 0.9))
            field = i % 4 == 3 ? field.subtract(part) : field.smoothUnion(part, k: 0.2)
        }
        return field
    }

    nonisolated static let scenes: [(name: String, shadowed: Bool, build: @Sendable () -> SDF3D)] = [
        ("a cluster", false, { cluster(31) }),
        ("a cluster under a shadow, over a floor", true, { cluster(32, 9) }),
        // Kept inside what has drawn in one pass before today, whatever the passes do:
        // a field's instructions times a pixel's reads is under 64 capsules' at an export.
        ("every combine", false, { FieldSkipTests.everyCombine(seed: 14, rounds: 1) }),
        ("every scope", false, { FieldSkipTests.everyScope(seed: 15, light: true) }),
        ("blocks", false, { cluster(33, 5).voxelized(size: 0.22) }),
        ("blocks beside parts", true, {
            cluster(34, 4).voxelized(size: 0.25).union(cluster(35, 5).at(2.4, 0, 0))
        }),
        ("a flat shape stood up, a fractal, and a rough part among the rest", false, {
            cluster(36, 8)
                .union(SDF.star(outerRadius: 0.6, innerRadius: 0.3, points: 5).extruded(depth: 0.3).at(-2, 1, 0))
                .smoothUnion(SDF3D.mandelbulb(iterations: 4, radius: 0.6).at(2, 1, 0), k: 0.1)
                .union(SDF3D.sphere(radius: 0.5).roughened(amplitude: 0.04, frequency: 7).at(0, 1.6, 0))
                .union(SDF3D.mengerSponge(iterations: 2, size: 0.8).at(0, -1.4, 0.5))
        }),
    ]

    private func image(_ index: Int, _ policy: SDF3D.SkipPolicy,
                       on renderer: MetalRenderer) throws -> (CGImage, [SDFNode3D]) {
        let scene = Scene()
        scene.build = Self.scenes[index].build
        scene.shadowed = Self.scenes[index].shadowed
        scene.drawer.sdf3DSkipPolicy = policy
        OllinApp.isRenderingHeadless = true
        defer { OllinApp.isRenderingHeadless = false }
        let image = try #require(try OllinApp.renderImage(of: scene, frame: 0, fps: 60, renderer: renderer))
        return (image, scene.drawer.sdf3DNodes)
    }

    @Test(.enabled(if: Snapshot.hasMetal), arguments: scenes.indices)
    func aFieldDrawsTheSamePixelsWithItsSkips(_ index: Int) throws {
        let name = Self.scenes[index].name
        let renderer = try OllinApp.headlessRenderer(for: Scene())
        let (skipped, program) = try image(index, .always, on: renderer)
        let (whole, plain) = try image(index, .never, on: renderer)
        #expect(program.contains { $0.kind == 9 }, "\(name): the field was drawn with no skip")
        #expect(!plain.contains { $0.kind == 9 })
        let difference = try #require(imageDifference(skipped, whole))
        #expect(difference.max == 0,
                "\(name): the picture moved with the skips (mean \(difference.mean), most \(difference.max))")
        // The picture holds the field at all: a blank frame would pass the line above.
        let blank = try #require(imageDifference(skipped, try emptyFrame(on: renderer)))
        #expect(blank.max > 40, "\(name): the field drew nothing")
    }

    private func emptyFrame(on renderer: MetalRenderer) throws -> CGImage {
        final class Empty: Sketch {
            override var canvasSize: CanvasSize { .size(180, 150) }
            override func draw() { background(Color(white: 0.08)) }
        }
        OllinApp.isRenderingHeadless = true
        defer { OllinApp.isRenderingHeadless = false }
        return try #require(try OllinApp.renderImage(of: Empty(), frame: 0, fps: 60, renderer: renderer))
    }
}
