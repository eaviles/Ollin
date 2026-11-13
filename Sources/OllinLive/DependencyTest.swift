import Foundation
import ImageIO
import Ollin
import OllinRuntime

/// The phases of `--selftest` for a sketch that imports more than the
/// framework: another target of its own package, a package named by a path,
/// and a package SwiftPM fetches.
///
/// The project is a sketch target `Garden` that imports the library target
/// `Petals`, which imports `Leaf` from a second package beside it. Each file
/// is saved in turn, and the phase reads three things after every save: the
/// picture, how many dependencies were compiled to get it, and a count the
/// library keeps in a stored global, which says whether the library the
/// sketch found is the one already in the process or a new one. The library
/// also hands the sketch a value of the framework's own type, and the count
/// reads wrong if the two do not hold the same framework.
enum DependencyTest {
    /// The seconds each kind of compile took, for the self-test's last line.
    struct Report {
        var first = 0.0
        var sketchSave = 0.0
        var librarySave = 0.0
        var fetched = 0.0
    }

    @MainActor
    static func run(in dir: String) -> Report {
        let fm = FileManager.default
        let root = (dir as NSString).appendingPathComponent("Dependencies")
        try? fm.removeItem(atPath: root)
        let garden = (root as NSString).appendingPathComponent("Garden")
        let leaf = (root as NSString).appendingPathComponent("Leaf")
        let stem = (root as NSString).appendingPathComponent("Stem")

        func write(_ text: String, _ path: String) {
            try! fm.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                    withIntermediateDirectories: true)
            try! text.write(toFile: path, atomically: true, encoding: .utf8)
        }
        func inGarden(_ relative: String) -> String { (garden as NSString).appendingPathComponent(relative) }

        // The manifest, with whatever a phase adds to it.
        func writeManifest(packages: String = "", targets: String = "", gardenNeeds: String = "") {
            write("""
            // swift-tools-version: 6.0
            import PackageDescription
            let package = Package(
                name: "Garden",
                dependencies: [.package(path: "../Leaf"), \(packages)],
                targets: [
                    .target(name: "Petals", dependencies: [.product(name: "Leaf", package: "Leaf")]),
                    .executableTarget(name: "Garden", dependencies: ["Petals", \(gardenNeeds)]),
                    \(targets)
                ])
            """, inGarden("Package.swift"))
        }
        func writeLeaf(shift: Int) {
            write("public func leafShift() -> Double { \(shift) }\n",
                  (leaf as NSString).appendingPathComponent("Sources/Leaf/Leaf.swift"))
        }
        func writePetals(radius: Int) {
            write("""
            import Leaf
            import Ollin

            /// How many times a sketch has set itself up against this library.
            /// Marked `package`, which the sketch's target reads only when
            /// both compile under their package's name.
            package enum Tally {
                package nonisolated(unsafe) static var loads = 0
            }

            /// Where the petal goes: a value of the framework's own type,
            /// built here and handed over behind `Any`. Building it names a
            /// symbol of the framework's that this library's link has to
            /// leave to the host, and the cast on the other side holds only
            /// when the library and the sketch know one `Vector2`.
            public func petalCenter(width: Double, height: Double) -> Any {
                Vector2(width / 2 + leafShift(), height / 2)
            }

            extension Sketch {
                public func drawPetal() {
                    guard let center = petalCenter(width: width, height: height) as? Vector2 else { return }
                    drawCircle(center: center, radius: \(radius))
                }
            }
            """, inGarden("Sources/Petals/Petals.swift"))
        }
        let sketchFile = inGarden("Sources/Garden/Sketch.swift")
        func writeSketch(mark: Bool, extra: String = "", imports: String = "") {
            write("""
            import Ollin
            import Petals
            \(imports)
            @main
            final class Garden: Sketch {
                override var title: String {
                    let shared = petalCenter(width: 1, height: 1) is Vector2
                    return "loads \\(Tally.loads)" + (shared ? "" : ", and a second framework")
                }
                override func setup() { Tally.loads += 1 }
                override func draw() {
                    background(.white)
                    fill(.black)
                    noStroke()
                    drawPetal()
                    \(mark ? "drawRect(40, 40, 120, 120)" : "")
                    \(extra)
                }
            }
            """, sketchFile)
        }

        write("""
        // swift-tools-version: 6.0
        import PackageDescription
        let package = Package(
            name: "Leaf",
            products: [.library(name: "Leaf", targets: ["Leaf"])],
            targets: [.target(name: "Leaf")])
        """, (leaf as NSString).appendingPathComponent("Package.swift"))
        writeManifest()
        writeLeaf(shift: 0)
        writePetals(radius: 40)
        writeSketch(mark: false)

        let loader = SketchLoader(sketchPath: sketchFile, scope: .target)
        var renders = 0
        /// Compile, load, and render; the picture, the library's count as the
        /// sketch reads it, and the seconds the compile took.
        func render() -> (pixels: Data, loads: String, seconds: Double) {
            renders += 1
            let path = (root as NSString).appendingPathComponent("frame-\(renders).png")
            let started = Date()
            let dylib: String
            switch loader.compile() {
            case .success(let built): dylib = built
            case .failure(let error): fail("render \(renders) did not compile: \(error)")
            }
            let seconds = Date().timeIntervalSince(started)
            switch loader.instantiate(dylibPath: dylib) {
            case .success(let sketch):
                do { try OllinApp.export(sketch, to: path) } catch { fail("render \(renders): \(error)") }
                guard let decoded = pixels(path) else { fail("could not decode render \(renders)") }
                return (decoded, sketch.title, seconds)
            case .failure(let error):
                fail("render \(renders) did not load: \(error)")
            }
        }
        func expect(_ compiles: Int, _ what: String) {
            let counted = SketchLoader.dependencyCompileCount
            guard counted == compiles else {
                fail("\(what): \(counted) dependencies compiled so far, expected \(compiles)")
            }
        }
        var report = Report()

        print("OllinLive selftest: a sketch that imports another target, which imports another package …")
        let first = render()
        report.first = first.seconds
        expect(2, "the first compile builds the library and the package under it")
        guard first.loads == "loads 1" else { fail("the first run read \(first.loads)") }

        print("OllinLive selftest: a save to the sketch compiles the sketch alone …")
        writeSketch(mark: true)
        let marked = render()
        report.sketchSave = marked.seconds
        guard marked.pixels != first.pixels else { fail("the edit to the sketch did not reach the render") }
        expect(2, "a save to the sketch")
        // The library is the one already in the process, so its stored
        // count went on from where the first run left it.
        guard marked.loads == "loads 2" else {
            fail("after a save to the sketch the library's count read \(marked.loads), expected "
                + "the kept library's 2")
        }

        print("OllinLive selftest: a save to the library rebuilds it and the sketch …")
        writePetals(radius: 240)
        let grown = render()
        report.librarySave = grown.seconds
        guard grown.pixels != marked.pixels else { fail("the edit to the library did not reach the render") }
        expect(3, "a save to the library rebuilds it and not the package under it")
        guard grown.loads == "loads 1" else {
            fail("after a save to the library its count read \(grown.loads), expected a fresh 1")
        }

        print("OllinLive selftest: a save to the package under it rebuilds everything above …")
        writeLeaf(shift: 200)
        let shifted = render()
        guard shifted.pixels != grown.pixels else { fail("the edit to the other package did not reach the render") }
        expect(5, "a save to the package rebuilds it and the library that imports it")

        print("OllinLive selftest: text a build was already made from is not compiled again …")
        writeLeaf(shift: 0)
        let back = render()
        guard back.pixels == grown.pixels else { fail("the reverted package rendered a different picture") }
        expect(5, "a reverted file finds the build made from that text")
        guard back.loads == "loads 2" else {
            fail("the reverted project found a library whose count read \(back.loads), expected the "
                + "earlier build's 2")
        }

        print("OllinLive selftest: the folders watched are the sketch's and its dependencies' …")
        let watched = Set(loader.watchFolders())
        let expected = Set([inGarden("Sources/Garden"), inGarden("Sources/Petals"),
                            (leaf as NSString).appendingPathComponent("Sources/Leaf")]
            .map(SketchTarget.resolved))
        guard watched == expected else { fail("the watch covers \(watched.sorted()), expected \(expected.sorted())") }

        print("OllinLive selftest: the sketch's file alone still cannot find the library …")
        switch SketchLoader(sketchPath: sketchFile).compile() {
        case .success:
            fail("the sketch compiled without its library, so the phase proves nothing")
        case .failure(let error):
            guard "\(error)".contains("no such module 'Petals'") else {
                fail("the file-alone compile failed for another reason: \(error)")
            }
        }

        print("OllinLive selftest: a framework rebuilt since launch still refuses the load …")
        var rebuilt = loader
        rebuilt.launchedAt = .distantPast
        switch rebuilt.compile() {
        case .success:
            fail("a sketch with a dependency compiled against a framework newer than the host")
        case .failure(let error):
            guard case .frameworkRebuilt = error else {
                fail("the compile after a rebuild failed for another reason: \(error)")
            }
        }

        print("OllinLive selftest: a dependency with C in it is refused by name …")
        write("int shim(void) { return 1; }\n", inGarden("Sources/Shim/shim.c"))
        write("int shim(void);\n", inGarden("Sources/Shim/include/shim.h"))
        writeManifest(targets: ".target(name: \"Shim\"),", gardenNeeds: "\"Shim\"")
        switch loader.compile() {
        case .success:
            fail("a sketch that depends on a C target compiled")
        case .failure(let error):
            guard case .dependencyUnbuildable(let sentence) = error,
                  sentence.contains("The target Shim holds shim.c"), sentence.contains("swift run") else {
                fail("the C target was refused in other words: \(error)")
            }
        }
        expect(5, "a refusal compiles nothing")
        try? fm.removeItem(atPath: inGarden("Sources/Shim"))

        print("OllinLive selftest: a package SwiftPM fetches is found where it was checked out …")
        write("""
        // swift-tools-version: 6.0
        import PackageDescription
        let package = Package(
            name: "Stem",
            products: [.library(name: "Stem", targets: ["Stem"])],
            targets: [.target(name: "Stem")])
        """, (stem as NSString).appendingPathComponent("Package.swift"))
        write("public func stemLength() -> Double { 300 }\n",
              (stem as NSString).appendingPathComponent("Sources/Stem/Stem.swift"))
        for arguments in [
            ["init", "--quiet", "--initial-branch", "main"], ["add", "."],
            ["commit", "--quiet", "-m", "A stem"], ["tag", "-a", "1.0.0", "-m", "1.0.0"],
        ] {
            let status = git(arguments, in: stem)
            guard status == 0 else { fail("git \(arguments.joined(separator: " ")) exited \(status)") }
        }
        writeManifest(packages: ".package(url: \"file://\(stem)\", exact: \"1.0.0\"),",
                      gardenNeeds: ".product(name: \"Stem\", package: \"Stem\")")
        writeSketch(mark: true, extra: "drawRect(40, 400, stemLength(), 20)", imports: "import Stem")
        let fetched = render()
        report.fetched = fetched.seconds
        guard fetched.pixels != back.pixels else { fail("the fetched package did not reach the render") }
        expect(6, "the fetched package is one more build")
        let checkout = SketchTarget.resolved(inGarden(".build/checkouts/Stem"))
        guard fm.fileExists(atPath: (checkout as NSString).appendingPathComponent("Package.swift")) else {
            fail("the package was not fetched into the project's build folder")
        }
        guard !loader.watchFolders().contains(where: { $0.hasPrefix(checkout) }) else {
            fail("the watch covers a checkout in the build folder")
        }
        return report
    }

    private static func git(_ arguments: [String], in folder: String) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        // An identity of its own and no signing, so the commit and the tag
        // do not depend on how git is set up on this machine.
        process.arguments = [
            "git", "-C", folder,
            "-c", "user.name=Ollin", "-c", "user.email=selftest@ollin.invalid",
            "-c", "commit.gpgSign=false", "-c", "tag.gpgSign=false",
        ] + arguments
        process.standardOutput = FileHandle.nullDevice
        do { try process.run() } catch { return -1 }
        process.waitUntilExit()
        return process.terminationStatus
    }

    private static func pixels(_ path: String) -> Data? {
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let data = image.dataProvider?.data else { return nil }
        return data as Data
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("OllinLive selftest: FAIL: \(message)\n".utf8))
        exit(1)
    }
}
