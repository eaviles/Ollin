import Testing
import CoreGraphics
@testable import Ollin

/// Every combinator scope draws what its field value draws, pixel for pixel:
/// `subtract { drawRect(...); drawCircle(...) }` and
/// `drawSDF(plate.subtract(disk))` are two spellings of one merged field, and
/// the scope adds nothing of its own. The shapes overlap off center, each in
/// its own fill, and every radius and count is uneven, so a scope that handed
/// its operands over in the wrong order, dropped its radius, or took the step
/// count for the radius would draw something else. Each scope is also held
/// against a picture it must not be (the same shapes under the hard operator
/// of its kind, or under another operator for the hard ones), and has to put
/// ink on the canvas, so two blank frames cannot pass for a pair.
///
/// A scope serves both dimensions: under a camera it captures the solid
/// primitives and merges them as one raymarched field, the operator carried
/// over by its number. One member of each family is held to its `SDF3D` twin
/// there, beside the three domain scopes, whose third axis only a 3D field
/// reads.
@Suite
@MainActor
struct CombinatorScopeFormsTests {

    /// One operator's two spellings, and a picture it must not draw.
    struct Pair: Sendable, CustomTestStringConvertible {
        let name: String
        let scope: @MainActor @Sendable (Sketch) -> Void
        let twin: @MainActor @Sendable (Sketch) -> Void
        let other: @MainActor @Sendable (Sketch) -> Void
        var testDescription: String { name }
    }

    nonisolated static let warm = Color(red: 0.95, green: 0.7, blue: 0.25)
    nonisolated static let cool = Color(red: 0.25, green: 0.6, blue: 0.95)

    // MARK: The flat shapes, as bare calls and as field values

    /// A rounded plate left of center, a disk overlapping its lower right
    /// corner, and a small stud on its upper left one.
    static func plate(_ s: Sketch) { s.fill(warm); s.drawRect(10, 17, 34, 26, cornerRadius: 3) }
    static func disk(_ s: Sketch) { s.fill(cool); s.drawCircle(40, 37, 15) }
    static func stud(_ s: Sketch) { s.fill(cool); s.drawCircle(21, 22, 8) }
    static func both(_ s: Sketch) { plate(s); disk(s) }

    static func plateField() -> SDF { SDF.rect(width: 34, height: 26, cornerRadius: 3).colored(warm).at(27, 30) }
    static func diskField() -> SDF { SDF.circle(radius: 15).colored(cool).at(40, 37) }
    static func studField() -> SDF { SDF.circle(radius: 8).colored(cool).at(21, 22) }

    /// A small bar and a dot around `(x, y)`, for the scopes that copy what
    /// is drawn inside them. They are drawn around an origin moved to the
    /// middle of the canvas, where the copies stay in the frame.
    static func motif(_ s: Sketch, _ x: Double, _ y: Double) {
        s.fill(warm)
        s.drawRect(center: Vector2(x - 2, y - 3), width: 10, height: 5, cornerRadius: 1)
        s.fill(cool)
        s.drawCircle(x + 3, y + 3, 3.5)
    }
    static func motifField(_ x: Double, _ y: Double) -> SDF {
        SDF.rect(width: 10, height: 5, cornerRadius: 1).colored(warm).at(x - 2, y - 3)
            .union(SDF.circle(radius: 3.5).colored(cool).at(x + 3, y + 3))
    }

    static func hardUnion(_ s: Sketch) { s.union { both(s) } }
    static func hardSubtract(_ s: Sketch) { s.subtract { both(s) } }
    static func hardIntersect(_ s: Sketch) { s.intersect { both(s) } }

    nonisolated static let flatPairs: [Pair] = [
        Pair(name: "union", scope: { s in s.union { both(s) } },
             twin: { $0.drawSDF(plateField().union(diskField())) },
             other: { hardSubtract($0) }),
        Pair(name: "subtract", scope: { s in s.subtract { both(s) } },
             twin: { $0.drawSDF(plateField().subtract(diskField())) },
             other: { hardUnion($0) }),
        Pair(name: "intersect", scope: { s in s.intersect { both(s) } },
             twin: { $0.drawSDF(plateField().intersect(diskField())) },
             other: { hardUnion($0) }),
        Pair(name: "smooth union", scope: { s in s.smoothUnion(k: 9) { both(s) } },
             twin: { $0.drawSDF(plateField().smoothUnion(diskField(), k: 9)) },
             other: { hardUnion($0) }),
        Pair(name: "smooth subtract", scope: { s in s.smoothSubtract(k: 7) { both(s) } },
             twin: { $0.drawSDF(plateField().smoothSubtract(diskField(), k: 7)) },
             other: { hardSubtract($0) }),
        Pair(name: "smooth intersect", scope: { s in s.smoothIntersect(k: 7) { both(s) } },
             twin: { $0.drawSDF(plateField().smoothIntersect(diskField(), k: 7)) },
             other: { hardIntersect($0) }),
        Pair(name: "chamfer union", scope: { s in s.chamferUnion(radius: 8) { both(s) } },
             twin: { $0.drawSDF(plateField().chamferUnion(diskField(), radius: 8)) },
             other: { hardUnion($0) }),
        Pair(name: "chamfer subtract", scope: { s in s.chamferSubtract(radius: 6) { both(s) } },
             twin: { $0.drawSDF(plateField().chamferSubtract(diskField(), radius: 6)) },
             other: { hardSubtract($0) }),
        Pair(name: "chamfer intersect", scope: { s in s.chamferIntersect(radius: 6) { both(s) } },
             twin: { $0.drawSDF(plateField().chamferIntersect(diskField(), radius: 6)) },
             other: { hardIntersect($0) }),
        Pair(name: "stairs union", scope: { s in s.stairsUnion(radius: 10, steps: 3) { both(s) } },
             twin: { $0.drawSDF(plateField().stairsUnion(diskField(), radius: 10, steps: 3)) },
             other: { hardUnion($0) }),
        Pair(name: "stairs subtract", scope: { s in s.stairsSubtract(radius: 8, steps: 4) { both(s) } },
             twin: { $0.drawSDF(plateField().stairsSubtract(diskField(), radius: 8, steps: 4)) },
             other: { hardSubtract($0) }),
        Pair(name: "stairs intersect", scope: { s in s.stairsIntersect(radius: 8, steps: 2) { both(s) } },
             twin: { $0.drawSDF(plateField().stairsIntersect(diskField(), radius: 8, steps: 2)) },
             other: { hardIntersect($0) }),
        Pair(name: "columns union", scope: { s in s.columnsUnion(radius: 10, count: 3) { both(s) } },
             twin: { $0.drawSDF(plateField().columnsUnion(diskField(), radius: 10, count: 3)) },
             other: { hardUnion($0) }),
        Pair(name: "columns subtract", scope: { s in s.columnsSubtract(radius: 8, count: 4) { both(s) } },
             twin: { $0.drawSDF(plateField().columnsSubtract(diskField(), radius: 8, count: 4)) },
             other: { hardSubtract($0) }),
        Pair(name: "columns intersect", scope: { s in s.columnsIntersect(radius: 8, count: 2) { both(s) } },
             twin: { $0.drawSDF(plateField().columnsIntersect(diskField(), radius: 8, count: 2)) },
             other: { hardIntersect($0) }),
        // The sculpt block folds each shape under the verbs in force when it
        // was drawn: the disk carved hard, then the stud added over a melt.
        Pair(name: "sculpt with carve, add and blend",
             scope: { s in
                 s.sculpt {
                     plate(s)
                     s.carve()
                     disk(s)
                     s.add()
                     s.blend(6)
                     stud(s)
                 }
             },
             twin: { $0.drawSDF(plateField().subtract(diskField()).smoothUnion(studField(), k: 6)) },
             other: { s in s.union { both(s); stud(s) } }),
        // The domain scopes merge what is drawn inside, then copy it. Mirrored
        // across one axis only, and tiled wider than tall, so a scope that
        // swapped its flags or its spacing would place the copies elsewhere.
        Pair(name: "mirrored",
             scope: { s in s.translate(31, 33); s.mirrored(x: true, y: false) { motif(s, 17, 0) } },
             twin: { $0.translate(31, 33); $0.drawSDF(motifField(17, 0).mirrored(x: true, y: false)) },
             other: { s in s.translate(31, 33); s.union { motif(s, 17, 0) } }),
        Pair(name: "repeated on a grid",
             scope: { s in s.translate(31, 33); s.repeated(spacing: Vector2(21, 15), count: 1) { motif(s, 0, 0) } },
             twin: { $0.translate(31, 33); $0.drawSDF(motifField(0, 0).repeated(spacing: Vector2(21, 15), count: 1)) },
             other: { s in s.translate(31, 33); s.union { motif(s, 0, 0) } }),
        Pair(name: "repeated around a center",
             scope: { s in s.translate(31, 33); s.repeatedRadially(count: 5) { motif(s, 17, 0) } },
             twin: { $0.translate(31, 33); $0.drawSDF(motifField(17, 0).repeatedRadially(count: 5)) },
             other: { s in s.translate(31, 33); s.union { motif(s, 17, 0) } }),
    ]

    // MARK: The solids, as bare calls and as field values

    /// A box at the origin and a ball sunk into its top, off center, so the
    /// seam between them is a ring the camera sees from above. The ball is
    /// placed with the transform stack, which the scope reads back as the
    /// field's own offset; the box, drawn where the block opened, is read
    /// back at an offset of zero.
    static func boxAndBall(_ s: Sketch) {
        s.fill(warm)
        s.drawBox(width: 0.9, height: 0.5, depth: 0.7)
        s.translate(-0.06, 0.33, 0.03)
        s.fill(cool)
        s.drawSphere(radius: 0.32)
    }
    static func boxField() -> SDF3D { SDF3D.box(width: 0.9, height: 0.5, depth: 0.7).colored(warm).at(0, 0, 0) }
    static func ballField() -> SDF3D { SDF3D.sphere(radius: 0.32).colored(cool).at(-0.06, 0.33, 0.03) }

    /// One small ball at `(x, y, z)`, for the scopes that copy it.
    static func bead(_ s: Sketch, _ x: Double, _ y: Double, _ z: Double) {
        s.fill(warm)
        s.translate(x, y, z)
        s.drawSphere(radius: 0.16)
    }
    static func beadField(_ x: Double, _ y: Double, _ z: Double) -> SDF3D {
        SDF3D.sphere(radius: 0.16).colored(warm).at(x, y, z)
    }

    nonisolated static let solidPairs: [Pair] = [
        Pair(name: "subtract", scope: { s in s.subtract { boxAndBall(s) } },
             twin: { $0.drawSDF3D(boxField().subtract(ballField())) },
             other: { s in s.union { boxAndBall(s) } }),
        Pair(name: "smooth union", scope: { s in s.smoothUnion(k: 0.3) { boxAndBall(s) } },
             twin: { $0.drawSDF3D(boxField().smoothUnion(ballField(), k: 0.3)) },
             other: { s in s.union { boxAndBall(s) } }),
        Pair(name: "chamfer intersect", scope: { s in s.chamferIntersect(radius: 0.12) { boxAndBall(s) } },
             twin: { $0.drawSDF3D(boxField().chamferIntersect(ballField(), radius: 0.12)) },
             other: { s in s.intersect { boxAndBall(s) } }),
        Pair(name: "stairs subtract", scope: { s in s.stairsSubtract(radius: 0.2, steps: 3) { boxAndBall(s) } },
             twin: { $0.drawSDF3D(boxField().stairsSubtract(ballField(), radius: 0.2, steps: 3)) },
             other: { s in s.subtract { boxAndBall(s) } }),
        Pair(name: "columns union", scope: { s in s.columnsUnion(radius: 0.2, count: 3) { boxAndBall(s) } },
             twin: { $0.drawSDF3D(boxField().columnsUnion(ballField(), radius: 0.2, count: 3)) },
             other: { s in s.union { boxAndBall(s) } }),
        // Mirrored across x and z and not y, tiled along x and z at two
        // spacings, and turned about z in place of the default y: each reads
        // an axis the flat field has no use for.
        Pair(name: "mirrored in depth",
             scope: { s in s.mirrored(x: true, y: false, z: true) { bead(s, 0.42, 0.1, 0.3) } },
             twin: { $0.drawSDF3D(beadField(0.42, 0.1, 0.3).mirrored(x: true, y: false, z: true)) },
             other: { s in s.union { bead(s, 0.42, 0.1, 0.3) } }),
        Pair(name: "repeated on a lattice",
             scope: { s in s.repeated(spacing: Vector3(0.55, 0, 0.42), count: 1) { bead(s, 0.05, 0.1, -0.03) } },
             twin: { $0.drawSDF3D(beadField(0.05, 0.1, -0.03).repeated(spacing: Vector3(0.55, 0, 0.42), count: 1)) },
             other: { s in s.union { bead(s, 0.05, 0.1, -0.03) } }),
        Pair(name: "repeated around an axis",
             scope: { s in s.repeatedRadially(count: 5, around: Vector3(0, 0, 2)) { bead(s, 0.45, 0.1, 0.15) } },
             twin: { $0.drawSDF3D(beadField(0.45, 0.1, 0.15).repeatedRadially(count: 5, around: Vector3(0, 0, 2))) },
             other: { s in s.union { bead(s, 0.45, 0.1, 0.15) } }),
    ]

    /// How many pixels carry ink: any color channel past a dark gray.
    private static func inked(_ bytes: [UInt8]) -> Int {
        var count = 0
        for i in stride(from: 0, to: bytes.count, by: 4) where max(bytes[i], bytes[i + 1], bytes[i + 2]) > 48 {
            count += 1
        }
        return count
    }

    @Test(arguments: flatPairs)
    func theScopeDrawsItsField(_ pair: Pair) throws {
        let scope = pixels(of: try OllinApp.image(of: FlatStage(pair.scope), frame: 1))
        let twin = pixels(of: try OllinApp.image(of: FlatStage(pair.twin), frame: 1))
        let other = pixels(of: try OllinApp.image(of: FlatStage(pair.other), frame: 1))
        #expect(Self.inked(scope) >= 16, "the scope drew nothing")
        #expect(scope != other, "the scope drew what another operator draws")
        #expect(scope == twin)
    }

    /// A radius below zero is no radius: the scope draws what its value form
    /// draws, which holds the radius at zero. Handed over as written, the
    /// two spellings of one field draw two pictures.
    nonisolated static let negativePairs: [Pair] = [
        Pair(name: "chamfer union, radius below zero", scope: { s in s.chamferUnion(radius: -6) { both(s) } },
             twin: { $0.drawSDF(plateField().chamferUnion(diskField(), radius: -6)) },
             other: { s in s.chamferUnion(radius: 8) { both(s) } }),
        Pair(name: "stairs subtract, radius below zero",
             scope: { s in s.stairsSubtract(radius: -8, steps: 3) { both(s) } },
             twin: { $0.drawSDF(plateField().stairsSubtract(diskField(), radius: -8, steps: 3)) },
             other: { s in s.stairsSubtract(radius: 8, steps: 3) { both(s) } }),
        Pair(name: "columns intersect, radius below zero",
             scope: { s in s.columnsIntersect(radius: -8, count: 3) { both(s) } },
             twin: { $0.drawSDF(plateField().columnsIntersect(diskField(), radius: -8, count: 3)) },
             other: { s in s.columnsIntersect(radius: 8, count: 3) { both(s) } }),
    ]

    @Test(arguments: negativePairs)
    func aRadiusBelowZeroDrawsWhatItsValueFormDraws(_ pair: Pair) throws {
        let scope = pixels(of: try OllinApp.image(of: FlatStage(pair.scope), frame: 1))
        let twin = pixels(of: try OllinApp.image(of: FlatStage(pair.twin), frame: 1))
        let other = pixels(of: try OllinApp.image(of: FlatStage(pair.other), frame: 1))
        #expect(Self.inked(scope) >= 16, "the scope drew nothing")
        #expect(scope != other, "a radius below zero drew what the radius above it draws")
        #expect(scope == twin)
    }

    @Test(arguments: solidPairs)
    func theScopeDrawsItsSolidField(_ pair: Pair) throws {
        let scope = pixels(of: try OllinApp.image(of: SolidStage(pair.scope), frame: 1))
        let twin = pixels(of: try OllinApp.image(of: SolidStage(pair.twin), frame: 1))
        let other = pixels(of: try OllinApp.image(of: SolidStage(pair.other), frame: 1))
        #expect(Self.inked(scope) >= 16, "the scope drew nothing")
        #expect(scope != other, "the scope drew what another operator draws")
        #expect(scope == twin)
    }
}

/// A 64-point canvas for one merged flat field, stroked so the merged outline
/// shows as well as the fills.
@MainActor
private final class FlatStage: Sketch {
    var paint: (Sketch) -> Void = { _ in }

    convenience init(_ paint: @escaping (Sketch) -> Void) {
        self.init()
        self.paint = paint
    }

    override var canvasSize: CanvasSize { .square(64) }

    override func draw() {
        background(.black)
        stroke(Color(red: 0.9, green: 0.95, blue: 1))
        strokeWeight(2)
        paint(self)
    }
}

/// A 96-point 3D canvas for one merged solid field, lit from off-axis and
/// seen from off every axis, so a copy placed along the wrong one shows.
@MainActor
private final class SolidStage: Sketch {
    var paint: (Sketch) -> Void = { _ in }

    convenience init(_ paint: @escaping (Sketch) -> Void) {
        self.init()
        self.paint = paint
    }

    override var canvasSize: CanvasSize { .square(96) }

    override func draw() {
        background(.black)
        camera(Camera3D(eye: Vector3(1.2, 1.0, 1.8), target: .zero))
        directionalLight(.white, direction: Vector3(-0.4, -0.8, -0.5))
        paint(self)
    }
}
