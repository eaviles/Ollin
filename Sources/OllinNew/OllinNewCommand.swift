import Foundation
import OllinProjects

/// The command-line face of the project generator, behind `ollin new`.
///
/// One generator serves the terminal and the window alike: everything here is
/// argument reading and printing, and the files themselves come from
/// `ProjectGenerator.plan`.
///
///     ollin new Dots.swift                 one loose file, as this has always done
///     ollin new MyPiece                    a folder that builds and runs
///     ollin new MyPiece --template shader --with audio
///     ollin new --list                     what can be made
@main
enum OllinNewCommand {

    static func main() {
        var arguments = Arguments(Array(CommandLine.arguments.dropFirst()))

        if arguments.takeFlag("--list") || arguments.takeFlag("-l") {
            printCatalog()
            return
        }
        if arguments.takeFlag("--examples") {
            printExamples()
            return
        }
        if arguments.takeFlag("--3d-options") {
            printThreeDOptions()
            return
        }
        if arguments.takeFlag("--help") || arguments.takeFlag("-h") {
            printUsage()
            return
        }

        let wantsRemote = arguments.takeFlag("--remote")
        let kindName = arguments.takeValue("--kind")
        let templateName = arguments.takeValue("--template")
        let exampleName = arguments.takeValue("--from")
        let capabilityNames = arguments.takeValue("--with")
        let canvasName = arguments.takeValue("--canvas")
        let threeDNames = arguments.takeValue("--3d")
        let destinationPath = arguments.takeValue("--in")
        let frameworkPath = arguments.takeValue("--framework-path")

        if let unknown = arguments.rest.first(where: { $0.hasPrefix("--") }) {
            fail("unknown flag \(unknown). Run `ollin new --list` to see what is available.")
        }
        let destination = URL(fileURLWithPath: destinationPath ?? FileManager.default.currentDirectoryPath)

        // A name ending in .swift asks for one loose file, which is what this
        // command has always made; anything else makes a folder. With no name at
        // all, the next dated serial, so starting something never begins with
        // naming it.
        let typed = arguments.rest.first
        let asksForFile = typed?.hasSuffix(".swift") ?? false
        let name = asksForFile
            ? String(typed!.dropLast(6))
            : typed ?? ProjectNaming.nextSerial(
                in: destination,
                year: Calendar.current.component(.year, from: Date()))

        let host = PackageHost.nearest(from: destination)
        let kind: ProjectKind
        if let kindName {
            guard let found = ProjectKind.named(kindName) else {
                fail("no kind called \(kindName). Run `ollin new --list`.")
            }
            kind = found
        } else if asksForFile {
            kind = .singleFile
        } else if let host, host.linksOllin {
            // A folder already inside a package almost always wants a target in
            // it rather than a package of its own: the framework then builds
            // once for every sketch there instead of once each.
            kind = .inPackage
            print("ollin: \(destination.path) is inside \(host.name), so the sketch joins it. Pass --kind mac-sketch for a project of its own.")
        } else if typed == nil {
            kind = .singleFile
        } else {
            kind = .macSketch
        }

        guard let template = ProjectTemplate.named(templateName ?? "blank") else {
            fail("no template called \(templateName ?? "blank"). Run `ollin new --list`.")
        }

        var capabilities: [Capability] = []
        for id in (capabilityNames ?? "").split(whereSeparator: { $0 == "," || $0 == " " }) {
            guard let capability = Capability.named(String(id)) else {
                fail("nothing called \(id) to wire in. Run `ollin new --list`.")
            }
            capabilities.append(capability)
        }

        guard let canvas = CanvasChoice.named(canvasName ?? "default") else {
            fail("no canvas called \(canvasName ?? "default"). Run `ollin new --list`.")
        }

        let framework: FrameworkSource
        if let frameworkPath {
            framework = .localPath(URL(fileURLWithPath: frameworkPath))
        } else if wantsRemote {
            framework = .remote(url: remoteURL, branch: "main")
        } else if let root = frameworkRoot() {
            framework = .localPath(root)
        } else {
            fail("could not find the Ollin folder from this binary; pass --framework-path <dir> or --remote.")
        }

        // Starting from an example needs the examples folder, which sits beside
        // the framework the manifest is about to point at.
        var example: ExampleSource.Example?
        if let exampleName {
            guard case .localPath(let root) = framework else {
                fail("--from needs the Ollin folder; drop --remote or pass --framework-path <dir>.")
            }
            let folder = root.appendingPathComponent("Examples")
            guard let found = ExampleSource.named(exampleName, in: folder) else {
                fail("no example called \(exampleName). Run `ollin new --examples` to see them.")
            }
            example = found
        }

        // The 3D pieces, checked against each other before anything is written:
        // a combination that cannot work is worth saying so rather than
        // generating a sketch where half the calls quietly do nothing.
        var threeD: ThreeDRecipe?
        if let threeDNames {
            // Read every choice first, then judge the whole thing: checking as
            // they arrive would make the order they were typed in decide whether
            // a perfectly good combination is accepted.
            var geometry: ThreeDOption?
            var finish: ThreeDOption?
            var extras: Set<String> = []
            for id in threeDNames.split(whereSeparator: { $0 == "," || $0 == " " }) {
                guard let option = ThreeDOption.named(String(id)) else {
                    fail("no 3D option called \(id). Run `ollin new --3d-options`.")
                }
                switch option.slot {
                case .geometry: geometry = option
                case .finish: finish = option
                case .extra: extras.insert(option.id)
                }
            }
            let resolvedGeometry = geometry ?? .mesh
            var recipe = ThreeDRecipe(
                geometry: resolvedGeometry,
                // With no finish named, take the first one that suits the
                // geometry, which is the only sensible reading of silence.
                finish: finish ?? ThreeDOption.inSlot(.finish).first {
                    ThreeDRecipe(geometry: resolvedGeometry, finish: $0, extras: []).objections.isEmpty
                } ?? .unlit,
                extras: extras
            )
            if let objection = recipe.objections.first {
                fail("those 3D options do not go together. \(objection)")
            }
            recipe.settle()
            threeD = recipe
        }

        let request = ProjectRequest(
            name: name, kind: kind, template: template, example: example,
            capabilities: capabilities, canvas: canvas, threeD: threeD,
            packageHost: host, destination: destination, framework: framework
        )

        do {
            let project = try ProjectGenerator.plan(request)
            try ProjectGenerator.write(project)

            print("ollin: made \(request.folderName) (\(kind.title.lowercased()), from \(request.startingPointTitle))")
            for file in project.files {
                print("  \(project.root.appendingPathComponent(file.path).path)")
            }
            for edit in project.edits {
                print("  \(edit.file.path)  (\(edit.summary))")
            }
            print("")
            for step in project.nextSteps { print("  \(step)") }
        } catch let error as ProjectGeneratorError {
            fail(error.description)
        } catch {
            fail("\(error)")
        }
    }

    static let remoteURL = "https://github.com/eaviles/Ollin.git"

    // MARK: - Arguments

    /// A tiny reader: flags and their values come out, the rest stays behind.
    struct Arguments {
        private(set) var rest: [String]

        init(_ arguments: [String]) { self.rest = arguments }

        mutating func takeFlag(_ name: String) -> Bool {
            guard let index = rest.firstIndex(of: name) else { return false }
            rest.remove(at: index)
            return true
        }

        mutating func takeValue(_ name: String) -> String? {
            guard let index = rest.firstIndex(of: name), index + 1 < rest.count else { return nil }
            let value = rest[index + 1]
            rest.removeSubrange(index ... index + 1)
            return value
        }
    }

    // MARK: - Finding the framework

    /// Walk up from this binary to the folder it was built in, so a generated
    /// manifest can point at the framework already on this machine.
    static func frameworkRoot() -> URL? {
        var directory = URL(fileURLWithPath: CommandLine.arguments[0])
            .resolvingSymlinksInPath()
            .deletingLastPathComponent()
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

    // MARK: - Printing

    static func printUsage() {
        print("""
        usage: ollin new <name>              a folder that builds and runs
               ollin new <name>.swift        one loose file
               ollin new                     one loose file, named by the next dated serial
               ollin new --list              every kind, template, and extra
               ollin new --examples          every example that can be started from

        options:
          --kind <id>            what to make (default: a target in the package you are
                                 already inside, else mac-sketch, or single-file for a
                                 .swift name)
          --template <id>        which ready-made starting point (default: blank)
          --from <Group/Name>    start from an example instead, material and all
          --with <a,b>           extra libraries and folders to wire in
          --canvas <id>          the canvas size to declare
          --in <dir>             where to put it (default: here)
          --remote               point the manifest at the published framework rather than this folder
          --framework-path <dir> point it at a particular copy of the framework
        """)
    }

    /// Every example that can be started from, grouped the way they are filed.
    static func printExamples() {
        guard let root = frameworkRoot() else {
            fail("could not find the Ollin folder from this binary.")
        }
        let examples = ExampleSource.discover(in: root.appendingPathComponent("Examples"))
        guard !examples.isEmpty else {
            fail("no examples found. Is this a full checkout?")
        }
        var group = ""
        for example in examples {
            if example.group != group {
                group = example.group
                print("\n\(group):")
            }
            let modules = example.modules.isEmpty ? "" : "  [\(example.modules.joined(separator: ", "))]"
            print("    \(example.path)\(modules)")
        }
        print("\nStart from one:  ollin new MyPiece --from \(examples[0].path)")
    }

    /// The 3D pieces and the rule each one carries, since which of them combine
    /// is the thing worth knowing before starting a 3D sketch.
    static func printThreeDOptions() {
        print("3D options (--3d a,b,c), used with `--template 3d`:\n")
        for slot in ThreeDOption.Slot.allCases {
            print("\(slot.title):")
            for option in ThreeDOption.inSlot(slot) {
                print("    \(pad(option.id, 14))\(option.summary)")
                if !option.rule.isEmpty {
                    print("    \(pad("", 14))\(option.rule)")
                }
            }
            print("")
        }
        print("The realism stack:  --template 3d --3d mesh,pbr,environment,shadows,ray-traced,tone-map")
        print("The full map lives in Docs/3D/Combining.md.")
    }

    static func printCatalog() {
        print("Kinds (--kind):")
        for kind in ProjectKind.all {
            print("  \(kind.isAvailable ? " " : "*") \(pad(kind.id, 14))\(kind.summary)")
            if let waiting = kind.waitingOn {
                print("    \(pad("", 14))not yet: \(waiting)")
            }
        }
        print("\n  * not ready yet\n")

        print("Templates (--template):")
        for template in ProjectTemplate.all {
            print("    \(pad(template.id, 14))\(template.summary)")
        }

        print("\nExtras (--with a,b):")
        for capability in Capability.all {
            print("    \(pad(capability.id, 14))\(capability.summary)")
        }

        print("\nCanvas (--canvas):")
        print("    " + CanvasChoice.all.map(\.id).joined(separator: ", "))
    }

    static func pad(_ text: String, _ width: Int) -> String {
        text.count >= width ? text + " " : text + String(repeating: " ", count: width - text.count)
    }

    static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data(("ollin new: " + message + "\n").utf8))
        exit(1)
    }
}
