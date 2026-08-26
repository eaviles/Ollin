import Foundation
import Testing
@testable import OllinProjects

/// The check that matters most: what comes out of the generator has to build.
///
/// A scaffold that does not compile is worse than no scaffold, and none of the
/// pure tests can catch a template that calls something the framework renamed.
/// These drive a real compiler, so they are the slow half of this suite, and
/// they run one at a time rather than several builds at once. Every nested
/// build shares one persistent scratch directory (see `scratchDirectory`), so
/// the framework compiles cold once ever rather than once per test per run;
/// without it, eight cold framework builds per run are most of this suite's
/// weight, and that load starves the wall-clock suites running beside it. The
/// time limit is the hang backstop: a nested build is a subprocess with no
/// timeout of its own, so a wedged one would otherwise wait forever.
@Suite("Generated projects build", .serialized, .timeLimit(.minutes(15)))
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

    /// A sketch written from a scene calls into the 3D surface by name: a camera
    /// initializer, six light factories, the transform stack, and the scene
    /// loader. Every one of those labels has to be the one the framework takes,
    /// and only a compiler can say so. Three of them were wrong the first time.
    @Test("A sketch written from a scene compiles, with every light kind in it")
    func aSceneSketchCompiles() throws {
        let repository = try #require(Self.repositoryRoot(), "could not find the Ollin folder from the test file")
        let root = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let everyLight: [ImportedLight] = [
            ImportedLight(kind: .directional, colorHex: 0xFFFFFF, intensity: 1,
                          direction: ImportedVector(-0.3, -0.8, -0.5)),
            ImportedLight(kind: .point, colorHex: 0xFFD9A0, intensity: 0.6,
                          position: ImportedVector(2, 3, 1)),
            ImportedLight(kind: .spot, colorHex: 0xFFFAF0, intensity: 2,
                          position: ImportedVector(1, 4, 1), direction: ImportedVector(0, -1, 0),
                          coneAngle: 0.6, penumbra: 0.25),
            ImportedLight(kind: .rect, colorHex: 0x88AAFF, intensity: 3,
                          position: ImportedVector(-2, 2, 0), direction: ImportedVector(1, 0, 0),
                          width: 1.5, height: 0.8, up: ImportedVector(0, 1, 0), twoSided: true),
            ImportedLight(kind: .disk, colorHex: 0xFF9955, intensity: 4,
                          position: ImportedVector(0, 3, -2), direction: ImportedVector(0, -1, 0),
                          radius: 0.7),
            ImportedLight(kind: .tube, colorHex: 0xFFFFFF, intensity: 8,
                          radius: 0.05,
                          endA: ImportedVector(-1, 2.5, 0), endB: ImportedVector(1, 2.5, 0)),
        ]

        // A nested group, a turn about a world axis, a turn about a tilted one,
        // and a non-uniform scale: every move the emitter can print.
        let tree = [
            ImportedSceneNode(
                name: "yard",
                translation: ImportedVector(0, 0.5, 0),
                children: [
                    ImportedSceneNode(name: "shed", part: "shed",
                                      rotation: ImportedRotation(angle: 0.4,
                                                                 axis: ImportedVector(0, 1, 0)),
                                      scale: ImportedVector(1, 2, 1)),
                    ImportedSceneNode(name: "vane", part: "vane",
                                      translation: ImportedVector(0, 2, 0),
                                      rotation: ImportedRotation(angle: 0.9,
                                                                 axis: ImportedVector(0.577, 0.577, 0.577)),
                                      note: "wears several materials"),
                ]),
        ]

        let cases: [String: ImportedScene] = [
            "SceneFull": ImportedScene(
                resourceName: "yard", resourceExtension: "usdz",
                origin: "Made from yard.usdz.",
                camera: ImportedCamera(eye: ImportedVector(4, 3, 6), target: ImportedVector(0, 1, 0),
                                       up: ImportedVector(0, 1, 0), near: 0.1, far: 100,
                                       projection: .perspective(fieldOfView: 0.69)),
                lights: everyLight, roots: tree, partNames: ["shed", "vane"],
                notes: ["One part wears more than one material."]),
            // The other shape: no geometry, an orthographic camera, no file.
            "SceneRig": ImportedScene(
                camera: ImportedCamera(eye: ImportedVector(0, 0, 5), target: .zero,
                                       up: ImportedVector(0, 1, 0), near: 0.1, far: 50,
                                       projection: .orthographic(height: 4)),
                lights: [everyLight[0]]),
        ]

        var targets: [String] = []
        var resources: [String: [String]] = [:]
        for target in cases.keys.sorted() {
            let scene = cases[target]!
            let request = ProjectRequest(name: target, importedScene: scene,
                                         destination: root, framework: .localPath(repository))
            let directory = root.appendingPathComponent("Sources/\(target)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try ProjectGenerator.sketchSource(request)
                .write(to: directory.appendingPathComponent("Sketch.swift"),
                       atomically: true, encoding: .utf8)
            // The sketch reads its geometry through `Bundle.module`, which only
            // exists for a target that declares a resource, so the stand-in has
            // to be declared exactly as the generated manifest declares the real
            // file. Its contents never matter to the compiler.
            if let file = scene.resourceFileName {
                try Data().write(to: directory.appendingPathComponent(file))
                resources[target] = [file]
            }
            targets.append(target)
        }

        try Self.writeManifest(named: "SceneImportCheck", targets: targets, at: root,
                               repository: repository, resources: resources)
        let result = try Self.swiftBuild(in: root)
        #expect(result.succeeded, "a sketch written from a scene stopped compiling:\n\(result.output)")
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

    /// An extension package is offered on four seams, and each one is a different
    /// piece of the framework's public surface. A seam that does not compile is
    /// the worst failure here, since the generator would offer it; the *tests* it
    /// ships have to compile too, or the first thing an author runs fails.
    @Test("Every extension seam compiles, tests and all")
    func everyExtensionSeamCompiles() throws {
        let repository = try #require(Self.repositoryRoot(), "could not find the Ollin folder from the test file")
        let root = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        var modules: [String] = []
        for seam in ExtensionSeam.all {
            // Each seam gets its own name so the module names cannot collide.
            let name = seam.id.split(separator: "-").map(\.capitalized).joined()
            let module = ExtensionNaming.moduleName(for: name)

            let source = root.appendingPathComponent("Sources/\(module)")
            let tests = root.appendingPathComponent("Tests/\(module)Tests")
            try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: tests, withIntermediateDirectories: true)

            try seam.source(named: name, module: module)
                .write(to: source.appendingPathComponent("\(name).swift"),
                       atomically: true, encoding: .utf8)
            try seam.test(named: name, module: module)
                .write(to: tests.appendingPathComponent("\(name)Tests.swift"),
                       atomically: true, encoding: .utf8)
            modules.append(module)
        }

        try Self.writeLibraryManifest(named: "SeamCheck", modules: modules,
                                      at: root, repository: repository)
        let result = try Self.swiftBuild(in: root, buildingTests: true)
        #expect(result.succeeded, "an extension seam stopped compiling:\n\(result.output)")
    }

    /// The manifest an extension package gets is its own shape: a library
    /// product and a test target rather than something to run. Only a real
    /// resolve says whether it is a manifest the package manager accepts.
    @Test("A generated extension package builds and its tests pass")
    func aGeneratedExtensionPackageBuilds() throws {
        let repository = try #require(Self.repositoryRoot(), "could not find the Ollin folder from the test file")
        let destination = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: destination) }

        let request = ProjectRequest(
            name: "Halftone",
            kind: .extensionPackage,
            seam: .drawCall,
            destination: destination,
            framework: .localPath(repository)
        )
        let project = try ProjectGenerator.plan(request)
        try ProjectGenerator.write(project)

        let result = try Self.swiftTest(in: project.root)
        #expect(result.succeeded, "a generated extension package did not build or test:\n\(result.output)")
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

    /// A screen saver is the one kind whose output is not a program, so nothing
    /// about it is proved by a build that merely succeeds. This one runs the
    /// script the generator wrote, then asks the system to load what came out
    /// and hand back the class the property list names: the exact question the
    /// system asks, and the exact way a saver fails quietly.
    ///
    /// Loading it here is safe because this test target links the generator
    /// alone, never the framework, so the copy inside the saver arrives in a
    /// process that has none.
    @Test("A generated screen saver builds into a bundle the system can load")
    func aGeneratedScreenSaverBuildsAndLoads() throws {
        let repository = try #require(Self.repositoryRoot(), "could not find the Ollin folder from the test file")
        let destination = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: destination) }

        let request = ProjectRequest(
            name: "Ripple",
            kind: .screenSaver,
            template: .motion,
            destination: destination,
            framework: .localPath(repository)
        )
        let project = try ProjectGenerator.plan(request)
        try ProjectGenerator.write(project)

        let built = try Self.run([project.root.appendingPathComponent("build.sh").path])
        #expect(built.succeeded, "the screen saver's own build script failed:\n\(built.output)")

        let saver = project.root.appendingPathComponent("Ripple.saver")
        #expect(FileManager.default.fileExists(atPath: saver.path), "no .saver came out of the script")

        // The framework's own files have to travel inside the saver: they are
        // looked for beside the running program, and that program belongs to
        // the system.
        let resources = saver.appendingPathComponent("Contents/Resources/Ollin_Ollin.bundle")
        #expect(FileManager.default.fileExists(atPath: resources.path),
                "the framework's resources did not travel with the saver")

        let bundle = try #require(Bundle(url: saver), "the .saver is not a bundle")
        #expect(bundle.load(), "the system could not load the saver's binary")
        // The name is the check, not the nil. Asked for a class it cannot find,
        // the loader hands back some other class out of the bundle rather than
        // nothing, so a saver with a misspelled name loads, appears in the list,
        // and shows whatever it happened to pick.
        let principal: AnyClass = try #require(bundle.principalClass,
                                               "the saver's binary carries no classes at all")
        #expect(NSStringFromClass(principal) == "RippleSaverView",
                "Info.plist and the @objc name have come apart")
    }

    /// The app kind's quiet failure is a bundle that opens and shows nothing,
    /// because the framework's resource files did not travel and the renderer
    /// finds no shaders. A build that merely succeeds proves none of that, so
    /// this one runs the script the generator wrote, checks the signature the
    /// way the system will, and then runs the binary *from inside the bundle*:
    /// the export only renders if every resource resolves from the app's own
    /// Resources folder.
    @Test("A generated app builds, signs, and renders from inside its bundle")
    func aGeneratedAppBuildsSignsAndRuns() throws {
        let repository = try #require(Self.repositoryRoot(), "could not find the Ollin folder from the test file")
        let destination = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: destination) }

        let request = ProjectRequest(
            name: "Orbit",
            kind: .macApp,
            template: .motion,
            destination: destination,
            framework: .localPath(repository)
        )
        let project = try ProjectGenerator.plan(request)
        try ProjectGenerator.write(project)

        let built = try Self.run([project.root.appendingPathComponent("build.sh").path])
        #expect(built.succeeded, "the app's own build script failed:\n\(built.output)")

        let app = project.root.appendingPathComponent("Orbit.app")
        #expect(FileManager.default.fileExists(atPath: app.path), "no .app came out of the script")

        // The framework's own files have to travel inside the app: run from a
        // bundle, the binary looks for them in the bundle's Resources folder.
        let resources = app.appendingPathComponent("Contents/Resources/Ollin_Ollin.bundle")
        #expect(FileManager.default.fileExists(atPath: resources.path),
                "the framework's resources did not travel with the app")

        // The icon the sketch rendered of itself.
        let icon = app.appendingPathComponent("Contents/Resources/AppIcon.icns")
        #expect(FileManager.default.fileExists(atPath: icon.path),
                "the script did not fold the rendered frame into an icon")

        let bundle = try #require(Bundle(url: app), "the .app is not a bundle")
        #expect(bundle.infoDictionary?["CFBundlePackageType"] as? String == "APPL",
                "the property list does not describe an app")

        // The question the system asks before launching anything.
        let signed = try Self.run(["codesign", "--verify", "--strict", app.path])
        #expect(signed.succeeded, "the signature does not verify:\n\(signed.output)")

        // The proof the app actually runs as shipped: rendering needs the
        // shader segments, and from here they can only come from the bundle.
        let frame = destination.appendingPathComponent("frame.png")
        let ran = try Self.run([app.appendingPathComponent("Contents/MacOS/Orbit").path,
                                "--export", frame.path, "--frame", "3"])
        #expect(ran.succeeded, "the bundled binary could not render:\n\(ran.output)")
        #expect(FileManager.default.fileExists(atPath: frame.path),
                "the bundled binary rendered nothing")
    }

    /// The wallpaper kind splits the program in two, a sketch with no entry
    /// point and a wrapper carrying it, and only a build proves the two files
    /// agree (a stray `@main` on the sketch refuses to compile beside the
    /// wrapper's). The rest is the app's own wrapper, checked the app's way,
    /// plus the one line that keeps the piece out of the Dock.
    @Test("A generated wallpaper builds, stays out of the Dock, and renders from its bundle")
    func aGeneratedWallpaperBuildsAndRuns() throws {
        let repository = try #require(Self.repositoryRoot(), "could not find the Ollin folder from the test file")
        let destination = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: destination) }

        let request = ProjectRequest(
            name: "Drift",
            kind: .wallpaper,
            template: .motion,
            destination: destination,
            framework: .localPath(repository)
        )
        let project = try ProjectGenerator.plan(request)
        try ProjectGenerator.write(project)

        let built = try Self.run([project.root.appendingPathComponent("build.sh").path])
        #expect(built.succeeded, "the wallpaper's own build script failed:\n\(built.output)")

        let app = project.root.appendingPathComponent("Drift.app")
        #expect(FileManager.default.fileExists(atPath: app.path), "no .app came out of the script")

        let bundle = try #require(Bundle(url: app), "the .app is not a bundle")
        // Out of the Dock: a Dock icon for a program with no window reads as
        // a hang, since clicking it shows nothing.
        #expect(bundle.infoDictionary?["LSUIElement"] as? Bool == true,
                "the wallpaper app would appear in the Dock")

        let signed = try Self.run(["codesign", "--verify", "--strict", app.path])
        #expect(signed.succeeded, "the signature does not verify:\n\(signed.output)")

        // The wrapper keeps the shared command-line surface, which is what the
        // script's own icon render depends on too.
        let frame = destination.appendingPathComponent("frame.png")
        let ran = try Self.run([app.appendingPathComponent("Contents/MacOS/Drift").path,
                                "--export", frame.path, "--frame", "3"])
        #expect(ran.succeeded, "the bundled binary could not render:\n\(ran.output)")
        #expect(FileManager.default.fileExists(atPath: frame.path),
                "the bundled binary rendered nothing")
    }

    /// The menu-bar kind is the wallpaper's shape pointed at the other host,
    /// so what this build proves is the one thing that differs: the wrapper's
    /// call compiles against the framework it names.
    @Test("A generated menu-bar piece builds and renders from its bundle")
    func aGeneratedMenuBarPieceBuildsAndRuns() throws {
        let repository = try #require(Self.repositoryRoot(), "could not find the Ollin folder from the test file")
        let destination = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: destination) }

        let request = ProjectRequest(
            name: "Pulse",
            kind: .menuBar,
            template: .motion,
            destination: destination,
            framework: .localPath(repository)
        )
        let project = try ProjectGenerator.plan(request)
        try ProjectGenerator.write(project)

        let built = try Self.run([project.root.appendingPathComponent("build.sh").path])
        #expect(built.succeeded, "the menu-bar piece's own build script failed:\n\(built.output)")

        let app = project.root.appendingPathComponent("Pulse.app")
        #expect(FileManager.default.fileExists(atPath: app.path), "no .app came out of the script")

        let bundle = try #require(Bundle(url: app), "the .app is not a bundle")
        #expect(bundle.infoDictionary?["LSUIElement"] as? Bool == true,
                "the menu-bar app would appear in the Dock")

        let frame = destination.appendingPathComponent("frame.png")
        let ran = try Self.run([app.appendingPathComponent("Contents/MacOS/Pulse").path,
                                "--export", frame.path, "--frame", "3"])
        #expect(ran.succeeded, "the bundled binary could not render:\n\(ran.output)")
        #expect(FileManager.default.fileExists(atPath: frame.path),
                "the bundled binary rendered nothing")
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

    /// One package with a library and a test target per extension seam, so the
    /// framework is built once rather than once per seam.
    static func writeLibraryManifest(named name: String, modules: [String],
                                     at root: URL, repository: URL) throws {
        let stanzas = modules.map { module in
            """
                    .target(
                        name: "\(module)",
                        dependencies: [
                            .product(name: "Ollin", package: "Ollin"),
                        ],
                        path: "Sources/\(module)"
                    ),
                    .testTarget(
                        name: "\(module)Tests",
                        dependencies: ["\(module)"],
                        path: "Tests/\(module)Tests"
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

    /// One scratch directory for every nested build, persistent across runs so
    /// even the first build of a run is warm. SwiftPM keeps it incrementally
    /// correct; a second process building at the same moment blocks on the
    /// scratch lock rather than corrupting anything. The generated screen
    /// saver's own `build.sh` does not use it (that script is shipped generator
    /// output, not test plumbing), so that one test still pays a cold build.
    static let scratchDirectory: URL = {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Ollin", isDirectory: true)
            .appendingPathComponent("test-scratch", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static func swiftBuild(in directory: URL,
                           buildingTests: Bool = false) throws -> (succeeded: Bool, output: String) {
        var arguments = ["swift", "build", "--package-path", directory.path,
                         "--scratch-path", scratchDirectory.path]
        if buildingTests { arguments.append("--build-tests") }
        return try run(arguments)
    }

    /// Build *and* run a package's own tests, for the case where what the
    /// generator wrote includes tests an author is about to run.
    static func swiftTest(in directory: URL) throws -> (succeeded: Bool, output: String) {
        try run(["swift", "test", "--package-path", directory.path,
                 "--scratch-path", scratchDirectory.path])
    }

    static func run(_ arguments: [String]) throws -> (succeeded: Bool, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments
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
