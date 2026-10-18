import Testing
import CoreGraphics
@testable import Ollin

/// Every 3D drawing helper draws what `drawMesh` of the same `Mesh` draws,
/// pixel for pixel: `drawBox(width:height:depth:)` and `drawMesh(.box(...))`
/// are two spellings of one solid, and the helper adds nothing of its own.
/// The numbers are uneven on purpose (a width unlike its height, a tube
/// unlike its radius, a count that is not the default), and the camera looks
/// from off every axis, so a helper that handed two of them over in the wrong
/// order, or dropped one for its default, would draw something else.
@Suite
@MainActor
struct BareForms3DTests {

    /// One solid's two spellings.
    struct Pair: Sendable, CustomTestStringConvertible {
        let name: String
        let bare: @MainActor @Sendable (Sketch) -> Void
        let twin: @MainActor @Sendable (Sketch) -> Void
        var testDescription: String { name }
    }

    nonisolated static let outline: [Vector2] = [
        Vector2(-0.3, -0.2), Vector2(0.35, -0.25), Vector2(0.25, 0.3), Vector2(-0.2, 0.22),
    ]
    nonisolated static let silhouette: [Vector2] = [
        Vector2(0.05, -0.5), Vector2(0.4, -0.2), Vector2(0.25, 0.3), Vector2(0.1, 0.5),
    ]
    nonisolated static let path: [Vector3] = [
        Vector3(-0.6, -0.3, 0), Vector3(-0.2, 0.3, 0.2), Vector3(0.3, -0.1, -0.2), Vector3(0.6, 0.35, 0.1),
    ]
    nonisolated static let upper: [Vector3] = [
        Vector3(-0.6, 0.3, 0), Vector3(-0.2, 0.45, 0.1), Vector3(0.3, 0.25, -0.1), Vector3(0.6, 0.4, 0),
    ]
    nonisolated static let rail = Curve3D(curveThrough: path, segments: 12)
    nonisolated static let sectionA = Shape(outline)
    nonisolated static let sectionB = Shape(outline.map { $0 * 0.6 })

    nonisolated static let pairs: [Pair] = [
        Pair(name: "box", bare: { $0.drawBox(width: 0.9, height: 0.5, depth: 0.7) },
             twin: { $0.drawMesh(.box(width: 0.9, height: 0.5, depth: 0.7)) }),
        Pair(name: "cube", bare: { $0.drawBox(size: 0.8) }, twin: { $0.drawMesh(.box(size: 0.8)) }),
        Pair(name: "sphere", bare: { $0.drawSphere(radius: 0.6, segments: 20, rings: 9) },
             twin: { $0.drawMesh(.sphere(radius: 0.6, segments: 20, rings: 9)) }),
        Pair(name: "cylinder", bare: { $0.drawCylinder(radius: 0.4, height: 0.9, segments: 14, caps: false) },
             twin: { $0.drawMesh(.cylinder(radius: 0.4, height: 0.9, segments: 14, caps: false)) }),
        Pair(name: "plane", bare: { $0.drawPlane(width: 1.2, depth: 0.7, segments: 3) },
             twin: { $0.drawMesh(.plane(width: 1.2, depth: 0.7, segments: 3)) }),
        Pair(name: "torus", bare: { $0.drawTorus(radius: 0.6, tube: 0.18, segments: 30, sides: 10) },
             twin: { $0.drawMesh(.torus(radius: 0.6, tube: 0.18, segments: 30, sides: 10)) }),
        Pair(name: "cone", bare: { $0.drawCone(radius: 0.5, height: 0.9, segments: 17) },
             twin: { $0.drawMesh(.cone(radius: 0.5, height: 0.9, segments: 17)) }),
        Pair(name: "pyramid", bare: { $0.drawPyramid(width: 0.9, depth: 0.6, height: 0.8) },
             twin: { $0.drawMesh(.pyramid(width: 0.9, depth: 0.6, height: 0.8)) }),
        Pair(name: "helix", bare: { $0.drawHelix(radius: 0.5, tube: 0.1, turns: 2.5, height: 0.9, segments: 120, sides: 8) },
             twin: { $0.drawMesh(.helix(radius: 0.5, tube: 0.1, turns: 2.5, height: 0.9, segments: 120, sides: 8)) }),
        Pair(name: "icosahedron", bare: { $0.drawIcosahedron(radius: 0.6) }, twin: { $0.drawMesh(.icosahedron(radius: 0.6)) }),
        Pair(name: "dodecahedron", bare: { $0.drawDodecahedron(radius: 0.6) }, twin: { $0.drawMesh(.dodecahedron(radius: 0.6)) }),
        Pair(name: "tetrahedron", bare: { $0.drawTetrahedron(radius: 0.6) }, twin: { $0.drawMesh(.tetrahedron(radius: 0.6)) }),
        Pair(name: "octahedron", bare: { $0.drawOctahedron(radius: 0.6) }, twin: { $0.drawMesh(.octahedron(radius: 0.6)) }),
        Pair(name: "torus knot", bare: { $0.drawTorusKnot(p: 3, q: 2, radius: 0.5, tube: 0.12, segments: 120, sides: 9) },
             twin: { $0.drawMesh(.torusKnot(p: 3, q: 2, radius: 0.5, tube: 0.12, segments: 120, sides: 9)) }),
        Pair(name: "capsule", bare: { $0.drawCapsule(radius: 0.3, height: 0.7, segments: 18, rings: 5) },
             twin: { $0.drawMesh(.capsule(radius: 0.3, height: 0.7, segments: 18, rings: 5)) }),
        Pair(name: "rounded box", bare: { $0.drawRoundedBox(width: 0.9, height: 0.5, depth: 0.7, radius: 0.1, segments: 8) },
             twin: { $0.drawMesh(.roundedBox(width: 0.9, height: 0.5, depth: 0.7, radius: 0.1, segments: 8)) }),
        Pair(name: "rounded cube", bare: { $0.drawRoundedBox(size: 0.8, radius: 0.12, segments: 8) },
             twin: { $0.drawMesh(.roundedBox(width: 0.8, height: 0.8, depth: 0.8, radius: 0.12, segments: 8)) }),
        Pair(name: "icosphere", bare: { $0.drawIcosphere(radius: 0.6, subdivisions: 1) },
             twin: { $0.drawMesh(.icosphere(radius: 0.6, subdivisions: 1)) }),
        Pair(name: "tube", bare: { $0.drawTube(path, radius: 0.12, sides: 7) },
             twin: { $0.drawMesh(.tube(along: path, radius: 0.12, sides: 7)) }),
        Pair(name: "strip", bare: { $0.drawStrip(between: path, and: upper) },
             twin: { $0.drawMesh(.strip(between: path, and: upper)) }),
        Pair(name: "extruded outline", bare: { $0.drawExtrude(outline, depth: 0.4) },
             twin: { $0.drawMesh(.extrude(outline, depth: 0.4)) }),
        Pair(name: "extruded shape", bare: { $0.drawExtrude(sectionA, depth: 0.4) },
             twin: { $0.drawMesh(.extrude(sectionA, depth: 0.4)) }),
        Pair(name: "lathe", bare: { $0.drawLathe(silhouette, segments: 14) },
             twin: { $0.drawMesh(.lathe(silhouette, segments: 14)) }),
        Pair(name: "mobius", bare: { $0.drawMobius(radius: 0.6, width: 0.25, segments: 40, sides: 6) },
             twin: { $0.drawMesh(.mobius(radius: 0.6, width: 0.25, segments: 40, sides: 6)) }),
        Pair(name: "klein", bare: { $0.drawKlein(scale: 0.2, segments: 40, sides: 16) },
             twin: { $0.drawMesh(.klein(scale: 0.2, segments: 40, sides: 16)) }),
        Pair(name: "superellipsoid", bare: { $0.drawSuperellipsoid(radius: 0.6, e1: 0.4, e2: 0.7, segments: 20, rings: 10) },
             twin: { $0.drawMesh(.superellipsoid(radius: 0.6, e1: 0.4, e2: 0.7, segments: 20, rings: 10)) }),
        Pair(name: "supershape", bare: { $0.drawSupershape(radius: 0.6, m: 5, n1: 0.3, n2: 0.4, n3: 0.5, segments: 30, rings: 14) },
             twin: { $0.drawMesh(.supershape(radius: 0.6, m: 5, n1: 0.3, n2: 0.4, n3: 0.5, segments: 30, rings: 14)) }),
        Pair(name: "swept outline", bare: { $0.drawSweep(outline, along: rail, scale: { 1 - $0 * 0.4 }, twist: { $0 * 0.8 }) },
             twin: { $0.drawMesh(.sweep(outline, along: rail, scale: { 1 - $0 * 0.4 }, twist: { $0 * 0.8 })) }),
        Pair(name: "swept shape", bare: { $0.drawSweep(sectionA, along: rail, capped: false) },
             twin: { $0.drawMesh(.sweep(sectionA, along: rail, capped: false)) }),
        Pair(name: "loft", bare: { $0.drawLoft([sectionA, sectionB], along: rail, smoothed: false) },
             twin: { $0.drawMesh(.loft([sectionA, sectionB], along: rail, smoothed: false)) }),
        Pair(name: "lofted outlines", bare: { $0.drawLoft([outline, outline.map { $0 * 0.5 }], along: rail, at: [0.1, 0.9]) },
             twin: { $0.drawMesh(.loft([outline, outline.map { $0 * 0.5 }], along: rail, at: [0.1, 0.9])) }),
        Pair(name: "text", bare: { $0.textFont(.systemBold); $0.textAlign(.center, .center); $0.drawText3D("Ab", size: 0.8, depth: 0.2) },
             twin: { $0.drawMesh(.text("Ab", font: .systemBold, size: 0.8, depth: 0.2, align: .center)) }),
    ]

    @Test(arguments: pairs)
    func theHelperDrawsItsMesh(_ pair: Pair) throws {
        let bare = pixels(of: try OllinApp.image(of: OneSolid(pair.bare), frame: 1))
        let twin = pixels(of: try OllinApp.image(of: OneSolid(pair.twin), frame: 1))
        let blank = pixels(of: try OllinApp.image(of: OneSolid { _ in }, frame: 1))
        #expect(bare != blank, "the helper drew nothing")
        #expect(bare == twin)
    }
}

/// A 96-point 3D canvas with one solid on it, lit from off-axis and seen from
/// off every axis, so a turned or mis-sized solid shows.
@MainActor
private final class OneSolid: Sketch {
    var paint: (Sketch) -> Void = { _ in }

    convenience init(_ paint: @escaping (Sketch) -> Void) {
        self.init()
        self.paint = paint
    }

    override var canvasSize: CanvasSize { .square(96) }

    override func draw() {
        background(.black)
        camera(Camera3D(eye: Vector3(1.6, 1.3, 2.4), target: .zero))
        directionalLight(.white, direction: Vector3(-0.4, -0.8, -0.5))
        fill(Color(red: 0.9, green: 0.7, blue: 0.3))
        paint(self)
    }
}
