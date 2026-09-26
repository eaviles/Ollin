import Foundation
import Testing
@testable import OllinReference

/// `ollin api`: reading the listings under `API/`, pairing a declaration with
/// its doc comment in `Sources/`, and finding where the reference and the
/// examples write it. Pure but for the reads of this repository's own folders.
@Suite("The public-surface lookup")
struct APILookupTests {

    static let listing = """
    // Ollin: the public surface.
    struct Light: Equatable
      static func spot(at: Vector3, color: Color = default) -> Light
      enum Kind
        case point
        case tube(length: Double)
      var intensity: Double
    func clamp(_: Double, _: ClosedRange<Double>) -> Double
    @discardableResult func cue(_: Int, over: Double = default) -> Bool
    extension Double
      var tau: Double { get }
    """

    // MARK: - The listing

    @Test("A line belongs to the type it is indented under, and leaves it when the indent does")
    func nesting() throws {
        let all = APIListing.declarations(in: Self.listing, module: "Ollin")
        let byName = Dictionary(all.map { ($0.qualifiedName, $0) }, uniquingKeysWith: { first, _ in first })
        #expect(byName["Light.Kind.point"]?.kind == .enumCase)
        #expect(byName["Light.Kind.tube"]?.kind == .enumCase)
        #expect(byName["Light.intensity"]?.kind == .property)
        #expect(byName["Light.spot"]?.kind == .function)
        #expect(byName["clamp"]?.owner.isEmpty == true)
        #expect(byName["cue"]?.kind == .function)
        #expect(byName["Double.tau"]?.owner == ["Double"])
        #expect(byName["Double"]?.isExtension == true)
        #expect(byName["Light"]?.isExtension == false)
        #expect(!all.contains { $0.text.hasPrefix("//") })
    }

    @Test("Labels come off the argument list, and an unlabeled one reads as an underscore")
    func labels() {
        #expect(APIListing.labels(of: "static func spot(at: Vector3, color: Color = default) -> Light") == ["at", "color"])
        #expect(APIListing.labels(of: "func clamp(_: Double, _: ClosedRange<Double>) -> Double") == ["_", "_"])
        #expect(APIListing.labels(of: "func map(_: (Double, Double) -> Double, over: [Int : Double]) -> Double") == ["_", "over"])
        #expect(APIListing.labels(of: "@available(*, deprecated, renamed: \"x\") func old(to: Int)") == ["to"])
        #expect(APIListing.labels(of: "func shaped<T where T : Shape>(_: T, by: Double)") == ["_", "by"])
        // The source spells a local name after the label; the label is what counts.
        #expect(APIListing.labels(of: "public func drawDot(_ x: Double, at p: Vector2, file: StaticString = #fileID)") == ["_", "at", "file"])
        #expect(APIListing.labels(of: "var radius: Double") == nil)
    }

    @Test("A declaration reads for a person: no source-location plumbing, no system module names")
    func tidy() {
        let written = "func drawCircle(_: Double, _: Double, _: Double, file: StaticString = default, line: Int = default, column: Int = default)"
        #expect(APIListing.tidy(written) == "func drawCircle(_: Double, _: Double, _: Double)")
        #expect(APIListing.tidy("init(url: Foundation.URL, in: Foundation.Bundle)") == "init(url: URL, in: Bundle)")
        #expect(APIListing.tidy("func tint(_: Ollin.Color)") == "func tint(_: Color)")
    }

    // MARK: - Asking by name

    @Test("A name finds every declaration it names, and a dotted one narrows by the type, inside out")
    func answers() {
        let all = APIListing.declarations(in: Self.listing, module: "Ollin")
        #expect(APIListing.answer("point", in: all).declarations.map(\.qualifiedName) == ["Light.Kind.point"])
        #expect(APIListing.answer("Kind.point", in: all).declarations.count == 1)
        #expect(APIListing.answer("Light.Kind.point", in: all).declarations.count == 1)
        #expect(APIListing.answer("Vector3.point", in: all).declarations.isEmpty)
        // The case is forgiven when nothing matches it exactly.
        #expect(APIListing.answer("light.spot", in: all).declarations.map(\.qualifiedName) == ["Light.spot"])
        // An extension adds to a type and is never the answer for it.
        #expect(APIListing.answer("Double", in: all).declarations.isEmpty)
    }

    @Test("A name nothing is called answers with the names spelled like it")
    func nearby() {
        let all = APIListing.declarations(in: Self.listing, module: "Ollin")
        let misspelled = APIListing.answer("intensty", in: all)
        #expect(misspelled.declarations.isEmpty)
        #expect(misspelled.nearby == ["Light.intensity"])
        #expect(APIListing.answer("tens", in: all).nearby == ["Light.intensity"])
        // A name that was found lists the longer names holding it, never a
        // misspelling of it.
        #expect(APIListing.answer("clamp", in: all).nearby.isEmpty)
        #expect(APIListing.distance("bloom", "blom") == 1)
        #expect(APIListing.camelHead("strokeWidth") == "stroke")
        #expect(APIListing.camelHead("URLSession") == "urlsession")
        #expect(APIListing.distance("", "abc") == 3)
    }

    @Test("A bare name that is no sketch call leads with the sketch calls spelled like it")
    func bareCalls() {
        let all = APIListing.declarations(in: """
        open class Sketch: Sendable
          func stroke(_: Color)
          func strokeCap(_: StrokeCap)
          func strokeWeight(_: Double)
          func drawCircle(_: Double, _: Double, _: Double)
        struct Element
          let strokeWidth: Double?
        enum Tip
          case circle
        """, module: "Ollin")
        let width = APIListing.answer("strokeWidth", in: all)
        #expect(width.declarations.map(\.qualifiedName) == ["Element.strokeWidth"])
        #expect(width.bare.first == "strokeWeight")
        #expect(Set(width.bare) == ["strokeWeight", "strokeCap", "stroke"])
        #expect(APIListing.answer("circle", in: all).bare == ["drawCircle"])
        // A sketch call, a type, or a name asked for on a type needs no hint.
        #expect(APIListing.answer("strokeWeight", in: all).bare.isEmpty)
        #expect(APIListing.answer("Element.strokeWidth", in: all).bare.isEmpty)
    }

    // MARK: - The source

    static let source = #"""
    public extension Sketch {
        /// Draws a dot.
        ///
        /// A second paragraph.
        @discardableResult
        func drawDot(_ x: Double, _ y: Double,
                     file: StaticString = #fileID) -> Bool {
            let shader = """
            struct Hidden { float x; }
            {
            """
            let local = 3   // a local { not a member
            return local > 0 && !shader.isEmpty
        }

        /// The labeled one.
        func drawDot(at p: Vector2) -> Bool { true }
    }

    public struct Light {
        /// Where it points.
        public var direction: Vector3
        public enum Kind {
            /// The two small ones.
            case point, spot
        }
        public var after: Int
    }
    """#

    @Test("A declaration pairs by the type it sits in and its labels, and a body's locals are not members")
    func pairing() {
        let written = SourceComments.declarations(in: Self.source)
        let listed = APIListing.declarations(in: """
        extension Sketch
          @discardableResult func drawDot(_: Double, _: Double, file: StaticString = default) -> Bool
          func drawDot(at: Vector2) -> Bool
          var local: Int
        struct Light
          var direction: Vector3
          var after: Int
          enum Kind
            case spot
        """, module: "Ollin")

        func place(_ name: String, labels: [String]? = nil) -> SourceComments.Written? {
            let declaration = listed.first { $0.qualifiedName == name && (labels == nil || $0.labels == labels) }!
            return written.first { SourceComments.pairs(declaration, with: $0) }
        }

        #expect(place("Sketch.drawDot", labels: ["_", "_", "file"])?.comment == ["Draws a dot.", "", "A second paragraph."])
        #expect(place("Sketch.drawDot", labels: ["at"])?.comment == ["The labeled one."])
        #expect(place("Sketch.local") == nil)
        #expect(place("Light.direction")?.comment == ["Where it points."])
        #expect(place("Light.Kind.spot")?.comment == ["The two small ones."])
        // The braces in the shader string and the comment did not unbalance
        // the file: the member after the nested enum is still Light's.
        #expect(place("Light.after") != nil)
        // An extension line never stands in for the type it extends.
        #expect(written.contains { $0.name == "Sketch" && $0.isExtension })
    }

    @Test("Overloads with the same labels are told apart by their parameter types")
    func overloadsByType() {
        let written = SourceComments.declarations(in: """
        public extension Sketch {
            /// Flat.
            func grow(_ amount: Double) {}
            /// In space.
            func grow(_ amount: Vector3, @ViewBuilder then: () -> Void = {}) {}
        }
        """)
        let listed = APIListing.declarations(in: """
        extension Sketch
          func grow(_: Vector3, then: () -> Void = default)
          func grow(_: Double)
        """, module: "Ollin")
        for declaration in listed where declaration.kind == .function {
            let paired = written.filter { SourceComments.pairs(declaration, with: $0) }
            let exact = paired.filter { SourceComments.sameTypes(declaration, $0) }
            #expect(exact.count == 1, "\(declaration.text)")
            #expect(exact.first?.comment == [declaration.text.contains("Vector3") ? "In space." : "Flat."])
        }
        #expect(APIListing.parameterTypes(of: "func f(_ x: inout Foundation.URL, y: [Int] = [1, 2])") == ["URL", "[Int]"])
    }

    @Test("Two declarations the listing writes alike take their own source lines, each with where it sits")
    func constrainedTwins() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ollin-twins-\(UUID().uuidString)")
        let folder = root.appendingPathComponent("Ollin")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try """
        public protocol Named {
            /// What it is called.
            var label: String { get }
        }
        public extension Named {
            var label: String { "unnamed" }
        }
        public final class Knob<Value> {
            public init(value: Value) {}
        }
        public extension Knob where Value: Named {
            /// For a named value.
            convenience init(wrappedValue: Value) { self.init(value: wrappedValue) }
        }
        public extension Knob where Value: CaseIterable {
            /// For a value with cases.
            convenience init(wrappedValue: Value) { self.init(value: wrappedValue) }
        }
        """.write(to: folder.appendingPathComponent("Knob.swift"), atomically: true, encoding: .utf8)
        let listed = APIListing.declarations(in: """
        protocol Named
          var label: String { get }
          var label: String { get }
        final class Knob<Value>
          convenience init(wrappedValue: Value)
          convenience init(wrappedValue: Value)
        """, module: "Ollin").filter { $0.kind != .type }
        let places = SourceComments.places(of: listed, inSources: root)
        #expect(places.count == 4)
        #expect(Set(places.values.map(\.line)).count == 4, "each listing line takes its own declaration")
        #expect(Set(places.values.compactMap(\.constraint)) == ["requirement", "where Value: Named", "where Value: CaseIterable"])
    }

    @Test("A declaration's global actor comes from its own attributes, never from an actor in its parameters")
    func isolation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ollin-actors-\(UUID().uuidString)")
        let folder = root.appendingPathComponent("Ollin")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try """
        /// Drawn on the main thread.
        @MainActor
        public final class Stage {
            public init() {}
            public nonisolated func measure(_ width: Double) -> Double { width }
        }
        public struct Plain {
            public func run(_ body: @MainActor () -> Void) {}
        }
        """.write(to: folder.appendingPathComponent("Stage.swift"), atomically: true, encoding: .utf8)
        let listed = APIListing.declarations(in: """
        final class Stage
          init()
          func measure(_: Double) -> Double
        struct Plain
          func run(_: @MainActor () -> Void)
        """, module: "Ollin")
        let places = SourceComments.places(of: listed, inSources: root)
        func actor(_ name: String) -> String? {
            guard let i = listed.firstIndex(where: { $0.name == name }), let place = places[i] else { return nil }
            return SourceComments.globalActor(at: place)
        }
        #expect(actor("Stage") == "@MainActor")
        #expect(actor("Plain") == nil)
        #expect(actor("run") == nil, "an actor in a parameter's type is not the function's")
        // A member that may run off the main thread says so.
        let measure = try #require(listed.firstIndex { $0.name == "measure" })
        let signature = try #require(places[measure].flatMap { SourceComments.signature(of: listed[measure], at: $0) })
        #expect(signature.hasPrefix("nonisolated func measure("), "\(signature)")
    }

    /// This checkout's public surface, read once for the suite: every listing
    /// under `API/`, which several tests below ask about.
    static let checkout: (root: URL, declarations: [APIDeclaration])? =
        ReferenceCatalogTests.repositoryRoot().map { root in
            (root, APIListing.declarations(inAPI: root.appendingPathComponent("API")))
        }

    /// Every reference page and every example sketch in this checkout, read
    /// once for the suite rather than once per question asked of them.
    static let corpus: UsageCorpus? = ReferenceCatalogTests.repositoryRoot().map { UsageCorpus(root: $0) }

    @Test("Sketch in this checkout reads as main-actor isolated")
    func sketchIsolation() throws {
        let checkout = try #require(Self.checkout)
        let root = checkout.root
        let all = checkout.declarations
        let sketch = try #require(all.first { $0.kind == .type && $0.qualifiedName == "Sketch" && $0.module == "Ollin" })
        let places = SourceComments.places(of: [sketch], inSources: root.appendingPathComponent("Sources"))
        let place = try #require(places[0])
        #expect(SourceComments.globalActor(at: place) == "@MainActor")
    }

    @Test("A type written through its cases counts where a case follows a label that takes it")
    func caseSpellings() {
        let all = APIListing.declarations(in: """
        enum MenuStyle
          case menu
          case segmented
        struct Group
          static func folded(_: String) -> Group
        open class Sketch: Sendable
          func control(style: MenuStyle, group: Group? = default)
        """, module: "Ollin")
        let menu = all.first { $0.name == "MenuStyle" }!
        let group = all.first { $0.name == "Group" }!
        #expect(APIUsage.caseSpellings(of: menu, in: all) == ["style: .menu", "style: .segmented"])
        #expect(APIUsage.caseSpellings(of: group, in: all) == ["group: .folded"])
        #expect(APIUsage.written(["style: .segmented"], in: "@Param(style: .segmented) var look = Look.a"))
        #expect(!APIUsage.written(["style: .segmented"], in: "strokeCap(.round)"))
    }

    @Test("A name is used where code writes it the way it is reached, never inside a longer name or as a label")
    func mentions() {
        #expect(APIUsage.mentions("drawCircle", in: "drawCircle(x, y, 4)", reach: .bare))
        #expect(!APIUsage.mentions("drawCircle", in: "drawCircles(points, radius: 4)", reach: .bare))
        #expect(!APIUsage.mentions("tube", in: "drawTorus(radius: 0.5, tube: 0.3)", reach: .bare))
        #expect(!APIUsage.mentions("tube", in: "drawTorus(radius: 0.5, tube: 0.3)", reach: .member))
        #expect(APIUsage.mentions("tube", in: "let m = Mesh.tube(along: path)", reach: .member))
        #expect(!APIUsage.mentions("rotate", in: "self.rotate(time, axis: .unitY)", reach: .member))
        #expect(APIUsage.mentions("width", in: "drawCircle(width / 2, height / 2, 40)", reach: .bare))
        #expect(APIUsage.mentions("Mesh", in: "let m: Mesh = .sphere()", reach: .type))
        #expect(APIUsage.spans(in: "Call `drawCircle(x, y, r)` or `drawRect`.") == "drawCircle(x, y, r) drawRect")
    }

    // MARK: - This checkout

    @Test("drawCircle in this checkout: its three forms, a page that documents it, and an example")
    func drawCircle() throws {
        let checkout = try #require(Self.checkout)
        let root = checkout.root
        let all = checkout.declarations
        let answer = APIListing.answer("drawCircle", in: all)
        #expect(answer.declarations.count == 3)
        #expect(answer.declarations.allSatisfy { $0.owner == ["Sketch"] && $0.module == "Ollin" })
        let places = SourceComments.places(of: answer.declarations, inSources: root.appendingPathComponent("Sources"))
        #expect(places.count == 3)
        #expect(places.values.allSatisfy { $0.file.lastPathComponent == "Sketch.swift" })
        let corpus = try #require(Self.corpus)
        let pages = APIUsage.pages(naming: "drawCircle", reach: .bare, owners: ["Sketch"], in: corpus)
        #expect(!pages.isEmpty)
        let examples = APIUsage.examples(using: "drawCircle", reach: .bare, in: corpus)
        #expect(examples.count == 3)
        #expect(examples.allSatisfy { $0.place.hasPrefix("Examples/") && $0.text.contains("drawCircle(") })
    }

    @Test("A sketch call shows its source's own parameter names, and is documented where the drawing page names it")
    func rotate() throws {
        let checkout = try #require(Self.checkout)
        let root = checkout.root
        let all = checkout.declarations
        let onSketch = APIListing.answer("Sketch.rotate", in: all).declarations
            .filter { APIListing.labels(of: $0.text) == ["_"] && $0.text.contains("Double") }
        let declaration = try #require(onSketch.first)
        let places = SourceComments.places(of: [declaration], inSources: root.appendingPathComponent("Sources"))
        let place = try #require(places[0])
        let signature = try #require(SourceComments.signature(of: declaration, at: place))
        #expect(signature.contains("radians"), "\(signature)")
        #expect(!signature.hasPrefix("public"))
        #expect(!signature.contains("{"))
        let corpus = try #require(Self.corpus)
        let pages = APIUsage.pages(naming: "rotate", reach: .bare, owners: [], in: corpus)
        #expect(pages.first?.place == "Drawing/Drawing", "\(pages.map(\.address))")
    }

    @Test("A type's page is the one that writes it most, not one with a section on binding it")
    func typePages() throws {
        let corpus = try #require(Self.corpus)
        let pages = APIUsage.pages(naming: "Param", reach: .type, owners: [], in: corpus)
        #expect(pages.first?.place == "Helpers/Parameters", "\(pages.map(\.address))")
    }

    /// The reader is written for the shape this tree is in, not for Swift
    /// at large, so this is the measure of how well it fits: the share of
    /// every public declaration it finds in the source. A change to the tree
    /// that it cannot follow shows up here as a drop rather than as comments
    /// quietly missing from the command's output.
    @Test("Nearly every public declaration in this checkout is found in the source")
    func coverage() throws {
        let checkout = try #require(Self.checkout)
        let root = checkout.root
        let all = checkout.declarations
            .filter { !$0.isExtension && $0.kind != .other }
        let places = SourceComments.places(of: all, inSources: root.appendingPathComponent("Sources"))
        let share = Double(places.count) / Double(all.count)
        let missing = all.indices.filter { places[$0] == nil }.prefix(20).map { all[$0].module + " " + all[$0].text }
        #expect(share > 0.999, "found \(places.count) of \(all.count); first missing: \(missing)")
    }
}
