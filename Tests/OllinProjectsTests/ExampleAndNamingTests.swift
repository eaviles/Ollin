import Foundation
import Testing
@testable import OllinProjects

/// Naming a sketch by dated serial, and starting one from an example.
@Suite("Starting points and names")
struct ExampleAndNamingTests {

    // MARK: - Dated serials

    @Test("An empty folder starts at one")
    func firstSerial() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(ProjectNaming.nextSerial(in: folder, year: 2026) == "Sketch2026001")
    }

    @Test("The next serial is one past the highest, whether it is a file or a folder")
    func nextSerialCountsBothShapes() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let manager = FileManager.default

        // A project folder and a loose file share one run of numbers, since the
        // same name can be either and a serial must not be reused across them.
        try manager.createDirectory(at: folder.appendingPathComponent("Sketch2026001"),
                                    withIntermediateDirectories: true)
        try "".write(to: folder.appendingPathComponent("Sketch2026004.swift"),
                     atomically: true, encoding: .utf8)

        #expect(ProjectNaming.nextSerial(in: folder, year: 2026) == "Sketch2026005")
    }

    @Test("A name that only looks like a serial never bumps the count")
    func foreignNamesAreIgnored() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        for name in ["Sketch2026007-old", "Sketch2026abc", "MyPiece", "Sketch2025099"] {
            try "".write(to: folder.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        // Only the 2025 one is a serial at all, and it is a different year.
        #expect(ProjectNaming.nextSerial(in: folder, year: 2026) == "Sketch2026001")
        #expect(ProjectNaming.nextSerial(in: folder, year: 2025) == "Sketch2025100")
    }

    @Test("The number is always three digits")
    func serialFormat() {
        #expect(ProjectNaming.serial(year: 2026, number: 1) == "Sketch2026001")
        #expect(ProjectNaming.serial(year: 2026, number: 42) == "Sketch2026042")
        #expect(ProjectNaming.serial(year: 2026, number: 999) == "Sketch2026999")
    }

    // MARK: - Reading an example

    @Test("A sketch's own type name is read off its declaration")
    func findsClassName() {
        #expect(ExampleSource.className(in: "final class Breathing: Sketch {") == "Breathing")
        #expect(ExampleSource.className(in: "@main\nfinal class Bloom_Example: Sketch {\n}") == "Bloom_Example")
        #expect(ExampleSource.className(in: "class Plain: Sketch {") == "Plain")
        #expect(ExampleSource.className(in: "struct NotASketch {}") == nil)
    }

    @Test("Renaming takes whole words only, everywhere they appear")
    func renamesWholeWords() {
        let source = """
        final class Dots: Sketch {
            let n = Dots.count
            let other = DotsExtra.thing
            let third = MyDots.thing
        }
        """
        let renamed = ExampleSource.renamed(source, to: "Sketch2026001")

        #expect(renamed.contains("final class Sketch2026001: Sketch"))
        #expect(renamed.contains("Sketch2026001.count"))
        // A longer name that merely starts or ends with it is somebody else's.
        #expect(renamed.contains("DotsExtra.thing"))
        #expect(renamed.contains("MyDots.thing"))
    }

    @Test("A sketch states which libraries it needs by importing them")
    func readsModules() {
        let source = """
        import Foundation
        import Ollin
        import OllinVision
        import OllinAudio
        """
        // Catalog order, not the file's, so a manifest reads the same each time.
        #expect(ExampleSource.modules(in: source) == ["OllinAudio", "OllinVision"])
        #expect(ExampleSource.modules(in: "import Ollin").isEmpty)
    }

    @Test("A library the catalog has never heard of is still linked")
    func unknownSatellitesSurvive() throws {
        // The failure this prevents: an `import` line is copied verbatim into
        // the new sketch, so a module the catalog filtered out would be imported
        // by the copy and absent from its manifest, and the project would not
        // build. It is the shape of the first day a new satellite ships.
        let source = "import Ollin\nimport OllinAudio\nimport OllinSerial\n"
        #expect(ExampleSource.modules(in: source) == ["OllinAudio", "OllinSerial"])

        let root = try stagedExamples()
        defer { try? FileManager.default.removeItem(at: root) }
        let future = root.appendingPathComponent("Rigs/Serial")
        try FileManager.default.createDirectory(at: future, withIntermediateDirectories: true)
        try """
        import Ollin
        import OllinSerial

        @main
        final class Serial: Sketch {
            override func draw() { background(.black) }
        }
        """.write(to: future.appendingPathComponent("Sketch.swift"), atomically: true, encoding: .utf8)

        let request = ProjectRequest(
            name: "Wired",
            example: ExampleSource.named("Rigs/Serial", in: root),
            destination: URL(fileURLWithPath: "/tmp"),
            framework: .localPath(URL(fileURLWithPath: "/somewhere/Ollin"))
        )
        let project = try ProjectGenerator.plan(request)
        let manifest = try #require(project.files.first { $0.path == "Package.swift" })
        #expect(manifest.contents.contains("\"OllinSerial\""))
    }

    @Test("Every example under a folder is found, with what sits beside it")
    func discovery() throws {
        let root = try stagedExamples()
        defer { try? FileManager.default.removeItem(at: root) }

        let found = ExampleSource.discover(in: root)
        #expect(found.map(\.path) == ["Motion/Breathing", "Vision/Faces"])

        let faces = try #require(found.first { $0.name == "Faces" })
        #expect(faces.group == "Vision")
        #expect(faces.modules == ["OllinVision"])
        #expect(faces.resources == ["model.mlmodelc"])
    }

    // MARK: - Generating from one

    @Test("An example arrives renamed, with its material and its credit intact")
    func generatesFromExample() throws {
        let root = try stagedExamples()
        defer { try? FileManager.default.removeItem(at: root) }

        let example = try #require(ExampleSource.named("Vision/Faces", in: root))
        let request = ProjectRequest(
            name: "Sketch2026001",
            example: example,
            destination: URL(fileURLWithPath: "/tmp"),
            framework: .localPath(URL(fileURLWithPath: "/somewhere/Ollin"))
        )
        let project = try ProjectGenerator.plan(request)

        let sketch = try #require(project.files.first { $0.path.hasSuffix("Sketch.swift") })
        #expect(sketch.contents.contains("final class Sketch2026001: Sketch"))
        // The header is where a ported or homage sketch's credit lives, so it
        // has to travel with the code rather than be stripped as boilerplate.
        #expect(sketch.contents.contains("after Somebody, used with permission"))

        // Its material comes along, copied rather than spelled out, and declared
        // or the copy would compile and then fail to find it.
        let resource = try #require(project.files.first { $0.path.hasSuffix("model.mlmodelc") })
        #expect(resource.copiedFrom != nil)
        let manifest = try #require(project.files.first { $0.path == "Package.swift" })
        #expect(manifest.contents.contains(".copy(\"model.mlmodelc\")"))

        // And what it imports decides what the manifest links.
        #expect(manifest.contents.contains("\"OllinVision\""))
    }

    @Test("An example wins over the template it was not asked for")
    func exampleBeatsTemplate() throws {
        let root = try stagedExamples()
        defer { try? FileManager.default.removeItem(at: root) }

        var request = ProjectRequest(
            name: "Mixed",
            template: .plotter,
            example: ExampleSource.named("Motion/Breathing", in: root),
            destination: URL(fileURLWithPath: "/tmp"),
            framework: .localPath(URL(fileURLWithPath: "/somewhere/Ollin"))
        )
        var sketch = ProjectGenerator.sketchSource(request)
        #expect(sketch.contains("final class Mixed: Sketch"))
        #expect(!sketch.contains("canvasSize: CanvasSize { .a4 }"))   // the template's own line

        request.example = nil
        sketch = ProjectGenerator.sketchSource(request)
        #expect(sketch.contains("canvasSize: CanvasSize { .a4 }"))
    }

    @Test("Extra libraries join the imports the example already has")
    func extraImportsAreAdded() throws {
        let root = try stagedExamples()
        defer { try? FileManager.default.removeItem(at: root) }

        let request = ProjectRequest(
            name: "Louder",
            example: ExampleSource.named("Vision/Faces", in: root),
            capabilities: [.audio],
            destination: URL(fileURLWithPath: "/tmp"),
            framework: .localPath(URL(fileURLWithPath: "/somewhere/Ollin"))
        )
        let sketch = ProjectGenerator.sketchSource(request)

        #expect(sketch.contains("import OllinAudio"))
        // Once, not twice: the example already imports vision.
        #expect(sketch.components(separatedBy: "import OllinVision").count - 1 == 1)
    }

    // MARK: - Support

    /// A small examples tree, so these tests do not lean on the repository's own
    /// example set staying as it is.
    private func stagedExamples() throws -> URL {
        let root = try temporaryDirectory()
        let manager = FileManager.default

        let breathing = root.appendingPathComponent("Motion/Breathing")
        try manager.createDirectory(at: breathing, withIntermediateDirectories: true)
        try """
        import Ollin

        /// A circle breathing.
        @main
        final class Breathing: Sketch {
            override func draw() { background(.white) }
        }
        """.write(to: breathing.appendingPathComponent("Sketch.swift"), atomically: true, encoding: .utf8)

        let faces = root.appendingPathComponent("Vision/Faces")
        try manager.createDirectory(at: faces, withIntermediateDirectories: true)
        try """
        import Ollin
        import OllinVision

        // A homage after Somebody, used with permission.
        @main
        final class Faces: Sketch {
            override func draw() { background(.black) }
        }
        """.write(to: faces.appendingPathComponent("Sketch.swift"), atomically: true, encoding: .utf8)
        try "weights".write(to: faces.appendingPathComponent("model.mlmodelc"),
                            atomically: true, encoding: .utf8)
        return root
    }

    private func temporaryDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ollin-examples-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

/// The 3D compatibility rules, which are the ones a generator must never get
/// wrong: offering a combination that does not work is worse than not offering
/// it, and refusing one that does work sends someone away from a real feature.
@Suite("3D combinations")
struct ThreeDRecipeTests {

    @Test("Geometry is never blocked, because everything under it settles to fit")
    func geometryIsAlwaysAvailable() {
        for geometry in ThreeDOption.inSlot(.geometry) {
            for finish in ThreeDOption.inSlot(.finish) {
                let recipe = ThreeDRecipe(geometry: .mesh, finish: finish,
                                          extras: Set(ThreeDOption.inSlot(.extra).map(\.id)))
                #expect(recipe.objection(to: geometry) == nil,
                        "\(geometry.id) was blocked while \(finish.id) was chosen")
            }
        }
    }

    @Test("A surface finish is refused for geometry that has no surface")
    func finishesNeedASurface() {
        for geometry in [ThreeDOption.wireframe, .pointCloud] {
            let recipe = ThreeDRecipe(geometry: geometry, finish: .unlit, extras: [])
            #expect(recipe.objection(to: .lit) != nil)
            #expect(recipe.objection(to: .physicallyBased) != nil)
            #expect(recipe.objection(to: .unlit) == nil)
        }
        // A field takes the lighting model, but never a matcap.
        let field = ThreeDRecipe(geometry: .field, finish: .lit, extras: [])
        #expect(field.objection(to: .lit) == nil)
        #expect(field.objection(to: .physicallyBased) == nil)
        #expect(field.objection(to: .matcap) != nil)
    }

    @Test("Traced reflections need both an environment and a physically based finish")
    func rayTracingRequirements() {
        var recipe = ThreeDRecipe(geometry: .mesh, finish: .physicallyBased, extras: [])
        #expect(recipe.objection(to: .rayTraced) != nil)          // no environment yet

        recipe.extras.insert(ThreeDOption.environment.id)
        #expect(recipe.objection(to: .rayTraced) == nil)

        recipe.finish = .lit
        #expect(recipe.objection(to: .rayTraced) != nil)          // and it needs the metal
    }

    @Test("A matcap turns off the lighting it replaces")
    func matcapExcludesLighting() {
        let recipe = ThreeDRecipe(geometry: .mesh, finish: .matcap, extras: [])
        #expect(recipe.objection(to: .shadows) != nil)
        #expect(recipe.objection(to: .environment) != nil)
        #expect(recipe.objection(to: .rayTraced) != nil)
        // The frame-wide ones still apply: they are not about surfaces.
        #expect(recipe.objection(to: .toneMap) == nil)
    }

    @Test("Changing the geometry drops whatever it rules out")
    func settlingKeepsARecipeCoherent() {
        var recipe = ThreeDRecipe.realistic
        #expect(recipe.objections.isEmpty)

        recipe.geometry = .wireframe
        recipe.settle()

        #expect(recipe.objections.isEmpty, "settling left \(recipe.objections)")
        #expect(recipe.finish.id == ThreeDOption.unlit.id)
        #expect(!recipe.extras.contains(ThreeDOption.shadows.id))
        #expect(!recipe.extras.contains(ThreeDOption.rayTraced.id))
        // What survives is what a wireframe can still take.
        #expect(recipe.extras.contains(ThreeDOption.toneMap.id))
    }

    @Test("Every rule carries the sentence that explains it")
    func rulesExplainThemselves() {
        for option in ThreeDOption.all where !option.conflicts.isEmpty || !option.requires.isEmpty {
            #expect(!option.rule.isEmpty, "\(option.id) restricts something with no reason given")
        }
    }

    @Test("The realism stack is one of the combinations that holds together")
    func realisticRecipeIsValid() {
        #expect(ThreeDRecipe.realistic.objections.isEmpty)
        #expect(ThreeDRecipe().objections.isEmpty)
    }
}
