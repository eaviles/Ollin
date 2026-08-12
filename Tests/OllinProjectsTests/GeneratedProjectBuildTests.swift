import Foundation
import Testing
@testable import OllinProjects

/// The check that matters most: what comes out of the generator has to build.
///
/// A scaffold that does not compile is worse than no scaffold, and none of the
/// pure tests can catch a template that calls something the framework renamed.
/// These two drive a real compiler, so they are the slow pair in this suite, and
/// they run one at a time rather than two builds at once.
@Suite("Generated projects build", .serialized)
struct GeneratedProjectBuildTests {

    @Test("Every template compiles against the framework as it stands")
    func everyTemplateCompiles() throws {
        let repository = try #require(Self.repositoryRoot(), "could not find the Ollin folder from the test file")
        let root = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        var targets: [String] = []
        for (index, template) in ProjectTemplate.all.enumerated() {
            let target = "Template\(index)"
            let request = ProjectRequest(
                name: target,
                template: template,
                destination: root,
                framework: .localPath(repository)
            )
            let directory = root.appendingPathComponent("Sources/\(target)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try ProjectGenerator.sketchSource(request)
                .write(to: directory.appendingPathComponent("Sketch.swift"),
                       atomically: true, encoding: .utf8)
            targets.append(target)
        }

        try Self.writeManifest(named: "TemplateCheck", targets: targets, at: root, repository: repository)
        let result = try Self.swiftBuild(in: root)
        #expect(result.succeeded, "a template stopped compiling:\n\(result.output)")
    }

    /// A sketch written around an imported shader has to compile too, and the
    /// three shapes differ: one draws the shader straight, one draws a layer for
    /// it to read, one draws a pair. Only the first was ever checked by hand.
    @Test("Every shape of imported-shader sketch compiles")
    func everyImportedShaderSketchCompiles() throws {
        let repository = try #require(Self.repositoryRoot(), "could not find the Ollin folder from the test file")
        let root = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let shaders = [
            "Generated": "void mainImage(out vec4 c, in vec2 f) { c = vec4(f / iResolution.xy, 0.0, 1.0); }",
            "Filtered": "void mainImage(out vec4 c, in vec2 f) { c = texture(iChannel0, f / iResolution.xy); }",
            "Combined": """
            void mainImage(out vec4 c, in vec2 f) {
                vec2 uv = f / iResolution.xy;
                c = mix(texture(iChannel0, uv), texture(iChannel1, uv), uv.x);
            }
            """,
        ]

        var targets: [String] = []
        var resources: [String: [String]] = [:]
        for target in shaders.keys.sorted() {
            let translated = ShaderImport.translate(glsl: shaders[target]!)
            let request = ProjectRequest(
                name: target,
                importedShader: ImportedShader(translated),
                destination: root,
                framework: .localPath(repository)
            )
            let directory = root.appendingPathComponent("Sources/\(target)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try ProjectGenerator.sketchSource(request)
                .write(to: directory.appendingPathComponent("Sketch.swift"),
                       atomically: true, encoding: .utf8)
            // The sketch loads the shader by name, so the file has to be there
            // and declared, exactly as the generated manifest declares it.
            let shaderFile = "\(ImportedShader.resourceName).metal"
            try translated.metalSource
                .write(to: directory.appendingPathComponent(shaderFile),
                       atomically: true, encoding: .utf8)
            resources[target] = [shaderFile]
            targets.append(target)
        }

        try Self.writeManifest(named: "ShaderImportCheck", targets: targets, at: root,
                               repository: repository, resources: resources)
        let result = try Self.swiftBuild(in: root)
        #expect(result.succeeded, "an imported-shader sketch stopped compiling:\n\(result.output)")
    }

    @Test("Every 3D combination the rules allow compiles")
    func everyValidThreeDRecipeCompiles() throws {
        let repository = try #require(Self.repositoryRoot(), "could not find the Ollin folder from the test file")
        let root = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        // The rules say which combinations are offered; this says they are all
        // real. A rule that permits something that does not compile is the worst
        // kind of wrong here, because the window would offer it.
        var recipes: [ThreeDRecipe] = []
        let extras = ThreeDOption.inSlot(.extra).map(\.id)
        for geometry in ThreeDOption.inSlot(.geometry) {
            for finish in ThreeDOption.inSlot(.finish) {
                // Each extra on its own, and then all of them at once, which is
                // the combination most likely to interact badly.
                for subset in extras.map({ Set([$0]) }) + [Set(extras)] {
                    var recipe = ThreeDRecipe(geometry: geometry, finish: finish, extras: subset)
                    guard recipe.objection(to: finish) == nil else { continue }
                    recipe.settle()
                    if !recipes.contains(recipe) { recipes.append(recipe) }
                }
            }
        }
        #expect(recipes.count > 12, "the sweep collapsed to \(recipes.count) recipes")

        var targets: [String] = []
        for (index, recipe) in recipes.enumerated() {
            let target = "Recipe\(index)"
            let request = ProjectRequest(
                name: target, template: .threeD, threeD: recipe,
                destination: root, framework: .localPath(repository)
            )
            let directory = root.appendingPathComponent("Sources/\(target)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try ProjectGenerator.sketchSource(request)
                .write(to: directory.appendingPathComponent("Sketch.swift"),
                       atomically: true, encoding: .utf8)
            targets.append(target)
        }

        try Self.writeManifest(named: "RecipeCheck", targets: targets, at: root, repository: repository)
        let result = try Self.swiftBuild(in: root)
        #expect(result.succeeded, "a 3D combination does not compile:\n\(result.output)")
    }

    @Test("A generated project builds exactly as it was written")
    func aGeneratedProjectBuilds() throws {
        let repository = try #require(Self.repositoryRoot(), "could not find the Ollin folder from the test file")
        let destination = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: destination) }

        // The most wired-up shape: a template with its own library, extra
        // capabilities, a copied shader file, and a processed asset folder, so
        // the manifest is exercised rather than just the sketch.
        let request = ProjectRequest(
            name: "Wired",
            template: .motion,
            capabilities: [.images, .shaders, .physics],
            canvas: .fhd1080,
            destination: destination,
            framework: .localPath(repository)
        )
        let project = try ProjectGenerator.plan(request)
        try ProjectGenerator.write(project)

        let result = try Self.swiftBuild(in: project.root)
        #expect(result.succeeded, "a generated project did not build:\n\(result.output)")
    }

    // MARK: - Support

    /// Walk up from this file to the folder holding the framework's manifest.
    static func repositoryRoot() -> URL? {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0 ..< 8 {
            let manifest = directory.appendingPathComponent("Package.swift")
            if let text = try? String(contentsOf: manifest, encoding: .utf8),
               text.contains("name: \"Ollin\"") {
                return directory
            }
            let parent = directory.deletingLastPathComponent()
            if parent == directory { break }
            directory = parent
        }
        return nil
    }

    /// One package with a target per sketch, so the framework is built once
    /// rather than once per sketch under test.
    static func writeManifest(named name: String, targets: [String],
                              at root: URL, repository: URL,
                              resources: [String: [String]] = [:]) throws {
        let products = ["Ollin", "OllinVision", "OllinAudio", "OllinPhysics"]
            .map { "                .product(name: \"\($0)\", package: \"Ollin\")," }
            .joined(separator: "\n")
        let stanzas = targets.map { target in
            // A target with no declared resource has no `Bundle.module`, so a
            // sketch that loads one would fail to compile here for a reason the
            // real generated manifest does not have.
            let declared = (resources[target] ?? []).map { "                    .copy(\"\($0)\")," }
                .joined(separator: "\n")
            let block = declared.isEmpty ? "" : "\n                resources: [\n\(declared)\n                ],"
            return """
                    .executableTarget(
                        name: "\(target)",
                        dependencies: [
            \(products)
                        ],
                        path: "Sources/\(target)",\(block)
                    ),
            """
        }.joined(separator: "\n")

        try """
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(
            name: "\(name)",
            platforms: [
                .macOS("26.0")
            ],
            dependencies: [
                .package(path: "\(repository.path)"),
            ],
            targets: [
        \(stanzas)
            ],
            swiftLanguageModes: [.v6]
        )
        """.write(to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
    }

    static func temporaryDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ollin-build-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func swiftBuild(in directory: URL) throws -> (succeeded: Bool, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["swift", "build", "--package-path", directory.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let output = String(data: data, encoding: .utf8) ?? ""
        // Only the lines worth reading when this fails.
        let interesting = output.split(separator: "\n")
            .filter { $0.contains("error") || $0.contains("warning: unhandled") }
            .prefix(20)
            .joined(separator: "\n")
        return (process.terminationStatus == 0, interesting.isEmpty ? output.suffix(2000).description : interesting)
    }
}
