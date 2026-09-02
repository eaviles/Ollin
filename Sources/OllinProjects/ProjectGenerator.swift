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

        // An extension package is a library, not a sketch, so it takes the seam
        // axis instead of the template one and never asks whether a template
        // fits.
        if request.kind.id == ProjectKind.extensionPackage.id {
            return planExtension(request)
        }

        guard request.template.fits(request.kind) else {
            throw ProjectGeneratorError.templateDoesNotFit(request.template, request.kind)
        }

        switch request.kind.id {
        case ProjectKind.singleFile.id:  return planSingleFile(request)
        case ProjectKind.macSketch.id:   return planMacSketch(request)
        case ProjectKind.macApp.id:      return planMacApp(request)
        case ProjectKind.inPackage.id:   return try planInPackage(request)
        case ProjectKind.screenSaver.id: return planScreenSaver(request)
        case ProjectKind.wallpaper.id:   return planWallpaper(request)
        case ProjectKind.menuBar.id:     return planMenuBar(request)
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
        if let file = request.importedScene?.sourceFile,
           let name = request.importedScene?.resourceFileName {
            files.append(GeneratedFile(path: name, contents: "", copiedFrom: file))
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
        var (files, resources) = sketchFiles(request, sourceDir: sourceDir)

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

    /// A sketch wrapped as a double-clickable app.
    ///
    /// The package is the mac sketch's, unchanged: an ordinary executable
    /// target. What makes it an app is the script beside it, which puts the
    /// `.app` folder around the built binary, renders one frame of the sketch
    /// into the icon, and signs the result. Ad-hoc by default, which runs on
    /// the building machine and nowhere else; a Developer ID identity and a
    /// notary profile make one that travels, and the script says which of the
    /// two it made every time.
    private static func planMacApp(_ request: ProjectRequest) -> GeneratedProject {
        let root = request.destination.appendingPathComponent(request.folderName)
        let target = request.typeName
        let sourceDir = "Sources/\(target)"
        var (files, resources) = sketchFiles(request, sourceDir: sourceDir)

        files.append(GeneratedFile(path: "Package.swift",
                                   contents: manifest(request, target: target, resources: resources),
                                   isExecutable: false))
        files.append(GeneratedFile(path: "Info.plist",
                                   contents: appInfoPlist(request, target: target),
                                   isExecutable: false))
        files.append(GeneratedFile(path: "build.sh",
                                   contents: appBuildScript(request, target: target),
                                   isExecutable: true))
        files.append(GeneratedFile(path: "README.md",
                                   contents: appReadme(request, target: target),
                                   isExecutable: false))
        files.append(GeneratedFile(path: ".gitignore", contents: appGitignore, isExecutable: false))

        return GeneratedProject(
            root: root,
            files: files.sorted { $0.path < $1.path },
            runCommand: "\(root.path)/build.sh",
            nextSteps: [
                "Make the app:  cd \(root.path) && ./build.sh",
                "Put it in Applications:  ./build.sh --install",
                "Edit while it runs in a window:  ollin \(root.path)/\(sourceDir)/Sketch.swift",
                "Hand it to somebody: README.md, under Giving it to somebody else.",
            ]
        )
    }

    /// A sketch wrapped as the machine's screen saver.
    ///
    /// The package builds a plug-in rather than a program, which is one line in
    /// the manifest: a dynamic library product with `-bundle` handed to the
    /// linker. What comes out is the Mach-O kind the system loads, and the
    /// script here puts the `.saver` folder around it.
    ///
    /// The two things the script does that are easy to miss are both about
    /// finding files at run time. The framework's own resources (the shader
    /// segments above all) are looked for beside the running program, and the
    /// running program belongs to whoever loaded the plug-in, so every resource
    /// bundle the build produced is copied into the saver's own `Resources`.
    /// And the binary's directory is asked for rather than assumed, because the
    /// two build systems the toolchain ships put it in different places.
    private static func planScreenSaver(_ request: ProjectRequest) -> GeneratedProject {
        let root = request.destination.appendingPathComponent(request.folderName)
        let target = request.typeName
        let sourceDir = "Sources/\(target)"
        let saverClass = "\(target)SaverView"
        var (files, resources) = sketchFiles(request, sourceDir: sourceDir)

        files.append(GeneratedFile(path: "\(sourceDir)/SaverView.swift",
                                   contents: saverViewSource(target: target, saverClass: saverClass)))
        files.append(GeneratedFile(path: "Package.swift",
                                   contents: saverManifest(request, target: target, resources: resources),
                                   isExecutable: false))
        files.append(GeneratedFile(path: "Info.plist",
                                   contents: saverInfoPlist(request, target: target, saverClass: saverClass),
                                   isExecutable: false))
        files.append(GeneratedFile(path: "build.sh",
                                   contents: saverBuildScript(request, target: target),
                                   isExecutable: true))
        files.append(GeneratedFile(path: "README.md",
                                   contents: saverReadme(request, target: target),
                                   isExecutable: false))
        files.append(GeneratedFile(path: ".gitignore", contents: saverGitignore, isExecutable: false))

        return GeneratedProject(
            root: root,
            files: files.sorted { $0.path < $1.path },
            runCommand: "\(root.path)/build.sh --install",
            nextSteps: [
                "Put it on this machine:  cd \(root.path) && ./build.sh --install",
                "Then pick it in System Settings, under Screen Saver.",
                "See it in a window first:  ollin \(root.path)/\(sourceDir)/Sketch.swift",
                "The sketch and everything it loads live in \(sourceDir)/.",
            ]
        )
    }

    /// A sketch wrapped as the desktop wallpaper.
    ///
    /// The package is the app's shape: an ordinary executable target with the
    /// app's own build script. What changes is the entry point, which moves
    /// from the sketch to a wrapper file that hands the sketch to the
    /// wallpaper host, and one line in the property list that keeps the app
    /// out of the Dock, since its only faces are the desktop itself and the
    /// menu-bar mark that quits it.
    private static func planWallpaper(_ request: ProjectRequest) -> GeneratedProject {
        let root = request.destination.appendingPathComponent(request.folderName)
        let target = request.typeName
        let sourceDir = "Sources/\(target)"
        var (files, resources) = sketchFiles(request, sourceDir: sourceDir)

        files.append(GeneratedFile(
            path: "\(sourceDir)/Main.swift",
            contents: surfaceMain(target: target,
                                  host: "OllinApp.runAsWallpaper { \(target)() }")))
        files.append(GeneratedFile(path: "Package.swift",
                                   contents: manifest(request, target: target, resources: resources),
                                   isExecutable: false))
        files.append(GeneratedFile(path: "Info.plist",
                                   contents: appInfoPlist(request, target: target, accessory: true),
                                   isExecutable: false))
        files.append(GeneratedFile(path: "build.sh",
                                   contents: appBuildScript(request, target: target),
                                   isExecutable: true))
        files.append(GeneratedFile(path: "README.md",
                                   contents: wallpaperReadme(request, target: target),
                                   isExecutable: false))
        files.append(GeneratedFile(path: ".gitignore", contents: appGitignore, isExecutable: false))

        return GeneratedProject(
            root: root,
            files: files.sorted { $0.path < $1.path },
            runCommand: "\(root.path)/build.sh",
            nextSteps: [
                "See it now:  cd \(root.path) && swift run \(target)  (the sparkle in the menu bar quits it)",
                "Make the app:  ./build.sh   then put it in Applications with ./build.sh --install",
                "Have it start with the machine: System Settings, General, Login Items, add the app.",
                "Edit in a window instead:  ollin \(root.path)/\(sourceDir)/Sketch.swift",
            ]
        )
    }

    /// A sketch wrapped as a menu-bar piece: the same app shape as the
    /// wallpaper, with the strip's host in the wrapper file instead.
    private static func planMenuBar(_ request: ProjectRequest) -> GeneratedProject {
        let root = request.destination.appendingPathComponent(request.folderName)
        let target = request.typeName
        let sourceDir = "Sources/\(target)"
        var (files, resources) = sketchFiles(request, sourceDir: sourceDir)

        files.append(GeneratedFile(
            path: "\(sourceDir)/Main.swift",
            contents: surfaceMain(target: target,
                                  host: "OllinApp.runInMenuBar { \(target)() }")))
        files.append(GeneratedFile(path: "Package.swift",
                                   contents: manifest(request, target: target, resources: resources),
                                   isExecutable: false))
        files.append(GeneratedFile(path: "Info.plist",
                                   contents: appInfoPlist(request, target: target, accessory: true),
                                   isExecutable: false))
        files.append(GeneratedFile(path: "build.sh",
                                   contents: appBuildScript(request, target: target),
                                   isExecutable: true))
        files.append(GeneratedFile(path: "README.md",
                                   contents: menuBarReadme(request, target: target),
                                   isExecutable: false))
        files.append(GeneratedFile(path: ".gitignore", contents: appGitignore, isExecutable: false))

        return GeneratedProject(
            root: root,
            files: files.sorted { $0.path < $1.path },
            runCommand: "\(root.path)/build.sh",
            nextSteps: [
                "See it now:  cd \(root.path) && swift run \(target)  (the strip's own menu quits it)",
                "Make the app:  ./build.sh   then put it in Applications with ./build.sh --install",
                "Have it start with the machine: System Settings, General, Login Items, add the app.",
                "Edit in a window instead:  ollin \(root.path)/\(sourceDir)/Sketch.swift",
            ]
        )
    }

    /// The sketch and everything it loads, plus the resource lines a manifest
    /// needs to declare them. Shared by every kind that puts a sketch in a
    /// target of its own, since what a sketch carries does not depend on what
    /// the target is finally built into.
    private static func sketchFiles(_ request: ProjectRequest,
                                    sourceDir: String) -> ([GeneratedFile], [String]) {
        var files: [GeneratedFile] = []
        var resources: [String] = []

        files.append(GeneratedFile(path: "\(sourceDir)/Sketch.swift",
                                   contents: sketchSource(request)))

        // A shader brought over from GLSL keeps its own file, kept as a flat
        // copied resource for the same reason the stub below is.
        if let shader = request.importedShader {
            files.append(GeneratedFile(path: "\(sourceDir)/\(ImportedShader.resourceName).metal",
                                       contents: shader.metalSource))
            resources.append(".copy(\"\(ImportedShader.resourceName).metal\")")
        }

        // The scene file itself, copied flat so `Scene(resource:extension:in:)`
        // finds it at the bundle root the way a copied `.metal` is found.
        if let file = request.importedScene?.sourceFile,
           let name = request.importedScene?.resourceFileName {
            files.append(GeneratedFile(path: "\(sourceDir)/\(name)", contents: "", copiedFrom: file))
            resources.append(".copy(\"\(name)\")")
        }

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

        return (files, resources)
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

        if let shader = request.importedShader {
            files.append(GeneratedFile(path: "\(folder)/\(ImportedShader.resourceName).metal",
                                       contents: shader.metalSource))
            resources.append(".copy(\"\(ImportedShader.resourceName).metal\")")
        }

        if let file = request.importedScene?.sourceFile,
           let name = request.importedScene?.resourceFileName {
            files.append(GeneratedFile(path: "\(folder)/\(name)", contents: "", copiedFrom: file))
            resources.append(".copy(\"\(name)\")")
        }

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

    /// A library other people's sketches import.
    ///
    /// The mechanics of an extension are already free: any package that depends
    /// on Ollin is one. What this writes is the *convention*, so the packages
    /// look alike and can be found: the `ollinx-` name, the module inside it, a
    /// worked starter on one real seam, and tests that check something.
    private static func planExtension(_ request: ProjectRequest) -> GeneratedProject {
        let name = request.typeName
        let module = request.extensionModuleName
        let package = request.extensionPackageName
        let seam = request.seam ?? .drawCall
        let root = request.destination.appendingPathComponent(package)

        let files: [GeneratedFile] = [
            GeneratedFile(path: "Sources/\(module)/\(name).swift",
                          contents: seam.source(named: name, module: module)),
            GeneratedFile(path: "Tests/\(module)Tests/\(name)Tests.swift",
                          contents: seam.test(named: name, module: module)),
            GeneratedFile(path: "Package.swift",
                          contents: extensionManifest(request, module: module, package: package)),
            GeneratedFile(path: "README.md",
                          contents: extensionReadme(request, name: name, module: module,
                                                    package: package, seam: seam)),
            GeneratedFile(path: ".gitignore", contents: gitignore),
        ]

        return GeneratedProject(
            root: root,
            files: files.sorted { $0.path < $1.path },
            runCommand: "swift build --package-path \(root.path)",
            nextSteps: [
                "Build it:  cd \(root.path) && swift build",
                "Test it:   cd \(root.path) && swift test",
                "Use it from a sketch:  import \(module), then \(seam.callSite.replacingOccurrences(of: "{{NAME}}", with: name))",
                "The README lists what to do before anyone else can install it.",
            ]
        )
    }

    private static func extensionManifest(_ request: ProjectRequest,
                                          module: String, package: String) -> String {
        """
        // swift-tools-version: 6.0
        import PackageDescription

        // \(package): an Ollin extension.
        //
        // A library, not a sketch. Someone installs it by URL like any Swift
        // package, adds `import \(module)`, and what it adds is simply there.
        //
        // The framework is reached by path, which builds against the copy of
        // Ollin already on this machine. Before publishing, point `dependencies`
        // at the framework's own repository instead, or nobody else can build it.
        let package = Package(
            name: "\(package)",
            platforms: [
                .macOS("26.0")
            ],
            products: [
                .library(name: "\(module)", targets: ["\(module)"]),
            ],
            dependencies: [
                \(request.framework.manifestEntry),
            ],
            targets: [
                .target(
                    name: "\(module)",
                    dependencies: [
                        .product(name: "Ollin", package: "Ollin"),
                    ]
                ),
                .testTarget(
                    name: "\(module)Tests",
                    dependencies: ["\(module)"]
                ),
            ],
            swiftLanguageModes: [.v6]
        )
        """
    }

    private static func extensionReadme(_ request: ProjectRequest, name: String, module: String,
                                        package: String, seam: ExtensionSeam) -> String {
        let call = seam.callSite.replacingOccurrences(of: "{{NAME}}", with: name)
        return """
        # \(package)

        \(seam.summary)

        An extension for [Ollin](https://github.com/eaviles/Ollin). It is an ordinary Swift package that depends on the framework, so there is nothing to register and no plug-in to install.

        ## Using it

        Add it to a sketch's `Package.swift`:

        ```swift
        dependencies: [
            .package(url: "https://example.com/\(package)", .upToNextMinor(from: "0.1.0")),
        ]
        ```

        Then import it and the addition is there:

        ```swift
        import Ollin
        import \(module)

        @main
        final class MySketch: Sketch {
            override func draw() {
                \(call)
            }
        }
        ```

        ## Working on it

        ```sh
        swift build
        swift test
        ```

        The tests check what can be checked away from a GPU. Anything that draws needs a probe that renders a known frame and reads the pixels back, which is how the framework tests its own drawing.

        ## Before publishing

        - [ ] Point `dependencies` in `Package.swift` at the framework's repository rather than a path on this machine. A path nobody else has is the one thing that stops a package building for them.
        - [ ] Add a `LICENSE`. An extension is your own work under your own license, and Ollin bundles nothing of yours, so the choice is entirely yours.
        - [ ] Name the repository `\(package)`, so it is recognisable and turns up in a search.
        - [ ] Say in this README which version of Ollin it was built against. The framework is before 1.0 and its API still moves.
        - [ ] Tag a version, so a dependant can ask for one.

        ## What it hangs off

        This starter is built on one seam: **\(seam.title.lowercased())**. The others, and what each promises, are in the framework's [extension guide](https://github.com/eaviles/Ollin/blob/main/Docs/Tools/Extensions.md).
        """
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
        let source: String
        if let shader = request.importedShader { source = importedShaderSource(request, shader) }
        else if let scene = request.importedScene { source = importedSceneSource(request, scene) }
        else if let example = request.example { source = exampleSource(request, example) }
        else { source = templateSource(request) }

        var text = request.kind.carriesEntryPoint ? source : withoutEntryPoint(source)
        // Asked for a shape, and the shape wins: the canvas keeps its own
        // proportions and is centered on what it is put on. Asked for nothing,
        // and a sketch with no window of its own takes the whole display.
        if request.kind.fillsTheDisplay, request.canvas.expression == nil {
            text = fillingTheDisplay(text, typeName: request.typeName)
        }
        return text
    }

    /// Declare `.resizable` on the line under the class opening, so `width` and
    /// `height` are the display's rather than the canvas's. Left alone if the
    /// sketch already says something about its window, since that is a sketch
    /// that has thought about it.
    private static func fillingTheDisplay(_ source: String, typeName: String) -> String {
        guard !source.contains("override var windowMode") else { return source }
        var lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let opening = lines.firstIndex(where: {
            $0.contains("class \(typeName)") && $0.contains(": Sketch") && $0.hasSuffix("{")
        }) else { return source }
        lines.insert("""
                // Drawn onto the whole display, so `width` and `height` are the
                // screen's. Take this out to keep the canvas's own proportions,
                // centered on black instead.
                override var windowMode: WindowMode { .resizable }
            """, at: opening + 1)
        return lines.joined(separator: "\n")
    }

    /// Drop the `@main` line from a sketch bound for a plug-in.
    ///
    /// Every path into a sketch writes one, and a maintained example carries its
    /// own, so this is done once here rather than guarded at each of the four
    /// places. Only a line that is nothing but the attribute counts, which is
    /// what keeps a sketch that mentions it in a comment intact.
    static func withoutEntryPoint(_ source: String) -> String {
        source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { $0.trimmingCharacters(in: .whitespaces) != "@main" }
            .joined(separator: "\n")
    }

    /// The sketch that draws a scene brought over from a file.
    private static func importedSceneSource(_ request: ProjectRequest, _ scene: ImportedScene) -> String {
        var source = "import Ollin\n\n"
            + ImportedSceneSource.body(scene, className: request.typeName)
            + "\n"
        if let expression = request.canvas.expression {
            source = insertCanvas(expression, into: source, typeName: request.typeName)
        }
        return source
    }

    /// The sketch that runs a shader brought over from GLSL. A single loose file
    /// carries the shader inline, because there is no target to declare a
    /// resource on; every other kind keeps it in its own `.metal` file, where it
    /// reloads on its own without a Swift build.
    private static func importedShaderSource(_ request: ProjectRequest, _ shader: ImportedShader) -> String {
        var source = "import Ollin\n\n"
            + ImportedShaderSource.body(shader, className: request.typeName,
                                        inlineShader: request.kind == .singleFile)
            + "\n"
        if let expression = request.canvas.expression {
            source = insertCanvas(expression, into: source, typeName: request.typeName)
        }
        return source
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

    /// The framework products a target has to link: Ollin, whatever the ticked
    /// capabilities bring, and whatever an example's own imports name.
    ///
    /// The union, so a library an example imports is linked even when the
    /// capability catalog has never heard of it.
    private static func productLines(_ request: ProjectRequest) -> String {
        let known = request.resolvedCapabilities.compactMap(\.module)
        let fromExample = (request.example?.modules ?? []).filter { !known.contains($0) }
        return (["Ollin"] + (known + fromExample).sorted())
            .map { "                .product(name: \"\($0)\", package: \"Ollin\")," }
            .joined(separator: "\n")
    }

    /// The `resources:` argument a target needs, or nothing at all when it
    /// carries no files.
    private static func resourceLine(_ resources: [String]) -> String {
        guard !resources.isEmpty else { return "" }
        return ",\n            resources: [\n"
            + resources.map { "                \($0)," }.joined(separator: "\n")
            + "\n            ]"
    }

    private static func manifest(_ request: ProjectRequest, target: String, resources: [String]) -> String {
        let products = productLines(request)
        let resourceLine = resourceLine(resources)

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

    // MARK: - The app's own files

    private static func appInfoPlist(_ request: ProjectRequest, target: String,
                                     accessory: Bool = false) -> String {
        let identifier = "com.example.\(target.lowercased())"

        // A piece that lives on the desktop or in the menu bar has no window
        // of its own to stand behind a Dock icon, so the app stays out of the
        // Dock and the app switcher.
        let accessoryKeys = accessory ? """


                <!-- The piece lives in the system, not in a window, so the app
                     keeps out of the Dock and the app switcher. Quit lives in
                     its menu-bar item. -->
                <key>LSUIElement</key>
                <true/>
            """ : ""

        // A bundled app that touches the camera or the microphone without the
        // matching usage line is killed on the first ask, so the lines ride
        // the capabilities that make those asks possible.
        var usageKeys = ""
        let capabilities = request.resolvedCapabilities.map(\.id)
        if capabilities.contains(Capability.vision.id) {
            usageKeys += """

                <!-- Shown the first time the app opens the camera. Without this
                     line the system kills the app instead of asking. -->
                <key>NSCameraUsageDescription</key>
                <string>\(request.folderName) draws with what the camera sees.</string>
            """
        }
        if capabilities.contains(Capability.bluetooth.id) {
            usageKeys += """

                <!-- Shown the first time the app uses Bluetooth. Without this
                     line the system kills the app instead of asking, and until
                     the question is answered the radio reports nothing at all. -->
                <key>NSBluetoothAlwaysUsageDescription</key>
                <string>\(request.folderName) draws with what a Bluetooth sensor reads.</string>
            """
        }
        if capabilities.contains(Capability.audio.id) {
            usageKeys += """

                <!-- Shown the first time the app opens the microphone. Without
                     this line the system kills the app instead of asking. -->
                <key>NSMicrophoneUsageDescription</key>
                <string>\(request.folderName) listens and draws what it hears.</string>
            """
        }

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleDevelopmentRegion</key>
            <string>en</string>
            <key>CFBundleExecutable</key>
            <string>\(target)</string>
            <!-- The icon build.sh renders from the sketch, or your own AppIcon.icns. -->
            <key>CFBundleIconFile</key>
            <string>AppIcon</string>
            <!-- Yours to change before you hand this to anybody. Two apps with
                 one identifier are one app as far as the system is concerned. -->
            <key>CFBundleIdentifier</key>
            <string>\(identifier)</string>
            <key>CFBundleInfoDictionaryVersion</key>
            <string>6.0</string>
            <!-- The name in the menu bar and the Dock. -->
            <key>CFBundleName</key>
            <string>\(request.folderName)</string>
            <key>CFBundlePackageType</key>
            <string>APPL</string>
            <key>CFBundleShortVersionString</key>
            <string>1.0</string>
            <key>CFBundleVersion</key>
            <string>1</string>
            <key>LSMinimumSystemVersion</key>
            <string>26.0</string>
            <key>NSHighResolutionCapable</key>
            <true/>\(accessoryKeys)\(usageKeys)
        </dict>
        </plist>
        """
    }

    private static func appBuildScript(_ request: ProjectRequest, target: String) -> String {
        """
        #!/bin/sh
        # Build the sketch and put the .app folder around it.
        #
        #   ./build.sh                 build it here, signed for this machine
        #   ./build.sh --install       build it and put it in /Applications
        #   ./build.sh --sign "Developer ID Application: Name (TEAMID)"
        #                              sign it so it can travel
        #   ./build.sh --sign "..." --notarize <profile>
        #                              also have Apple's notary pass it
        #
        set -e
        cd "$(dirname "$0")"

        NAME="\(request.folderName)"
        TARGET="\(target)"
        APP="$NAME.app"

        IDENTITY="-"
        PROFILE=""
        INSTALL=0
        while [ $# -gt 0 ]; do
            case "$1" in
                --install)  INSTALL=1 ;;
                --sign)     IDENTITY="$2"; shift ;;
                --notarize) PROFILE="$2"; shift ;;
                *) echo "build.sh: unknown option $1" >&2; exit 2 ;;
            esac
            shift
        done
        if [ -n "$PROFILE" ] && [ "$IDENTITY" = "-" ]; then
            echo "build.sh: --notarize needs --sign with a Developer ID identity" >&2
            exit 2
        fi

        swift build -c release
        # Asked for, not assumed: the two build systems the toolchain ships put
        # the binary in different places.
        BIN="$(swift build -c release --show-bin-path)"

        rm -rf "$APP"
        mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
        cp "$BIN/$TARGET" "$APP/Contents/MacOS/$TARGET"
        cp Info.plist "$APP/Contents/Info.plist"
        printf 'APPL????' > "$APP/Contents/PkgInfo"

        # The framework's own files: shader segments, fonts, tables. Run from a
        # bundle, the binary looks for them in the app's Resources folder, so
        # every resource bundle the build produced travels inside.
        for bundle in "$BIN"/*.bundle; do
            [ -e "$bundle" ] || continue
            cp -R "$bundle" "$APP/Contents/Resources/"
        done

        # The icon is the sketch: the freshly built binary renders one frame of
        # itself, squared and scaled into the .icns. An AppIcon.icns of your own
        # beside this script wins, and if the render fails the app just keeps
        # the stock icon.
        if [ -f AppIcon.icns ]; then
            cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
        else
            ICONWORK="$(mktemp -d)"
            if "$BIN/$TARGET" --export "$ICONWORK/frame.png" --frame 120 >/dev/null 2>&1; then
                W="$(sips -g pixelWidth  "$ICONWORK/frame.png" | awk '/pixelWidth/  {print $2}')"
                H="$(sips -g pixelHeight "$ICONWORK/frame.png" | awk '/pixelHeight/ {print $2}')"
                S="$W"
                if [ "$H" -lt "$S" ]; then S="$H"; fi
                sips -c "$S" "$S" "$ICONWORK/frame.png" --out "$ICONWORK/square.png" >/dev/null
                mkdir "$ICONWORK/AppIcon.iconset"
                for SIZE in 16 32 128 256 512; do
                    sips -z "$SIZE" "$SIZE" "$ICONWORK/square.png" \\
                         --out "$ICONWORK/AppIcon.iconset/icon_${SIZE}x${SIZE}.png" >/dev/null
                    sips -z "$((SIZE * 2))" "$((SIZE * 2))" "$ICONWORK/square.png" \\
                         --out "$ICONWORK/AppIcon.iconset/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
                done
                iconutil -c icns -o "$APP/Contents/Resources/AppIcon.icns" "$ICONWORK/AppIcon.iconset"
            else
                echo "build.sh: could not render the icon frame; the app keeps the stock icon" >&2
            fi
            rm -rf "$ICONWORK"
        fi

        if [ "$IDENTITY" = "-" ]; then
            # Ad-hoc: good on this machine, refused by any other. Said at every
            # build, so nobody ships one by accident.
            codesign --force --sign - --timestamp=none "$APP"
            echo "Built $APP, signed for this machine only."
            echo "Another Mac will refuse it. To make one that travels:"
            echo "  ./build.sh --sign \\"Developer ID Application: Your Name (TEAMID)\\" --notarize <profile>"
        else
            # The hardened runtime and a timestamp are what the notary checks.
            codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
            echo "Built $APP, signed as $IDENTITY."
        fi

        if [ -n "$PROFILE" ]; then
            # One-time setup for the profile named here:
            #   xcrun notarytool store-credentials <profile> \\
            #       --apple-id you@example.com --team-id TEAMID --password <app-specific>
            ditto -c -k --keepParent "$APP" "$NAME.zip"
            xcrun notarytool submit "$NAME.zip" --keychain-profile "$PROFILE" --wait
            xcrun stapler staple "$APP"
            # Re-zipped with the ticket inside, ready to hand over.
            rm -f "$NAME.zip"
            ditto -c -k --keepParent "$APP" "$NAME.zip"
            echo "Notarized and stapled: $APP, with $NAME.zip to hand over."
        fi

        if [ "$INSTALL" = 1 ]; then
            rm -rf "/Applications/$APP"
            cp -R "$APP" /Applications/
            echo "Installed to /Applications/$APP"
        fi
        """
    }

    private static func appReadme(_ request: ProjectRequest, target: String) -> String {
        """
        # \(request.folderName)

        \(request.template.summary)

        An Ollin sketch wrapped as a Mac app, so the piece can be opened with a double click on a machine that has never seen the toolchain.

        ## Making the app

        ```sh
        ./build.sh
        ```

        `\(request.folderName).app` appears beside the script. `./build.sh --install` also puts it in /Applications. The icon is a frame the sketch renders of itself; drop an `AppIcon.icns` of your own beside `build.sh` to replace it, or change the `--frame 120` in the script to pick a different moment.

        ## Working on it

        Rebuilding an app is a slow way to see a change. Open the same sketch in a window instead, where it reloads as you save:

        ```sh
        ollin Sources/\(target)/Sketch.swift
        ```

        The sketch is an ordinary sketch: the window, the mouse, the keyboard, and every export flag work the same inside the app.

        ## Giving it to somebody else

        `build.sh` alone signs the app so this machine will run it. Another machine will refuse it. Traveling takes a paid Apple Developer account, once:

        1. Sign with your Developer ID certificate and send the app to Apple's notary:

           ```sh
           xcrun notarytool store-credentials ollin-notary \\
               --apple-id you@example.com --team-id TEAMID --password <app-specific password>
           ./build.sh --sign "Developer ID Application: Your Name (TEAMID)" --notarize ollin-notary
           ```

           The first command is one-time setup; the password is an app-specific one from appleid.apple.com.

        2. Hand over the `\(request.folderName).zip` the script leaves beside the app. Any Mac will open what is inside.

        Before you do, change `CFBundleIdentifier` in `Info.plist` from `com.example.*` to something of yours.

        ## Where things go

        The sketch and everything it loads live in `Sources/\(target)/`. `Info.plist` is the app's name tag, and `build.sh` is the whole wrapper: the two are self-contained, so they can be copied into any sketch folder of this shape to make an app of it too.
        """
    }

    /// The app folder and the notary zip are built, so they are not kept.
    private static let appGitignore = """
    .build/
    .swiftpm/
    .DS_Store
    *.xcodeproj
    *.app
    *.zip
    """

    // MARK: - The pieces that live in the system

    /// The program for a kind whose sketch does not run itself: one wrapper
    /// file that keeps the shared command-line surface and then hands the
    /// sketch to the host for this surface.
    private static func surfaceMain(target: String, host: String) -> String {
        """
        import Ollin

        // The program around the sketch. The export flags keep working, which
        // is also how build.sh renders the icon from a frame of the piece.
        @main
        enum \(target)Main {
            @MainActor static func main() {
                if OllinApp.handleCommandLine(makeSketch: { \(target)() }) { return }
                \(host)
            }
        }
        """
    }

    private static func wallpaperReadme(_ request: ProjectRequest, target: String) -> String {
        """
        # \(request.folderName)

        \(request.template.summary)

        An Ollin sketch wrapped as the desktop wallpaper: the piece runs across every display, behind the icons, while the machine is used for everything else.

        ## Seeing it

        ```sh
        swift run \(target)
        ```

        The desktop becomes the piece. The sparkle at the right end of the menu bar is the way out: click it and pick Quit.

        ## Making the app

        ```sh
        ./build.sh
        ```

        `\(request.folderName).app` appears beside the script, signed for this machine. `./build.sh --install` also puts it in /Applications. To have the piece start with the machine, add the app under System Settings, General, Login Items.

        The icon is a frame the sketch renders of itself; drop an `AppIcon.icns` of your own beside `build.sh` to replace it. `build.sh` alone signs for this machine only; `./build.sh --sign "Developer ID Application: Your Name (TEAMID)" --notarize <profile>` makes one that travels, and the script says which of the two it made every time.

        ## Working on it

        Open the same sketch in a window, where it reloads as you save:

        ```sh
        ollin Sources/\(target)/Sketch.swift
        ```

        The sketch declares `.resizable`, so on the desktop `width` and `height` are the display's own, and each display runs a sketch of its own. Give it a `canvasSize` instead to keep fixed proportions, centered on black.

        ## Where things go

        The sketch and everything it loads live in `Sources/\(target)/`. `Main.swift` is the whole program: it hands the sketch to the wallpaper host. `Info.plist` and `build.sh` are the same self-contained wrapper the Mac app kind writes, plus the one line that keeps the app out of the Dock.
        """
    }

    private static func menuBarReadme(_ request: ProjectRequest, target: String) -> String {
        """
        # \(request.folderName)

        \(request.template.summary)

        An Ollin sketch wrapped as a menu-bar piece: a small live strip among the status items, on screen for the whole working day.

        ## Seeing it

        ```sh
        swift run \(target)
        ```

        The strip appears in the menu bar. A click on it opens its menu, and Quit is the way out.

        ## The strip

        The strip is 56 points wide and draws at 30 frames a second, a rate a surface that never goes away can afford. Change the width where `Main.swift` hands the sketch over:

        ```swift
        OllinApp.runInMenuBar(width: 90) { \(target)() }
        ```

        The sketch declares `.resizable`, so `width` and `height` are the strip's own few points. Give it a `canvasSize` instead to fit fixed proportions into the strip.

        ## Making the app

        ```sh
        ./build.sh
        ```

        `\(request.folderName).app` appears beside the script, signed for this machine. `./build.sh --install` also puts it in /Applications. To have the piece start with the machine, add the app under System Settings, General, Login Items. `--sign` and `--notarize` make one that travels, exactly as the Mac app kind does.

        ## Working on it

        Open the same sketch in a window, where it reloads as you save:

        ```sh
        ollin Sources/\(target)/Sketch.swift
        ```

        ## Where things go

        The sketch and everything it loads live in `Sources/\(target)/`. `Main.swift` is the whole program: it hands the sketch to the menu-bar host. `Info.plist` and `build.sh` are the same self-contained wrapper the Mac app kind writes, plus the one line that keeps the app out of the Dock.
        """
    }

    // MARK: - The screen saver's own files

    /// The class the system asks for by name.
    ///
    /// `@objc` pins the name, because a plug-in is read through the Objective-C
    /// runtime and Swift would otherwise decorate it into something the property
    /// list cannot spell. `Foundation` is imported for that attribute alone.
    private static func saverViewSource(target: String, saverClass: String) -> String {
        """
        import Foundation
        import Ollin

        // The system loads this plug-in, asks for the class named in Info.plist,
        // and puts it on the screen. Everything else is the sketch next door.
        //
        // Keep the `@objc` name and the `NSPrincipalClass` line in Info.plist the
        // same, or the saver loads and shows nothing.
        @objc(\(saverClass))
        final class \(saverClass): SketchSaverView {
            override func makeSketch() -> Sketch { \(target)() }
        }
        """
    }

    /// The manifest for a plug-in: a dynamic library, linked as a bundle.
    ///
    /// `-bundle` is what makes the binary the kind the system can load. The flag
    /// is unsafe in the package manager's sense, which only bars a package from
    /// being somebody else's dependency, and a screen saver is nobody's
    /// dependency.
    private static func saverManifest(_ request: ProjectRequest, target: String,
                                      resources: [String]) -> String {
        let products = productLines(request)
        let resourceLine = resourceLine(resources)

        return """
        // swift-tools-version: 6.0
        import PackageDescription

        // \(request.folderName): an Ollin sketch, wrapped as a screen saver.
        //
        // Build and install it:  ./build.sh --install
        //
        // The product is a *dynamic* library handed `-bundle`, which is the Mach-O
        // kind the system loads a screen saver from. `build.sh` puts the .saver
        // folder around what this builds.
        let package = Package(
            name: "\(target)",
            platforms: [
                .macOS("26.0")
            ],
            products: [
                .library(name: "\(target)", type: .dynamic, targets: ["\(target)"]),
            ],
            dependencies: [
                \(request.framework.manifestEntry),
            ],
            targets: [
                .target(
                    name: "\(target)",
                    dependencies: [
        \(products)
                    ],
                    path: "Sources/\(target)"\(resourceLine),
                    linkerSettings: [
                        .unsafeFlags(["-Xlinker", "-bundle"]),
                    ]
                ),
            ],
            swiftLanguageModes: [.v6]
        )
        """
    }

    private static func saverInfoPlist(_ request: ProjectRequest, target: String,
                                       saverClass: String) -> String {
        let identifier = "com.example.\(target.lowercased())"
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleDevelopmentRegion</key>
            <string>en</string>
            <key>CFBundleExecutable</key>
            <string>\(target)</string>
            <!-- Yours to change before you hand this to anybody. Two savers with
                 one identifier are one saver as far as the system is concerned. -->
            <key>CFBundleIdentifier</key>
            <string>\(identifier)</string>
            <key>CFBundleInfoDictionaryVersion</key>
            <string>6.0</string>
            <!-- The name in the System Settings list. -->
            <key>CFBundleName</key>
            <string>\(request.folderName)</string>
            <key>CFBundlePackageType</key>
            <string>BNDL</string>
            <key>CFBundleShortVersionString</key>
            <string>1.0</string>
            <key>CFBundleVersion</key>
            <string>1</string>
            <key>LSMinimumSystemVersion</key>
            <string>26.0</string>
            <!-- The class the system asks for. Same name as the `@objc` one in
                 Sources/\(target)/SaverView.swift. -->
            <key>NSPrincipalClass</key>
            <string>\(saverClass)</string>
        </dict>
        </plist>
        """
    }

    private static func saverBuildScript(_ request: ProjectRequest, target: String) -> String {
        """
        #!/bin/sh
        # Build the sketch and put the .saver folder around it.
        #
        #   ./build.sh              build it here
        #   ./build.sh --install    build it and put it on this machine
        #
        set -e
        cd "$(dirname "$0")"

        NAME="\(request.folderName)"
        TARGET="\(target)"
        SAVER="$NAME.saver"

        swift build -c release
        # Asked for, not assumed: the two build systems the toolchain ships put
        # the binary in different places.
        BIN="$(swift build -c release --show-bin-path)"

        rm -rf "$SAVER"
        mkdir -p "$SAVER/Contents/MacOS" "$SAVER/Contents/Resources"
        cp "$BIN/lib$TARGET.dylib" "$SAVER/Contents/MacOS/$TARGET"
        cp Info.plist "$SAVER/Contents/Info.plist"

        # The framework's own files: shader segments, fonts, tables. They are
        # looked for beside the running program, and the running program here
        # belongs to the system, so they travel inside the saver instead.
        for bundle in "$BIN"/*.bundle; do
            [ -e "$bundle" ] || continue
            cp -R "$bundle" "$SAVER/Contents/Resources/"
        done

        # Unsigned, the system refuses to load it. This signature is good on this
        # machine; handing it to somebody else needs a Developer ID and a trip
        # through notarization.
        codesign --force --sign - --timestamp=none "$SAVER"
        echo "Built $SAVER"

        if [ "$1" = "--install" ]; then
            DEST="$HOME/Library/Screen Savers"
            mkdir -p "$DEST"
            rm -rf "$DEST/$SAVER"
            cp -R "$SAVER" "$DEST/"
            # The host process keeps the old copy loaded until it is told to go.
            killall legacyScreenSaver 2>/dev/null || true
            killall ScreenSaverEngine 2>/dev/null || true
            echo "Installed to $DEST/$SAVER"
            echo "Pick it in System Settings, under Screen Saver."
        fi
        """
    }

    private static func saverReadme(_ request: ProjectRequest, target: String) -> String {
        """
        # \(request.folderName)

        \(request.template.summary)

        An Ollin sketch wrapped as a screen saver, so it runs when the machine is left alone.

        ## Putting it on this machine

        ```sh
        ./build.sh --install
        ```

        Then open System Settings, go to Screen Saver, and pick **\(request.folderName)** from the list. Run `./build.sh --install` again after every edit; the script tells the host process to let go of the old copy for you.

        ## Working on it

        A screen saver is a slow way to see a change. Open the same sketch in a window instead, where it reloads as you save:

        ```sh
        ollin Sources/\(target)/Sketch.swift
        ```

        The sketch is an ordinary sketch. Everything you would write in a window works here, with two differences the setting makes necessary:

        - **It gets no input.** A key or a click ends a screen saver, so the sketch never sees either. `mouseX`, `mouseY`, and `key` stay where they started.
        - **It fills the display.** The sketch declares `windowMode` as `.resizable`, so `width` and `height` are the screen's. Take that line out and the canvas keeps its own proportions instead, centered on black.

        ## Giving it to somebody else

        `build.sh` signs the saver so this machine will load it. Another machine will not: for that it needs a Developer ID signature and a trip through notarization. Until then, `\(request.folderName).saver` is yours alone.

        ## Where things go

        The sketch and everything it loads live in `Sources/\(target)/`. `SaverView.swift` is the small class the system asks for by name, and `Info.plist` is where that name is written down. The two have to agree.
        """
    }

    /// The saver folder is built, so it is not kept.
    private static let saverGitignore = """
    .build/
    .swiftpm/
    .DS_Store
    *.xcodeproj
    *.saver
    """

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

        Each export records the seed and the parameter values it used, so a picture you like can be made again.

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
