import Foundation

/// Everything the generator needs to make one project: what to call it, which
/// kind and template, what else to wire in, and where to put it.
public struct ProjectRequest: Sendable {
    /// The name as typed. Becomes the folder name, and (cleaned up) the type name.
    public var name: String
    public var kind: ProjectKind
    public var template: ProjectTemplate
    /// An example to start from instead of the template. When set it wins, since
    /// it is a whole working sketch and the template would only be in its way.
    public var example: ExampleSource.Example?
    /// A shader brought over from GLSL. Like an example, it decides the sketch
    /// rather than filling a template in.
    public var importedShader: ImportedShader?
    /// A 3D scene brought over from a file. Like a shader, it decides the sketch.
    public var importedScene: ImportedScene?
    /// Capabilities asked for beyond the ones the starting point needs itself.
    public var capabilities: [Capability]
    public var canvas: CanvasChoice
    /// Which 3D pieces are in play, for the starting point that draws in 3D.
    /// Ignored by every other one.
    public var threeD: ThreeDRecipe?
    /// The package the sketch will join, when the caller has already found it.
    /// Left nil, the generator looks for the nearest one itself.
    public var packageHost: PackageHost?
    /// The folder the project is created *in*.
    public var destination: URL
    /// How the generated manifest reaches the framework.
    public var framework: FrameworkSource

    public init(
        name: String,
        kind: ProjectKind = .macSketch,
        template: ProjectTemplate = .blank,
        example: ExampleSource.Example? = nil,
        importedShader: ImportedShader? = nil,
        importedScene: ImportedScene? = nil,
        capabilities: [Capability] = [],
        canvas: CanvasChoice = .default,
        threeD: ThreeDRecipe? = nil,
        packageHost: PackageHost? = nil,
        destination: URL,
        framework: FrameworkSource
    ) {
        self.name = name
        self.kind = kind
        self.template = template
        self.example = example
        self.importedShader = importedShader
        self.importedScene = importedScene
        self.capabilities = capabilities
        self.canvas = canvas
        self.threeD = threeD
        self.packageHost = packageHost
        self.destination = destination
        self.framework = framework
    }

    /// Every capability the generated sketch links: what the starting point
    /// needs itself plus the caller's, de-duplicated and in catalog order so two
    /// runs agree. An example states its needs by what it imports.
    public var resolvedCapabilities: [Capability] {
        let own: Set<String>
        if let example {
            own = Set(Capability.satellites.filter { example.modules.contains($0.module ?? "") }.map(\.id))
        } else {
            own = Set(template.requires)
        }
        let wanted = own.union(capabilities.map(\.id))
        return Capability.all.filter { wanted.contains($0.id) }
    }

    /// What the starting point is called, for a message or a list row.
    public var startingPointTitle: String {
        if let example { return example.path }
        if let name = importedScene?.resourceFileName { return name }
        return template.title
    }

    /// The project name reduced to something that can be a Swift type name.
    /// Mirrors what the command line does for a loose file, so both faces of the
    /// generator name a class the same way.
    public var typeName: String {
        let stripped = name.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0) || $0 == "_"
        }
        var cleaned = String(String.UnicodeScalarView(stripped))
        if cleaned.isEmpty || cleaned.first!.isNumber { cleaned = "MySketch" }
        return cleaned.prefix(1).uppercased() + cleaned.dropFirst()
    }

    /// The folder name on disk: the name as typed, with the separators a path
    /// cannot take replaced.
    public var folderName: String {
        let cleaned = name.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "MySketch" : cleaned
    }
}

/// Where a generated manifest points for the framework.
///
/// The path form is the honest default while the framework is unpublished: the
/// generator knows the repository it is running out of, so it writes that in and
/// the project builds straight away. The remote form is for a project meant to
/// be shared with someone who does not have that folder.
public enum FrameworkSource: Sendable, Hashable {
    case localPath(URL)
    case remote(url: String, branch: String)

    /// The `dependencies:` entry this source becomes.
    public var manifestEntry: String {
        switch self {
        case .localPath(let url):
            return ".package(path: \"\(url.path)\")"
        case .remote(let url, let branch):
            return ".package(url: \"\(url)\", branch: \"\(branch)\")"
        }
    }
}

/// A canvas size offered by the generator, carrying the expression it emits.
///
/// Spelled as text rather than as a `CanvasSize` because this library generates
/// source and never links the framework, which keeps it quick to build and to
/// test.
public struct CanvasChoice: Sendable, Hashable, Identifiable {
    public let id: String
    public let title: String
    /// The `CanvasSize` expression, or nil to leave the framework default alone.
    public let expression: String?

    public init(id: String, title: String, expression: String?) {
        self.id = id
        self.title = title
        self.expression = expression
    }
}

extension CanvasChoice {
    public static let `default` = CanvasChoice(id: "default", title: "Default (1080 square)", expression: nil)
    public static let square1440 = CanvasChoice(id: "square1440", title: "Square 1440", expression: ".square1440")
    public static let square2160 = CanvasChoice(id: "square2160", title: "Square 2160", expression: ".square2160")
    public static let fhd1080 = CanvasChoice(id: "fhd1080", title: "1920 x 1080", expression: ".fhd1080")
    public static let uhd4K = CanvasChoice(id: "uhd4k", title: "3840 x 2160", expression: ".uhd4K")
    public static let vertical1080 = CanvasChoice(id: "vertical1080", title: "Vertical 1080 x 1920", expression: ".vertical1080")
    public static let portrait1080 = CanvasChoice(id: "portrait1080", title: "Portrait 1080 x 1350", expression: ".portrait1080")
    public static let a4 = CanvasChoice(id: "a4", title: "A4 sheet", expression: ".a4")
    public static let a3 = CanvasChoice(id: "a3", title: "A3 sheet", expression: ".a3")
    public static let usLetter = CanvasChoice(id: "us-letter", title: "US Letter sheet", expression: ".usLetter")

    public static let all: [CanvasChoice] = [
        .default, .square1440, .square2160, .fhd1080, .uhd4K,
        .vertical1080, .portrait1080, .a4, .a3, .usLetter,
    ]

    public static func named(_ id: String) -> CanvasChoice? {
        all.first { $0.id == id }
    }
}
