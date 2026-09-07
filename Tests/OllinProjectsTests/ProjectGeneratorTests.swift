import Foundation
import Testing
@testable import OllinProjects

/// The catalog's own rules, and what each kind emits. All pure: no disk, no
/// toolchain, no GPU.
@Suite("Project generator")
struct ProjectGeneratorTests {

    // MARK: - Catalog integrity

    @Test("Every template carries both placeholders exactly once")
    func templatePlaceholders() {
        for template in ProjectTemplate.all {
            let classCount = template.source.components(separatedBy: "{{CLASS}}").count - 1
            let hintCount = template.source.components(separatedBy: "{{HINTS}}").count - 1
            #expect(classCount >= 1, "\(template.id) never names its class")
            #expect(hintCount == 1, "\(template.id) has \(hintCount) hint slots, not 1")
        }
    }

    @Test("Every template asks only for capabilities that exist")
    func templateRequirements() {
        for template in ProjectTemplate.all {
            for id in template.requires {
                #expect(Capability.named(id) != nil, "\(template.id) requires unknown \(id)")
            }
            for id in template.kinds {
                #expect(ProjectKind.named(id) != nil, "\(template.id) names unknown kind \(id)")
            }
        }
    }

    @Test("Slugs are unique across each catalog")
    func uniqueSlugs() {
        #expect(Set(ProjectKind.all.map(\.id)).count == ProjectKind.all.count)
        #expect(Set(ProjectTemplate.all.map(\.id)).count == ProjectTemplate.all.count)
        #expect(Set(Capability.all.map(\.id)).count == Capability.all.count)
        #expect(Set(CanvasChoice.all.map(\.id)).count == CanvasChoice.all.count)
    }

    @Test("A kind that is not ready says what it waits on")
    func gatedKindsExplainThemselves() {
        for kind in ProjectKind.all where !kind.isAvailable {
            #expect(kind.waitingOn?.isEmpty == false, "\(kind.id) is gated with no reason")
        }
        // The point of the gate: the ones the framework cannot build yet are
        // still in the catalog, so they can be named rather than missing.
        #expect(ProjectKind.all.count > ProjectKind.available.count)
    }

    // MARK: - Naming

    @Test("A name becomes a type name that Swift will take")
    func typeNames() {
        func typeName(_ name: String) -> String {
            request(name: name).typeName
        }
        #expect(typeName("MyPiece") == "MyPiece")
        #expect(typeName("my piece") == "Mypiece")
        #expect(typeName("dots-and-lines") == "Dotsandlines")
        #expect(typeName("3D thing") == "MySketch")     // cannot start with a digit
        #expect(typeName("") == "MySketch")
        #expect(typeName("!!!") == "MySketch")
        #expect(typeName("with_underscores") == "With_underscores")
    }

    @Test("A folder name keeps the name as typed, minus the separators a path cannot take")
    func folderNames() {
        #expect(request(name: "My Piece").folderName == "My Piece")
        #expect(request(name: "a/b").folderName == "a-b")
        #expect(request(name: "  ").folderName == "MySketch")
    }

    // MARK: - Planning

    @Test("A gated kind is refused, carrying its reason")
    func refusesGatedKind() {
        var wanted = request(name: "Thing")
        wanted.kind = .visionOSApp
        #expect(throws: ProjectGeneratorError.self) {
            _ = try ProjectGenerator.plan(wanted)
        }
        // The message is the whole point of gating rather than omitting.
        let error = ProjectGeneratorError.kindUnavailable(.visionOSApp)
        #expect(error.description.contains("visionOS"))
    }

    @Test("A single file is one executable file carrying the interpreter line")
    func singleFileShape() throws {
        var wanted = request(name: "Dots")
        wanted.kind = .singleFile
        let project = try ProjectGenerator.plan(wanted)

        #expect(project.files.count == 1)
        let file = try #require(project.files.first)
        #expect(file.path == "Dots.swift")
        #expect(file.isExecutable)
        #expect(file.contents.hasPrefix("#!/usr/bin/env ollin\n"))
        #expect(file.contents.contains("final class Dots: Sketch"))
    }

    @Test("A project folder carries a manifest, a sketch, and the notes around them")
    func macSketchShape() throws {
        let project = try ProjectGenerator.plan(request(name: "MyPiece"))
        let paths = Set(project.files.map(\.path))

        #expect(paths.contains("Package.swift"))
        #expect(paths.contains("Sources/MyPiece/Sketch.swift"))
        #expect(paths.contains("README.md"))
        #expect(paths.contains(".gitignore"))
        #expect(project.files.allSatisfy { !$0.isExecutable })
    }

    @Test("Asked-for libraries reach both the import list and the manifest")
    func capabilitiesReachBothFiles() throws {
        var wanted = request(name: "Seen")
        wanted.capabilities = [.vision, .audio]
        let project = try ProjectGenerator.plan(wanted)

        let sketch = try #require(project.files.first { $0.path.hasSuffix("Sketch.swift") })
        #expect(sketch.contents.contains("import OllinVision"))
        #expect(sketch.contents.contains("import OllinAudio"))

        let manifest = try #require(project.files.first { $0.path == "Package.swift" })
        #expect(manifest.contents.contains("\"OllinVision\""))
        #expect(manifest.contents.contains("\"OllinAudio\""))
    }

    @Test("A template's own libraries come along without being asked for")
    func templateRequirementsAreWired() throws {
        var wanted = request(name: "Looking")
        wanted.template = .camera          // needs vision, nobody ticked it
        let project = try ProjectGenerator.plan(wanted)

        let sketch = try #require(project.files.first { $0.path.hasSuffix("Sketch.swift") })
        #expect(sketch.contents.contains("import OllinVision"))
    }

    @Test("A template that states its own canvas is never given a second one")
    func canvasIsDeclaredOnce() throws {
        var wanted = request(name: "Paper")
        wanted.template = .plotter         // declares .a4 itself
        wanted.canvas = .square1440
        let project = try ProjectGenerator.plan(wanted)

        let sketch = try #require(project.files.first { $0.path.hasSuffix("Sketch.swift") })
        let declarations = sketch.contents.components(separatedBy: "override var canvasSize").count - 1
        #expect(declarations == 1)
        #expect(sketch.contents.contains(".a4"))       // the template's own choice wins
    }

    @Test("A chosen canvas is declared on a template that has no opinion")
    func canvasIsAdded() throws {
        var wanted = request(name: "Tall")
        wanted.canvas = .vertical1080
        let project = try ProjectGenerator.plan(wanted)

        let sketch = try #require(project.files.first { $0.path.hasSuffix("Sketch.swift") })
        #expect(sketch.contents.contains("override var canvasSize: CanvasSize { .vertical1080 }"))
    }

    @Test("@main lands on the class, under whatever the template says about it")
    func mainAttributeSitsOnTheClass() throws {
        let project = try ProjectGenerator.plan(request(name: "Marked"))
        let sketch = try #require(project.files.first { $0.path.hasSuffix("Sketch.swift") })
        #expect(sketch.contents.contains("@main\nfinal class Marked: Sketch {"))
    }

    @Test("Two asset folders never collide once the bundle flattens them")
    func assetPlaceholdersAreDistinct() throws {
        var wanted = request(name: "Material")
        wanted.capabilities = [.images, .text, .video]
        let project = try ProjectGenerator.plan(wanted)

        // A processed folder is flattened into the bundle root, so the notes
        // inside two folders must not share a file name.
        let leaves = project.files.map { URL(fileURLWithPath: $0.path).lastPathComponent }
        let notes = leaves.filter { $0.hasSuffix(".md") }
        #expect(Set(notes).count == notes.count, "two notes share a name: \(notes)")
    }

    @Test("The framework is reached the way the caller asked")
    func frameworkSource() throws {
        var wanted = request(name: "Local")
        wanted.framework = .localPath(URL(fileURLWithPath: "/somewhere/Ollin"))
        var manifest = try manifestOf(wanted)
        #expect(manifest.contains(".package(path: \"/somewhere/Ollin\")"))

        wanted.framework = .remote(url: "https://example.com/Ollin.git", version: "0.1.0")
        manifest = try manifestOf(wanted)
        #expect(manifest.contains(".package(url: \"https://example.com/Ollin.git\", .upToNextMinor(from: \"0.1.0\"))"))
    }

    // MARK: - Writing

    @Test("Writing puts every planned file where the plan said")
    func writingMatchesThePlan() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        var wanted = request(name: "Written")
        wanted.destination = root
        let project = try ProjectGenerator.plan(wanted)
        try ProjectGenerator.write(project)

        for file in project.files {
            let url = project.root.appendingPathComponent(file.path)
            #expect(FileManager.default.fileExists(atPath: url.path), "missing \(file.path)")
            #expect(try String(contentsOf: url, encoding: .utf8) == file.contents)
        }
    }

    @Test("Writing never overwrites work that is already there")
    func writingRefusesToOverwrite() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        var wanted = request(name: "Twice")
        wanted.destination = root
        let project = try ProjectGenerator.plan(wanted)
        try ProjectGenerator.write(project)

        #expect(throws: ProjectGeneratorError.self) {
            try ProjectGenerator.write(project)
        }
    }

    @Test("A single file comes out runnable")
    func singleFileIsExecutable() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        var wanted = request(name: "Runnable")
        wanted.kind = .singleFile
        wanted.destination = root
        try ProjectGenerator.write(try ProjectGenerator.plan(wanted))

        let url = root.appendingPathComponent("Runnable.swift")
        #expect(FileManager.default.isExecutableFile(atPath: url.path))
    }

    // MARK: - Support

    private func request(name: String) -> ProjectRequest {
        ProjectRequest(
            name: name,
            destination: URL(fileURLWithPath: "/tmp"),
            framework: .localPath(URL(fileURLWithPath: "/somewhere/Ollin"))
        )
    }

    private func manifestOf(_ request: ProjectRequest) throws -> String {
        let project = try ProjectGenerator.plan(request)
        return try #require(project.files.first { $0.path == "Package.swift" }).contents
    }

    private func temporaryDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ollin-projects-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
