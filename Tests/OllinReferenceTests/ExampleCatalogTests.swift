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
        | [![Breathing](https://media.example/Breathing/still.jpg)](Breathing/) | [![PointCloud](https://media.example/PointCloud/still.jpg)](Geometry/PointCloud/) |
        |---|---|
        | [Breathing](Breathing/) | [PointCloud](Geometry/PointCloud/) |

        | Example | What it shows |
        |---|---|
        | [Breathing](Breathing/Sketch.swift) | the same circle, animated via `time` |
        | [PointCloud](Geometry/PointCloud/) | a rippling heightfield as a point cloud |
        | not a row |
        """
        let rows = ExampleCatalog.rows(listing)
        #expect(rows.count == 2, "the grid's picture row and its name row describe nothing")
        #expect(rows[0].target == "Breathing/Sketch.swift")
        #expect(rows[0].summary == "the same circle, animated via time", "the markers come off")
        #expect(rows[1].target == "Geometry/PointCloud/")
    }

    @Test("A row of nothing but links is the grid naming its pictures, not a description")
    func linkRows() {
        #expect(ExampleCatalog.isOnlyLinks(" [A](A/) | [B](B/) | "))
        #expect(ExampleCatalog.isOnlyLinks(" [A](A/) |  |  "), "a short last row pads with empty cells")
        #expect(!ExampleCatalog.isOnlyLinks(" a circle, see [A](A/) for the rest "))
        #expect(!ExampleCatalog.isOnlyLinks(" a rippling heightfield "))
    }

    @Test("The sketch's own comment is read as its header, and a credit is told from a note")
    func headers() {
        let credited = """
        import Ollin
        import OllinVision

        // Inspired by Harley Turan, "Complex Number Visualization in GLSL"
        //   https://hturan.com/writing/complex-numbers-glsl (April 2022)
        // An original sketch written from that idea; credited here as a homage.

        /// The picture.
        @main
        final class Example: Sketch {}
        """
        let header = ExampleCatalog.header(in: credited)
        #expect(header.split(separator: "\n").count == 3)
        #expect(header.hasPrefix("Inspired by Harley Turan"))
        #expect(header.contains("hturan.com"), "the address is kept whole, so it can be searched")
        #expect(!header.contains("The picture"), "the documentation comment is not the header")
        #expect(Self.entry("Shaders/Meromorphic", "", header: header).credit == "Inspired by Harley Turan, \"Complex Number Visualization in GLSL\"")

        let noted = """
        import Ollin

        // A raymarched scene: the SDF is evaluated on the GPU.
        // Try the other blend modes.

        /// Doc.
        final class Example: Sketch {}
        """
        #expect(ExampleCatalog.header(in: noted).hasPrefix("A raymarched scene"))
        #expect(Self.entry("3D/Scene", "", header: ExampleCatalog.header(in: noted)).credit == nil,
                "a note of the sketch's own is searchable but is not printed as a credit")

        let bare = """
        import Ollin

        /// Doc.
        final class Example: Sketch {}
        """
        #expect(ExampleCatalog.header(in: bare).isEmpty)
    }

    // MARK: - Against the repository

    /// Every example in this checkout, enumerated once for the suite.
    static let checkoutEntries: [ExampleEntry]? = ReferenceCatalogTests.repositoryRoot().map {
        ExampleCatalog.entries(inExamples: $0.appendingPathComponent("Examples"))
    }

    @Test("Every example in this checkout is found, named, and described")
    func realExamples() throws {
        let entries = try #require(Self.checkoutEntries)

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

    @Test("Every description is the sketch's own words, never its neighbors' names")
    func ownWords() throws {
        let entries = try #require(Self.checkoutEntries)
        let names = Set(entries.map(\.name))
        var borrowed: [String] = []
        for entry in entries {
            // A description lifted off the picture grid's name row reads as
            // `A | B | C`: sibling names and bars and nothing else.
            let words = entry.summary.split { $0 == "|" || $0 == " " }.map(String.init)
            let onlyNames = !words.isEmpty && words.allSatisfy { names.contains($0) }
            if entry.summary.contains("|") || onlyNames { borrowed.append("\(entry.path): \(entry.summary)") }
        }
        #expect(borrowed.isEmpty, "described by their neighbors: \(borrowed.joined(separator: "; "))")

        // The two the grid had renamed, read back as themselves.
        let log = try #require(entries.first { $0.path == "Shaders/ImaginaryLog" })
        #expect(log.summary.hasPrefix("the imaginary part of a logarithm"))
        let clone = try #require(entries.first { $0.path == "Effects/SeamlessClone" })
        #expect(!clone.summary.hasPrefix("SoapFilm"))
    }

    @Test("A sketch's header credit is read from its source")
    func realHeaders() throws {
        let entries = try #require(Self.checkoutEntries)
        let plane = try #require(entries.first { $0.path == "Shaders/ComplexPlane" })
        #expect(plane.header.hasPrefix("Inspired by Harley Turan"))
        #expect(plane.credit?.hasPrefix("Inspired by") == true)
        let escape = try #require(entries.first { $0.path == "Effects/EscapeTime" })
        #expect(escape.credit == nil, "a sketch whose file opens on its documentation has no header")
    }

    @Test("Every example target the catalog names is one the package declares")
    func targetNames() throws {
        let root = try #require(ReferenceCatalogTests.repositoryRoot())
        let entries = try #require(Self.checkoutEntries)
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
        entry("Shaders/ComplexPlane", "the shader library's complex module beside the CPU value"),
        entry("Shaders/Meromorphic", "a ratio of two cubics built from six roots that move as Complex values",
              header: "Inspired by Harley Turan, \"Complex Number Visualization in GLSL\"\n  https://hturan.com/writing/complex-numbers-glsl"),
    ]

    static func entry(_ path: String, _ summary: String, header: String = "") -> ExampleEntry {
        ExampleEntry(path: path,
                     directory: URL(fileURLWithPath: "/dev/null"),
                     summary: summary,
                     modules: [],
                     resources: [],
                     header: header)
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

    @Test("A name that fits one sketch does not hide the ones whose descriptions say it")
    func nameBesideDescription() {
        let hits = ExampleCatalog.matches("complex", in: Self.sample).map(\.path)
        #expect(hits == ["Shaders/ComplexPlane", "Shaders/Meromorphic"],
                "the one named for the word first, then the one described by it")
        #expect(ExampleCatalog.matches("ocean", in: Self.sample).count == 1,
                "an exact name still answers alone")
    }

    @Test("The author a sketch credits finds it")
    func byCredit() {
        #expect(ExampleCatalog.matches("turan", in: Self.sample).map(\.path) == ["Shaders/Meromorphic"])
        #expect(ExampleCatalog.matches("hturan.com", in: Self.sample).count == 1)
    }

    @Test("In this checkout, complex finds the meromorphic sketch and the article's author finds three")
    func realSearches() throws {
        let entries = try #require(Self.checkoutEntries)
        let complex = ExampleCatalog.matches("complex", in: entries).map(\.path)
        #expect(complex.first == "Shaders/ComplexPlane")
        #expect(complex.contains("Shaders/Meromorphic"), "found through its description")
        let turan = Set(ExampleCatalog.matches("turan", in: entries).map(\.path))
        #expect(turan == ["Shaders/ComplexPlane", "Shaders/ImaginaryLog", "Shaders/Meromorphic"])
    }
}
