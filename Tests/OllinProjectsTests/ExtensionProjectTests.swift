import Foundation
import Testing
@testable import OllinProjects

/// An extension package is a library rather than a sketch, so it takes a
/// different path through the generator: a different name, a different manifest,
/// and the seam axis instead of the template one.
@Suite("Extension packages")
struct ExtensionProjectTests {

    // MARK: - Naming

    @Test("A name becomes one module and one package, each spelled as it is allowed to be")
    func namingFollowsTheConvention() {
        #expect(ExtensionNaming.moduleName(for: "Halftone") == "OllinxHalftone")
        #expect(ExtensionNaming.packageName(for: "Halftone") == "ollinx-halftone")
    }

    @Test("Words in the name are split apart for the package name")
    func aMultiWordNameIsHyphenated() {
        #expect(ExtensionNaming.packageName(for: "HalftonePress") == "ollinx-halftone-press")
        #expect(ExtensionNaming.packageName(for: "PlotterTools") == "ollinx-plotter-tools")
    }

    @Test("A run of capitals stays one word")
    func anInitialismIsNotSplitLetterByLetter() {
        // An initialism is one word to a reader even though it is several
        // capitals to a parser, so `ollinx-s-v-g-tools` would be wrong.
        #expect(ExtensionNaming.kebabCased("SVGTools") == "svg-tools")
        #expect(ExtensionNaming.kebabCased("SVG") == "svg")
        #expect(ExtensionNaming.kebabCased("X") == "x")
    }

    // MARK: - The plan

    @Test("The package is laid out around the module it builds")
    func theLayoutIsNamedForTheModule() throws {
        let project = try plan(named: "Halftone")
        let paths = project.files.map(\.path)

        #expect(project.root.lastPathComponent == "ollinx-halftone")
        #expect(paths.contains("Sources/OllinxHalftone/Halftone.swift"))
        #expect(paths.contains("Tests/OllinxHalftoneTests/HalftoneTests.swift"))
        #expect(paths.contains("Package.swift"))
        #expect(paths.contains("README.md"))
    }

    @Test("The manifest declares a library and a test target, and no executable")
    func theManifestIsALibrarysNotASketchs() throws {
        let manifest = try contents(of: "Package.swift", in: plan(named: "Halftone"))

        #expect(manifest.contains(".library(name: \"OllinxHalftone\", targets: [\"OllinxHalftone\"])"))
        #expect(manifest.contains(".testTarget("))
        // A sketch's manifest builds something to run. This one does not, and an
        // executable target here would mean the wrong emitter ran.
        #expect(!manifest.contains(".executableTarget("))
    }

    @Test("The seam decides what the starter is built on")
    func eachSeamWritesItsOwnStarter() throws {
        let filter = try contents(of: "Sources/OllinxTint/Tint.swift",
                                  in: plan(named: "Tint", seam: .filter))
        #expect(filter.contains("extension Filter"))
        #expect(filter.contains(".shader(Shader("))

        let source = try contents(of: "Sources/OllinxWall/Wall.swift",
                                  in: plan(named: "Wall", seam: .frameSource))
        #expect(source.contains(": FrameSource"))
        #expect(source.contains("public var frameTap: FrameTap?"))

        let lifecycle = try contents(of: "Sources/OllinxBar/Bar.swift",
                                     in: plan(named: "Bar", seam: .lifecycle))
        #expect(lifecycle.contains(": SketchExtension"))
    }

    @Test("With no seam named, the starter is the simplest one")
    func theDefaultSeamIsADrawCall() throws {
        let source = try contents(of: "Sources/OllinxPlain/Plain.swift", in: plan(named: "Plain"))
        #expect(source.contains("extension Sketch"))
        #expect(source.contains("public func drawSpiral"))
    }

    @Test("Every name in every emitted file is filled in")
    func noPlaceholderSurvivesIntoTheOutput() throws {
        // Two seams carry the extension's name inside their call site as well as
        // their source, so a placeholder can reach the README rather than the
        // code, where it is easy to miss.
        for seam in ExtensionSeam.all {
            let project = try plan(named: "Pattern", seam: seam)
            for file in project.files {
                #expect(!file.contents.contains("{{"),
                        "\(seam.id) left a placeholder in \(file.path)")
            }
        }
    }

    @Test("A template is not consulted, so one can never rule the kind out")
    func aTemplateDoesNotBlockAnExtension() throws {
        // A template's `fits` is about sketches. An extension is a library, so
        // asking the question at all would refuse a perfectly good package.
        for template in ProjectTemplate.all {
            let project = try plan(named: "Anyway", template: template)
            #expect(project.files.contains { $0.path == "Sources/OllinxAnyway/Anyway.swift" })
        }
    }

    @Test("The README says the one thing that stops the package building for anyone else")
    func theReadmeNamesTheLocalPathAsAReleaseStep() throws {
        let readme = try contents(of: "README.md", in: plan(named: "Halftone"))
        #expect(readme.contains("ollinx-halftone"))
        // The manifest points at this machine's own copy of the framework, which
        // is right while working and wrong the moment it is published.
        #expect(readme.lowercased().contains("path on this machine"))
    }

    // MARK: - Support

    private func plan(named name: String,
                      seam: ExtensionSeam? = nil,
                      template: ProjectTemplate = .blank) throws -> GeneratedProject {
        try ProjectGenerator.plan(ProjectRequest(
            name: name,
            kind: .extensionPackage,
            template: template,
            seam: seam,
            destination: URL(fileURLWithPath: "/tmp/ollin-extension-tests"),
            framework: .localPath(URL(fileURLWithPath: "/tmp/Ollin"))
        ))
    }

    private func contents(of path: String, in project: GeneratedProject) throws -> String {
        try #require(project.files.first { $0.path == path }?.contents,
                     "no \(path) in the plan")
    }
}
