import Foundation

/// The clips and stills the site plays, as `Media/media.json`
/// names them.
///
/// The files themselves are not in the repository. They are rendered by
/// `Scripts/media.sh` and served from one host the manifest names once, so
/// moving that host is a single edit rather than a rewrite of every page that
/// shows one. An example with no row simply has no picture, which is what
/// lets the set fill in a folder at a time instead of all at once.
///
/// A missing or unreadable manifest is not an error. The site builds without
/// pictures, exactly as it did before any existed.
public struct ExampleMedia: Sendable {

    /// What one example's row says. The paths are relative to `base`.
    ///
    /// A sketch that draws one picture and holds it keeps its stills and has
    /// no clip, so both clip paths are absent from its row.
    public struct Entry: Sendable, Decodable {
        /// The clip at the canvas size, for the example's own page.
        public var loop: String?
        /// The small clip a grid plays under the pointer.
        public var loopSmall: String?
        /// The still at the canvas size, which is also the clip's poster.
        public var still: String
        /// The still at grid size.
        public var stillSmall: String
        public var width: Int
        public var height: Int
        /// Whether the clip carries the sketch's own music.
        public var sound: Bool?
    }

    /// A picture that opens a page, and the clip it stands in for.
    ///
    /// The markdown carries the picture, since that is what GitHub and a
    /// plain clone can show, and the site swaps in the clip.
    public struct Hero: Sendable, Decodable {
        public var image: String
        public var clip: String
        public var width: Int
        public var height: Int
        /// What the cells are, for the page to say out loud.
        public var of: String
    }

    /// One sketch the front page shows running beside its whole source.
    public struct Showpiece: Sendable, Decodable {
        public var example: String
        public var note: String
    }

    /// Where the files are served from, with no trailing slash.
    public var base: String
    /// Rows by example path, as `Patterns/Kaleidoscope`.
    public var entries: [String: Entry]
    /// The pictures that open a page, by the page they open.
    public var heroes: [String: Hero] = [:]
    /// The sketches the front page shows running beside their source.
    public var showcase: [Showpiece] = []
    /// A clip of the sketch each Guide chapter builds, by chapter stem
    /// (`01-HelloOllin`). The committed still stays the poster, so a clone,
    /// GitHub and the offline reference all show exactly what they always did.
    public var chapters: [String: Chapter] = [:]

    /// One chapter's finished sketch, recorded.
    public struct Chapter: Sendable, Decodable {
        /// The clip, as a path under `base`.
        public var clip: String
        /// The committed still it stands in for, as it is written in the
        /// chapter: `Images/01-HelloOllin/HelloMotion.jpg`.
        public var still: String
        public var width: Int
        public var height: Int
    }

    public static let none = ExampleMedia(base: "", entries: [:], heroes: [:], showcase: [])

    private struct File: Decodable {
        var base: String
        var examples: [String: Entry]
        var heroes: [String: Hero]?
        var showcase: [Showpiece]?
        var chapters: [String: Chapter]?
    }

    /// Read the manifest. It sits at `Media/media.json` in the repository
    /// rather than under `Examples/`, because it now carries the Guide's
    /// chapter clips and the site's own heroes as well as the examples'.
    public static func read(inRepository root: URL) -> ExampleMedia {
        let url = root.appendingPathComponent("Media/media.json")
        guard let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data) else { return .none }
        var base = file.base
        while base.hasSuffix("/") { base.removeLast() }
        return ExampleMedia(base: base, entries: file.examples, heroes: file.heroes ?? [:],
                            showcase: file.showcase ?? [], chapters: file.chapters ?? [:])
    }

    public subscript(example: String) -> Entry? { entries[example] }

    /// The full address of one file the manifest named.
    public func address(of path: String) -> String { "\(base)/\(path)" }
}
