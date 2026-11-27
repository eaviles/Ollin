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

    /// A folder's cover, the four stills a listing shows for it, as paths
    /// under `base`.
    public struct Group: Sendable, Decodable {
        public var image: String
        public var imageSmall: String
    }

    /// The covers, by the folder they stand for (`3D`, `Recreations/Gego`).
    public var groups: [String: Group] = [:]

    public static let none = ExampleMedia(base: "", entries: [:], heroes: [:], showcase: [])

    private struct File: Decodable {
        var base: String
        var examples: [String: Entry]
        var heroes: [String: Hero]?
        var showcase: [Showpiece]?
        var chapters: [String: Chapter]?
        var groups: [String: Group]?
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
        var media = ExampleMedia(base: base, entries: file.examples, heroes: file.heroes ?? [:],
                                 showcase: file.showcase ?? [], chapters: file.chapters ?? [:])
        media.groups = file.groups ?? [:]
        return media
    }

    public subscript(example: String) -> Entry? { entries[example] }

    /// The full address of one file the manifest named.
    public func address(of path: String) -> String { "\(base)/\(path)" }

    // MARK: - How big a picture is

    /// The side a small copy is fitted into, which its name carries
    /// (`still-640.jpg`).
    public static let smallSide = 640
    /// The side of a folder's cover at full size. A cover is a square.
    public static let coverSide = 1080

    /// The size the pipeline gives a small copy of a picture: fitted inside
    /// a square of `smallSide` with its shape kept, the shorter side taken to
    /// the nearest even number, since a clip's sides have to be even and the
    /// still is cut with the same rule (`cap` in `Scripts/media.sh`). So a
    /// 1080 by 608 canvas is 640 by 360 and a 940 by 1080 one is 558 by 640.
    public static func smallSize(width: Int, height: Int) -> (width: Int, height: Int) {
        guard width > 0, height > 0 else { return (smallSide, smallSide) }
        func even(_ long: Int, _ short: Int) -> Int {
            2 * Int((Double(smallSide) * Double(short) / Double(long) / 2).rounded())
        }
        return width >= height ? (smallSide, max(2, even(width, height))) : (max(2, even(height, width)), smallSide)
    }

    /// The pixel size of a picture the manifest names, by its path under
    /// `base` with or without the version it carries (`?v=1f5259ec`), or nil
    /// for a path the manifest does not know.
    ///
    /// The files are on another host, so a page cannot read them when it is
    /// built; what it has is the canvas size each row records and the rule
    /// the pipeline cuts a small copy by. That is enough to give every
    /// picture its size in its tag, which is what holds its place on the page
    /// before the file arrives.
    public func pictureSize(at path: String) -> (width: Int, height: Int)? {
        pictureSizes[Self.unversioned(path)]
    }

    static func unversioned(_ path: String) -> String {
        String(path.prefix { $0 != "?" })
    }

    /// Every picture the manifest names, by its unversioned path. Built on
    /// each read, so a caller with many pictures to size keeps the table.
    public var pictureSizes: [String: (width: Int, height: Int)] {
        var found: [String: (width: Int, height: Int)] = [:]
        for entry in entries.values {
            found[Self.unversioned(entry.still)] = (entry.width, entry.height)
            found[Self.unversioned(entry.stillSmall)] = Self.smallSize(width: entry.width, height: entry.height)
        }
        for group in groups.values {
            found[Self.unversioned(group.image)] = (Self.coverSide, Self.coverSide)
            found[Self.unversioned(group.imageSmall)] = (Self.smallSide, Self.smallSide)
        }
        for hero in heroes.values {
            found[Self.unversioned(hero.image)] = (hero.width, hero.height)
        }
        return found
    }
}
