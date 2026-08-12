import Foundation

/// Turns a `ProjectRequest` into files.
///
/// The work is split in two on purpose: `plan` is pure and touches nothing, so
/// it can be tested and shown as a preview, and `write` only puts the planned
/// files on disk. Both faces of the generator, the command line and the window,
/// run the same `plan`.
public enum ProjectGenerator {

    // MARK: - Planning

    public static func plan(_ request: ProjectRequest) throws -> GeneratedProject {
        guard request.kind.isAvailable else {
            throw ProjectGeneratorError.kindUnavailable(request.kind)
        }
        guard request.template.fits(request.kind) else {
            throw ProjectGeneratorError.templateDoesNotFit(request.template, request.kind)
        }

        switch request.kind.id {
        case ProjectKind.singleFile.id: return planSingleFile(request)
        case ProjectKind.macSketch.id:  return planMacSketch(request)
        case ProjectKind.inPackage.id:  return try planInPackage(request)
        default:
            throw ProjectGeneratorError.kindUnavailable(request.kind)
        }
    }

    /// One file, run by the `ollin` command. Assets, if any, sit beside it.
    private static func planSingleFile(_ request: ProjectRequest) -> GeneratedProject {
        let fileName = "\(request.folderName).swift"
        var files: [GeneratedFile] = [
            GeneratedFile(
                path: fileName,
                contents: "#!/usr/bin/env ollin\n" + sketchSource(request),
                isExecutable: true
            )
        ]
        // A loose sketch resolves `Bundle.module` to its own folder, so a shader
        // file beside it is reachable with no manifest in sight, and the same is
        // true of everything an example loads.
        if request.resolvedCapabilities.contains(where: { $0.id == Capability.shaders.id }) {
            files.append(GeneratedFile(path: "effect.metal", contents: shaderStub))
        }
        for resource in request.example?.resources ?? [] {
            files.append(GeneratedFile(
                path: resource,
                contents: "",
                copiedFrom: request.example!.directory.appendingPathComponent(resource)
            ))
        }

        let shown = request.destination.appendingPathComponent(fileName).path
        return GeneratedProject(
            root: request.destination,
            files: files,
            runCommand: "ollin \(shown)",
            nextSteps: [
                "Run it:  ollin \(shown)",
                "It is executable, so ./\(fileName) works too once you are in its folder.",
                "Edit and save while it runs: the window reloads in place.",
                "Any image, font, or shader you drop beside it is reachable with `in: .module`.",
            ]
        )
    }

    /// A folder with its own manifest, built and run by the Swift package manager.
    private static func planMacSketch(_ request: ProjectRequest) -> GeneratedProject {
        let root = request.destination.appendingPathComponent(request.folderName)
        let target = request.typeName
        let sourceDir = "Sources/\(target)"
        var files: [GeneratedFile] = []
        var resources: [String] = []

        files.append(GeneratedFile(path: "\(sourceDir)/Sketch.swift",
                                   contents: sketchSource(request)))

        // An example's own material (a picture, a mesh, a clip, its shader) is
        // copied over beside the sketch and declared, or the copy would compile
        // and then fail to find what it loads.
        if let example = request.example {
            for resource in example.resources {
                files.append(GeneratedFile(
                    path: "\(sourceDir)/\(resource)",
                    contents: "",
                    copiedFrom: example.directory.appendingPathComponent(resource)
                ))
                resources.append(".copy(\"\(resource)\")")
            }
        }

        for capability in request.resolvedCapabilities {
            if capability.id == Capability.shaders.id {
                // Kept as a flat, copied file: a `.metal` declared as a processed
                // resource is compiled into a library instead of staying source,
                // and a copied *folder* keeps its nesting, which puts the file out
                // of reach of a plain resource lookup.
                files.append(GeneratedFile(path: "\(sourceDir)/effect.metal",
                                           contents: shaderStub, isExecutable: false))
                resources.append(".copy(\"effect.metal\")")
                continue
            }
            for folder in capability.assetFolders {
                // Named after its folder, not README: a processed folder is
                // flattened into the bundle, so two folders each holding a
                // README would land on the same name and refuse to build.
                files.append(GeneratedFile(
                    path: "\(sourceDir)/\(folder.name)/\(folder.name).md",
                    contents: "# \(folder.name)\n\n\(folder.note)\n",
                    isExecutable: false
                ))
                // A processed folder is flattened into the bundle, which is what
                // puts each file within reach of a name-and-extension lookup.
                resources.append(".process(\"\(folder.name)\")")
            }
        }

        files.append(GeneratedFile(path: "Package.swift",
                                   contents: manifest(request, target: target, resources: resources),
                                   isExecutable: false))
        files.append(GeneratedFile(path: "README.md", contents: readme(request, target: target),
                                   isExecutable: false))
        files.append(GeneratedFile(path: ".gitignore", contents: gitignore, isExecutable: false))

        return GeneratedProject(
            root: root,
            files: files.sorted { $0.path < $1.path },
            runCommand: "swift run --package-path \(root.path) \(target)",
            nextSteps: [
                "Run it:  cd \(root.path) && swift run \(target)",
                "Edit while it runs:  ollin \(root.path)/\(sourceDir)/Sketch.swift",
                "Export a frame:  swift run \(target) --export frame.png",
                "The sketch and everything it loads live in \(sourceDir)/.",
            ]
        )
    }

    /// A sketch folder inside a package that already exists, plus one target in
    /// its manifest.
    ///
    /// The manifest is somebody's own code, so this is the one path that changes
    /// a file rather than only creating them, and it is deliberately timid: it
    /// refuses a package that cannot reach Ollin, and when it cannot find the
    /// target list unambiguously it writes the sketch anyway and hands the
    /// stanza over to be pasted instead of guessing.
    private static func planInPackage(_ request: ProjectRequest) throws -> GeneratedProject {
        guard let host = request.packageHost ?? PackageHost.nearest(from: request.destination) else {
            throw ProjectGeneratorError.noPackageHere(request.destination)
        }
        guard host.linksOllin else {
            throw ProjectGeneratorError.packageDoesNotLinkOllin(host)
        }

        let target = request.typeName
        let folder = request.folderName
        var files: [GeneratedFile] = [
            GeneratedFile(path: "\(folder)/Sketch.swift", contents: sketchSource(request))
        ]
        var resources: [String] = []

        if let example = request.example {
            for resource in example.resources {
                files.append(GeneratedFile(
                    path: "\(folder)/\(resource)",
                    contents: "",
                    copiedFrom: example.directory.appendingPathComponent(resource)
                ))
                resources.append(".copy(\"\(resource)\")")
            }
        }
        for capability in request.resolvedCapabilities {
            if capability.id == Capability.shaders.id {
                files.append(GeneratedFile(path: "\(folder)/effect.metal", contents: shaderStub))
                resources.append(".copy(\"effect.metal\")")
                continue
            }
            for asset in capability.assetFolders {
                files.append(GeneratedFile(
                    path: "\(folder)/\(asset.name)/\(asset.name).md",
                    contents: "# \(asset.name)\n\n\(asset.note)\n"
                ))
                resources.append(".process(\"\(asset.name)\")")
            }
        }

        // The target's own path, from the package root, so the sketch can live
        // wherever the folders already put it rather than in a fixed layout.
        let inside = host.relativePath(of: request.destination.appendingPathComponent(folder))
        let stanza = targetStanza(request, target: target, path: inside, resources: resources)

        var edits: [GeneratedEdit] = []
        var steps: [String] = []
        if let manifestText = try? String(contentsOf: host.manifest, encoding: .utf8),
           let updated = PackageHost.inserting(stanza, intoTargetsOf: manifestText) {
            edits.append(GeneratedEdit(
                file: host.manifest,
                updated: updated,
                summary: "one target added to \(host.name)'s Package.swift"
            ))
            steps.append("Run it:  cd \(host.root.path) && swift run \(target)")
        } else {
            steps.append("Could not read \(host.name)'s target list, so nothing was changed there.")
            steps.append("Add this target by hand:\n\(stanza)")
        }
        steps.append("Edit while it runs:  ollin \(request.destination.appendingPathComponent(folder).path)/Sketch.swift")
        steps.append("The framework builds once for the whole package, so this sketch is a one-file compile.")

        return GeneratedProject(
            root: request.destination,
            files: files.sorted { $0.path < $1.path },
            edits: edits,
            runCommand: "swift run --package-path \(host.root.path) \(target)",
            nextSteps: steps
        )
    }

    static func targetStanza(_ request: ProjectRequest, target: String,
                             path: String, resources: [String]) -> String {
        let known = request.resolvedCapabilities.compactMap(\.module)
        let fromExample = (request.example?.modules ?? []).filter { !known.contains($0) }
        let products = (["Ollin"] + (known + fromExample).sorted())
            .map { "                .product(name: \"\($0)\", package: \"Ollin\")," }
            .joined(separator: "\n")
        let resourceLine = resources.isEmpty
            ? ""
            : ",\n            resources: [\n" + resources.map { "                \($0)," }.joined(separator: "\n") + "\n            ]"
        return """
                .executableTarget(
                    name: "\(target)",
                    dependencies: [
        \(products)
                    ],
                    path: "\(path)"\(resourceLine)
                ),
        """
    }

    // MARK: - Source assembly

    /// The sketch file: imports, then the template's own class with its
    /// placeholders filled in.
    ///
    /// Public because the generator window previews a template by compiling and
    /// running exactly this, rather than showing a picture of it.
    public static func sketchSource(_ request: ProjectRequest) -> String {
        if let example = request.example { return exampleSource(request, example) }
        return templateSource(request)
    }

    /// The 3D template writes itself out of the recipe, since which pieces are
    /// in play is exactly what the sketch's `draw()` says.
    static func threeDBody(_ request: ProjectRequest) -> String {
        ThreeDSource.body(request.threeD ?? ThreeDRecipe(),
                          className: request.typeName,
                          hints: hints(request))
    }

    /// An example, copied over with its type renamed after the new project and
    /// any extra imports added. Everything else is left exactly as written,
    /// including the header comment, which for a ported or homage sketch is
    /// where the credit lives and must travel with the code.
    private static func exampleSource(_ request: ProjectRequest, _ example: ExampleSource.Example) -> String {
        let url = example.directory.appendingPathComponent("Sketch.swift")
        guard let original = try? String(contentsOf: url, encoding: .utf8) else {
            return templateSource(request)
        }
        var source = ExampleSource.renamed(original, to: request.typeName)

        // Only what the sketch does not already import: the ticked extras.
        let already = Set(ExampleSource.modules(in: source))
        let extras = request.resolvedCapabilities
            .compactMap(\.module)
            .filter { !already.contains($0) }
            .sorted()
        if !extras.isEmpty {
            source = addingImports(extras, to: source)
        }
        if let expression = request.canvas.expression, !source.contains("override var canvasSize") {
            source = insertCanvas(expression, into: source, typeName: request.typeName)
        }
        return source
    }

    /// Put new imports under the last one the file already has, so the block
    /// stays together wherever the sketch chose to put it.
    private static func addingImports(_ modules: [String], to source: String) -> String {
        var lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let last = lines.lastIndex(where: { $0.hasPrefix("import ") }) else {
            return modules.map { "import \($0)" }.joined(separator: "\n") + "\n" + source
        }
        lines.insert(contentsOf: modules.map { "import \($0)" }, at: last + 1)
        return lines.joined(separator: "\n")
    }

    private static func templateSource(_ request: ProjectRequest) -> String {
        var body = request.template.id == ProjectTemplate.threeD.id
            ? threeDBody(request)
            : request.template.source
                .replacingOccurrences(of: "{{CLASS}}", with: request.typeName)
                .replacingOccurrences(of: "{{HINTS}}", with: hints(request))

        // A template that already states its own canvas keeps it, so the two can
        // never both be declared.
        if let expression = request.canvas.expression, !body.contains("override var canvasSize") {
            body = insertCanvas(expression, into: body, typeName: request.typeName)
        }

        // `@main` goes on the class itself, under whatever the template says
        // about it, rather than above the note.
        let opening = "final class \(request.typeName): Sketch {"
        if let range = body.range(of: opening) {
            body = body.replacingCharacters(in: range, with: "@main\n" + opening)
        }

        let modules = request.resolvedCapabilities.compactMap(\.module).sorted()
        let imports = (["import Ollin"] + modules.map { "import \($0)" }).joined(separator: "\n")
        return "\(imports)\n\n\(body)\n"
    }

    /// The note inside `setup()`: what got wired in and the first call for each.
    /// Left as a comment so a freshly generated sketch always runs.
    private static func hints(_ request: ProjectRequest) -> String {
        // The template's own code already makes these calls, so repeating them
        // would be noise.
        let extras = request.resolvedCapabilities.filter {
            !request.template.requires.contains($0.id) && !$0.starterHint.isEmpty
        }
        guard !extras.isEmpty else { return "// runs once, before the first frame" }

        var lines = ["// Wired in and ready to use:"]
        for capability in extras {
            lines.append("//   \(capability.title): \(capability.starterHint)")
        }
        return lines.joined(separator: "\n        ")
    }

    /// Declare the canvas on the line under the class opening. Found by looking
    /// for the declaration rather than one exact spelling, since an example may
    /// write it differently from the templates.
    private static func insertCanvas(_ expression: String, into body: String, typeName: String) -> String {
        var lines = body.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let opening = lines.firstIndex(where: {
            $0.contains("class \(typeName)") && $0.contains(": Sketch") && $0.hasSuffix("{")
        }) else { return body }
        lines.insert("    override var canvasSize: CanvasSize { \(expression) }\n", at: opening + 1)
        return lines.joined(separator: "\n")
    }

    // MARK: - Supporting files

    private static func manifest(_ request: ProjectRequest, target: String, resources: [String]) -> String {
        // The union, so a library an example imports is linked even when the
        // capability catalog has never heard of it.
        let known = request.resolvedCapabilities.compactMap(\.module)
        let fromExample = (request.example?.modules ?? []).filter { !known.contains($0) }
        let modules = ["Ollin"] + (known + fromExample).sorted()
        let products = modules
            .map { "                .product(name: \"\($0)\", package: \"Ollin\")," }
            .joined(separator: "\n")
        let resourceLine = resources.isEmpty
            ? ""
            : ",\n            resources: [\n" + resources.map { "                \($0)," }.joined(separator: "\n") + "\n            ]"

        return """
        // swift-tools-version: 6.0
        import PackageDescription

        // \(request.folderName): an Ollin sketch.
        //
        // Run it:      swift run \(target)
        // Export it:   swift run \(target) --export frame.png
        //
        // The framework is reached by path, so this builds against the copy of
        // Ollin already on this machine. Point `dependencies` somewhere else to
        // move the project to another one.
        let package = Package(
            name: "\(target)",
            platforms: [
                .macOS("26.0")
            ],
            dependencies: [
                \(request.framework.manifestEntry),
            ],
            targets: [
                .executableTarget(
                    name: "\(target)",
                    dependencies: [
        \(products)
                    ],
                    path: "Sources/\(target)"\(resourceLine)
                ),
            ],
            swiftLanguageModes: [.v6]
        )
        """
    }

    private static func readme(_ request: ProjectRequest, target: String) -> String {
        let wired = request.resolvedCapabilities
        let wiredSection: String
        if wired.isEmpty {
            wiredSection = "Nothing beyond the framework itself yet. Add a library to `Package.swift` when you need one.\n"
        } else {
            wiredSection = wired.map { capability in
                let module = capability.module.map { " (`import \($0)`)" } ?? ""
                return "- **\(capability.title)**\(module): \(capability.summary)"
            }.joined(separator: "\n") + "\n"
        }

        return """
        # \(request.folderName)

        \(request.template.summary)

        ## Running it

        ```sh
        swift run \(target)
        ```

        The window opens and keeps drawing. To edit it and watch the change land without the window closing, open the same file through the live host instead:

        ```sh
        ollin Sources/\(target)/Sketch.swift
        ```

        ## Leaving with a picture

        Every export runs headlessly on a fixed clock, so the result is the same every time:

        ```sh
        swift run \(target) --export frame.png          # one frame
        swift run \(target) --export-video out.mp4 --seconds 8
        swift run \(target) --export-svg out.svg        # vectors, for a plotter
        ```

        Each export records the seed and the knob values it used, so a picture you like can be made again.

        ## What is wired in

        \(wiredSection)
        ## Where things go

        The sketch and everything it loads live in `Sources/\(target)/`. A file dropped in there is reachable by name once `Package.swift` lists it as a resource, which the folders already created here do for you.
        """
    }

    private static let gitignore = """
    .build/
    .swiftpm/
    .DS_Store
    *.xcodeproj
    """

    private static let shaderStub = """
    // A shader of your own. The contract is one function: `shade` gets a 0...1
    // coordinate with its origin at the top left, and returns a straight sRGB
    // color. Everything around it is generated for you.
    //
    // Reach it from the sketch with `Shader(resource: "effect", in: .module)`,
    // then run it with `generate(...)`, `layer.filtered(...)`, or `combined(with:)`
    // depending on how many inputs it takes.

    float4 shade(float2 uv, ShaderInfo info) {
        float2 p = uv * 2.0 - 1.0;
        p.x *= info.resolution.x / info.resolution.y;

        float rings = 0.5 + 0.5 * sin(length(p) * 10.0 - info.time * 1.5);
        float3 color = palette(rings, float3(0.5), float3(0.5),
                               float3(1.0), float3(0.0, 0.10, 0.20));
        return float4(color, 1.0);
    }
    """

    // MARK: - Writing

    /// Put a planned project on disk. Refuses to touch a file that already
    /// exists, so a generator run can never overwrite work.
    @discardableResult
    public static func write(_ project: GeneratedProject) throws -> URL {
        let manager = FileManager.default

        for file in project.files {
            let url = project.root.appendingPathComponent(file.path)
            if manager.fileExists(atPath: url.path) {
                throw ProjectGeneratorError.fileExists(url)
            }
        }

        for file in project.files {
            let url = project.root.appendingPathComponent(file.path)
            try manager.createDirectory(at: url.deletingLastPathComponent(),
                                        withIntermediateDirectories: true)
            if let source = file.copiedFrom {
                try manager.copyItem(at: source, to: url)
            } else {
                try file.contents.write(to: url, atomically: true, encoding: .utf8)
            }
            if file.isExecutable {
                try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            }
        }

        // Edits last: everything they refer to is on disk by now, so a failure
        // here leaves a folder that is merely unlisted rather than a manifest
        // pointing at nothing.
        for edit in project.edits {
            try edit.updated.write(to: edit.file, atomically: true, encoding: .utf8)
        }
        return project.root
    }
}

/// A planned project: where it goes, every file it is made of, and what to say
/// once it is written.
public struct GeneratedProject: Sendable {
    /// The folder the paths are relative to.
    public let root: URL
    public let files: [GeneratedFile]
    /// Changes to files that already exist, which is a different promise from
    /// creating one and is kept separate so it can be shown as such.
    public let edits: [GeneratedEdit]
    /// The one command that runs the result.
    public let runCommand: String
    /// Lines to print, or show, after writing.
    public let nextSteps: [String]

    public init(root: URL, files: [GeneratedFile], edits: [GeneratedEdit] = [],
                runCommand: String, nextSteps: [String]) {
        self.root = root
        self.files = files
        self.edits = edits
        self.runCommand = runCommand
        self.nextSteps = nextSteps
    }
}

/// A change to a file that is already there.
///
/// Creating a file can promise never to destroy anything; changing one cannot,
/// so an edit carries the whole new text (worked out while planning, so the
/// window can show it before anything happens) and one line saying what it does.
public struct GeneratedEdit: Sendable, Hashable {
    public let file: URL
    /// The file's full contents after the change.
    public let updated: String
    /// What changed, in a few words.
    public let summary: String

    public init(file: URL, updated: String, summary: String) {
        self.file = file
        self.updated = updated
        self.summary = summary
    }
}

public struct GeneratedFile: Sendable, Hashable {
    /// Path relative to the project root.
    public let path: String
    /// The text to write, empty for a file copied from somewhere.
    public let contents: String
    /// Where to copy the file from, for material a generator cannot spell out
    /// (an example's picture, mesh, or clip).
    public let copiedFrom: URL?
    public let isExecutable: Bool

    public init(path: String, contents: String, copiedFrom: URL? = nil, isExecutable: Bool = false) {
        self.path = path
        self.contents = contents
        self.copiedFrom = copiedFrom
        self.isExecutable = isExecutable
    }
}

public enum ProjectGeneratorError: Error, CustomStringConvertible, Equatable {
    case kindUnavailable(ProjectKind)
    case templateDoesNotFit(ProjectTemplate, ProjectKind)
    case fileExists(URL)
    case noPackageHere(URL)
    case packageDoesNotLinkOllin(PackageHost)

    public var description: String {
        switch self {
        case .kindUnavailable(let kind):
            if let reason = kind.waitingOn {
                return "\(kind.title) is not ready yet: it waits on \(reason)."
            }
            return "\(kind.title) cannot be generated."
        case .templateDoesNotFit(let template, let kind):
            return "The \(template.title) template does not fit a \(kind.title.lowercased()) project."
        case .fileExists(let url):
            return "\(url.path) already exists; nothing was written."
        case .noPackageHere(let url):
            return "no Package.swift at or above \(url.path), so there is nothing to add the sketch to."
        case .packageDoesNotLinkOllin(let host):
            return "\(host.name) does not depend on Ollin yet, so a target added to it could not import the framework. Add the dependency, or make a self-contained project instead."
        }
    }
}
