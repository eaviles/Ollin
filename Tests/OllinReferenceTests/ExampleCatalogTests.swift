import Foundation
import Testing
@testable import OllinReference

/// The examples set as the reference talks about it: which sketches exist,
/// what each category's listing says about them, and which one somebody meant.
@Suite("The examples catalog")
struct ExampleCatalogTests {

    // MARK: - Reading a listing

    @Test("A row is read whether it links at the sketch or at its folder")
    func rowForms() {
        let listing = """
        | Example | What it shows |
        |---|---|
        | [Breathing](Breathing/Sketch.swift) | the same circle, animated via `time` |
        | [PointCloud](Geometry/PointCloud/) | a rippling heightfield as a point cloud |
        | not a row |
        """
        let rows = ExampleCatalog.rows(listing)
        #expect(rows.count == 2)
        #expect(rows[0].target == "Breathing/Sketch.swift")
        #expect(rows[0].summary == "the same circle, animated via time", "the markers come off")
        #expect(rows[1].target == "Geometry/PointCloud/")
    }

    // MARK: - Against the repository

    @Test("Every example in this checkout is found, named, and described")
    func realExamples() throws {
        let root = try #require(ReferenceCatalogTests.repositoryRoot())
        let entries = ExampleCatalog.entries(inExamples: root.appendingPathComponent("Examples"))

        #expect(entries.count > 100, "found \(entries.count) examples")

        let named = try #require(entries.first { $0.path == "Motion/SineSweep" })
        #expect(named.target == "Example-Motion-SineSweep")
        #expect(named.group == "Motion")
        #expect(!named.summary.isEmpty, "its category listing says nothing about it")
        #expect(FileManager.default.fileExists(atPath: named.sketch.path))

        // A grouped category files its sketches one level deeper, and both the
        // target name and the listing have to follow the folder down.
        let deep = try #require(entries.first { $0.path == "3D/Geometry/Ocean" })
        #expect(deep.target == "Example-3D-Geometry-Ocean")
        #expect(deep.group == "3D/Geometry")
        #expect(!deep.summary.isEmpty)

        // The listings are what a reader is handed, so a sketch missing from
        // its category's table is a sketch nobody can find by browsing.
        let quiet = entries.filter(\.summary.isEmpty).map(\.path)
        #expect(quiet.isEmpty, "not in their category listing: \(quiet.joined(separator: ", "))")
    }

    @Test("Every example target the catalog names is one the package declares")
    func targetNames() throws {
        let root = try #require(ReferenceCatalogTests.repositoryRoot())
        let entries = ExampleCatalog.entries(inExamples: root.appendingPathComponent("Examples"))
        let manifest = try String(contentsOf: root.appendingPathComponent("Examples/Package.swift"),
                                  encoding: .utf8)
        // The manifest names a target by its folder, so the printed run
        // command is checked against the folder the manifest lists.
        for entry in entries {
            #expect(manifest.contains("\"\(entry.path)\""),
                    "\(entry.path) is not declared in Examples/Package.swift")
        }
    }

    // MARK: - Finding one

    static let sample: [ExampleEntry] = [
        entry("3D/Geometry/Ocean", "a sea built from its own wave spectrum"),
        entry("Motion/Breathing", "the same circle, animated via time"),
        entry("Patterns/Flocking", "boids steering in a flock"),
        entry("Simulation/Fluid", "water sloshing in a box"),
    ]

    static func entry(_ path: String, _ summary: String) -> ExampleEntry {
        ExampleEntry(path: path,
                     directory: URL(fileURLWithPath: "/dev/null"),
                     summary: summary,
                     modules: [],
                     resources: [])
    }

    @Test("A name finds its sketch, however it is spelled")
    func byName() {
        #expect(ExampleCatalog.matches("ocean", in: Self.sample).map(\.path) == ["3D/Geometry/Ocean"])
        #expect(ExampleCatalog.matches("3D/Geometry/Ocean", in: Self.sample).count == 1)
        #expect(ExampleCatalog.matches("Example-3D-Geometry-Ocean", in: Self.sample).count == 1,
                "the target name is what a run command shows, so it has to work too")
    }

    @Test("A folder finds everything in it")
    func byFolder() {
        #expect(ExampleCatalog.matches("3D", in: Self.sample).count == 1)
        #expect(ExampleCatalog.matches("motion", in: Self.sample).count == 1)
    }

    @Test("A description finds a sketch whose name gives nothing away")
    func byDescription() {
        #expect(ExampleCatalog.matches("boids", in: Self.sample).map(\.path) == ["Patterns/Flocking"])
        #expect(ExampleCatalog.matches("sloshing", in: Self.sample).map(\.path) == ["Simulation/Fluid"])
    }

    @Test("A word nothing carries returns nothing rather than everything")
    func nothing() {
        #expect(ExampleCatalog.matches("banana", in: Self.sample).isEmpty)
    }
}
