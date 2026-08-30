import Foundation
import Testing
@testable import OllinProjects

/// What the emitter prints, given a scene description built by hand.
///
/// These are the pure half: no file is read and the framework is never linked,
/// so they check spelling and shape. Whether a real file turns into the right
/// description is `SceneImportTests` in the framework's own suite, which has a
/// loader to compare against.
@Suite("Scene source")
struct SceneSourceTests {

    // MARK: - Numbers

    @Test("A number is spelled the way a person would type it")
    func numbersAreSpelledPlainly() {
        #expect(ImportedSceneSource.num(0) == "0")
        #expect(ImportedSceneSource.num(-0.000001) == "0", "a number too small to print reads as zero")
        #expect(ImportedSceneSource.num(4) == "4", "a whole number keeps no decimal point")
        #expect(ImportedSceneSource.num(-2) == "-2")
        #expect(ImportedSceneSource.num(1.5) == "1.5", "a trailing zero is not printed")
        #expect(ImportedSceneSource.num(0.691234567) == "0.6912", "four places is the limit")
        #expect(ImportedSceneSource.num(.nan) == "0", "a number that is not one still has to print")
    }

    // MARK: - Rotations

    @Test("A turn about a world axis reads as the call named after that axis")
    func axisAlignedTurnsUseTheNamedCall() {
        let aboutY = ImportedRotation(angle: 1.25, axis: ImportedVector(0, 1, 0))
        #expect(ImportedSceneSource.rotationCall(aboutY) == "rotateY(1.25)")

        let aboutX = ImportedRotation(angle: 0.5, axis: ImportedVector(1, 0, 0))
        #expect(ImportedSceneSource.rotationCall(aboutX) == "rotateX(0.5)")

        let aboutZ = ImportedRotation(angle: 0.5, axis: ImportedVector(0, 0, 1))
        #expect(ImportedSceneSource.rotationCall(aboutZ) == "rotateZ(0.5)")
    }

    /// The same turn about the negative axis is that turn the other way, so it
    /// keeps the named call and takes the sign instead of printing a vector.
    @Test("A turn about a negative axis keeps the named call and flips the angle")
    func negativeAxisFlipsTheAngle() {
        let backwards = ImportedRotation(angle: 1.25, axis: ImportedVector(0, -1, 0))
        #expect(ImportedSceneSource.rotationCall(backwards) == "rotateY(-1.25)")
    }

    @Test("A turn about anything else keeps the general call")
    func tiltedAxisKeepsTheGeneralCall() {
        let tilted = ImportedRotation(angle: 0.8, axis: ImportedVector(0.577, 0.577, 0.577))
        let printed = ImportedSceneSource.rotationCall(tilted)
        #expect(printed.hasPrefix("rotate(0.8, axis: Vector3("),
                "got \(printed)")
    }

    // MARK: - Blocks

    @Test("A node that makes no move and only groups is flattened away")
    func aPlainGroupIsFlattened() {
        let group = ImportedSceneNode(
            name: "group",
            children: [ImportedSceneNode(name: "ball", part: "ball",
                                         translation: ImportedVector(0, 1, 0))])
        let lines = ImportedSceneSource.nodeBlock(group, indent: 0)
        #expect(!lines.contains { $0.contains("// group") },
                "an empty wrapper should not become a block of its own")
        #expect(lines.contains { $0.contains("drawPart(\"ball\")") })
        #expect(lines.filter { $0.contains("withState") }.count == 1,
                "only the child that actually moves needs scoping")
    }

    @Test("A group that does move keeps its block, and its children nest inside")
    func aMovingGroupKeepsItsBlock() {
        let group = ImportedSceneNode(
            name: "lamp",
            translation: ImportedVector(-1, 0, 2),
            children: [ImportedSceneNode(name: "shade", part: "shade",
                                         translation: ImportedVector(0, 1.5, 0))])
        let lines = ImportedSceneSource.nodeBlock(group, indent: 0)
        let text = lines.joined(separator: "\n")
        #expect(text.contains("// lamp"))
        #expect(text.contains("translate(-1, 0, 2)"))
        #expect(lines.filter { $0.contains("withState") }.count == 2,
                "the group and the child each scope their own moves")

        // The child's block has to sit inside the parent's, or it would be
        // placed in world space rather than relative to the lamp.
        let openedAt = try! #require(lines.firstIndex { $0.contains("withState") })
        let childAt = try! #require(lines.firstIndex { $0.contains("drawPart(\"shade\")") })
        let closedAt = try! #require(lines.lastIndex { $0.trimmingCharacters(in: .whitespaces) == "}" })
        #expect(openedAt < childAt && childAt < closedAt)
    }

    @Test("A node holding nothing that draws is left out entirely")
    func anEmptyNodeIsLeftOut() {
        let empty = ImportedSceneNode(name: "helper", translation: ImportedVector(3, 0, 0))
        #expect(!empty.drawsSomething)

        let scene = ImportedScene(roots: [empty])
        let source = ImportedSceneSource.body(scene, className: "Thing")
        #expect(!source.contains("helper"), "a node with no geometry under it draws nothing")
    }

    @Test("A note goes on the block it belongs to")
    func aNoteSitsOnItsOwnBlock() {
        let node = ImportedSceneNode(name: "pedestal", part: "pedestal",
                                     translation: ImportedVector(0, 0.5, 0),
                                     note: "wears several materials")
        let lines = ImportedSceneSource.nodeBlock(node, indent: 0)
        let noteAt = try! #require(lines.firstIndex { $0.contains("wears several materials") })
        let drawAt = try! #require(lines.firstIndex { $0.contains("drawPart") })
        #expect(noteAt < drawAt, "the note has to be read before the call it is about")
    }

    // MARK: - Lights and camera

    @Test("Every light kind prints its own factory, with the labels that factory takes")
    func everyLightKindPrintsItsFactory() {
        // Read whole, since what matters here is the call, not where it wraps.
        func call(_ kind: ImportedLight.Kind) -> String {
            ImportedSceneSource.lightLines(
                ImportedLight(kind: kind, colorHex: 0xFF8800, intensity: 2,
                              position: ImportedVector(1, 2, 3),
                              direction: ImportedVector(0, -1, 0),
                              endA: ImportedVector(0, 0, 0), endB: ImportedVector(0, 0, 1)))
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .joined(separator: " ")
        }
        #expect(call(.directional).hasPrefix("light(.directional(Color(hex: 0xFF8800), direction:"))
        #expect(call(.point).contains(".point(Color(hex: 0xFF8800), at: Vector3(1, 2, 3)"))
        #expect(call(.spot).contains("coneAngle:"), "the spot factory's label is coneAngle")
        #expect(call(.rectangle).contains("up:") && call(.rectangle).contains("isTwoSided:"))
        #expect(call(.disk).contains("isTwoSided:"))
        #expect(call(.tube).contains("from: Vector3(0, 0, 0), to: Vector3(0, 0, 1)"),
                "a tube is spelled by its two ends")
        for kind in [ImportedLight.Kind.directional, .point, .spot, .rectangle, .disk, .tube] {
            #expect(call(kind).contains("intensity: 2"))
        }
    }

    @Test("Both projections print the label Camera3D takes")
    func projectionsUseTheRightLabel() {
        let perspective = ImportedCamera(eye: .zero, target: ImportedVector(0, 0, -1), up: ImportedVector(0, 1, 0),
                                         near: 0.1, far: 100, projection: .perspective(fieldOfView: 1))
        #expect(ImportedSceneSource.cameraCall(perspective).joined().contains("fieldOfView: 1"))

        let ortho = ImportedCamera(eye: .zero, target: ImportedVector(0, 0, -1), up: ImportedVector(0, 1, 0),
                                   near: 0.1, far: 100, projection: .orthographic(height: 4))
        #expect(ImportedSceneSource.cameraCall(ortho).joined().contains("orthographic(height: 4)"))
    }

    // MARK: - The whole file

    @Test("A scene with geometry writes out its part names and reads the file for them")
    func geometryBringsItsOwnLoader() {
        let scene = ImportedScene(
            resourceName: "yard", resourceExtension: "usdz",
            roots: [ImportedSceneNode(name: "shed", part: "shed")],
            partNames: ["shed", "shed-2"])
        let source = ImportedSceneSource.body(scene, className: "Yard")

        #expect(source.contains("private static let partNames = [\"shed\", \"shed-2\"]"))
        #expect(source.contains("Scene(resource: \"yard\", withExtension: \"usdz\", in: .module)"))
        #expect(source.contains("loadParts()"))
        #expect(source.contains("private func drawPart(_ name: String)"))
    }

    /// A scene of nothing but lights and a camera is self-contained, and asking
    /// the sketch to load a file it does not need would be a lie.
    @Test("A scene with no geometry carries no file and no loader")
    func noGeometryMeansNoFile() {
        let scene = ImportedScene(lights: [ImportedLight(kind: .point, colorHex: 0xFFFFFF, intensity: 1)])
        #expect(!scene.needsResource)

        let source = ImportedSceneSource.body(scene, className: "Rig")
        #expect(!source.contains("Scene(resource:"))
        #expect(!source.contains("partNames"))
        #expect(source.contains("light(.point("))
    }

    @Test("A name carrying a quote or a line break cannot break the file")
    func awkwardNamesAreEscaped() {
        let node = ImportedSceneNode(name: "say \"hi\"\nplease", part: "say \"hi\"",
                                     translation: ImportedVector(1, 0, 0))
        let lines = ImportedSceneSource.nodeBlock(node, indent: 0)
        let text = lines.joined(separator: "\n")
        #expect(text.contains("drawPart(\"say \\\"hi\\\"\")"))
        #expect(lines.allSatisfy { !$0.contains("\n") }, "a comment cannot carry a line break")
    }
}
