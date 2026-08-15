import Foundation

public extension Installation {

    /// Which displays the piece goes on, and what each one carries.
    ///
    /// A wall wider than one projector needs more than one beam, and a room of
    /// screens showing the same piece needs more than one panel. Both are one
    /// machine driving several displays: the canvas is drawn once and then put
    /// on each display, with each display carrying its own part of it.
    ///
    /// ```swift
    /// override var installation: Installation {
    ///     Installation(displays: .spanning)
    /// }
    /// ```
    ///
    /// That spreads one canvas across every display the machine has, in the
    /// arrangement the displays are actually in: two monitors side by side each
    /// carry a half, one above the other each carry a band. Nothing is declared
    /// in numbers, because the desk already says it.
    ///
    /// ``parts(_:)`` is the form for a wall that is not a plain arrangement of
    /// monitors: two projectors overlapping in the middle, a display turned on
    /// its side, a piece of the canvas repeated. Each declaration says which
    /// part of the canvas that display carries and how its edges fade, exactly
    /// as a single machine's ``Projection`` does.
    ///
    /// The piece is drawn once a frame however many displays it goes on. What
    /// grows with the count is the size the canvas is drawn at, since every
    /// display wants its own part at its own resolution.
    enum Displays: Sendable, Equatable {

        /// The one display the piece opens on. The default, and the only value
        /// that costs nothing.
        case one

        /// Every display, with the canvas spread across the whole arrangement:
        /// each display carries the part of the canvas its own place on the desk
        /// covers. Two displays side by side carry a half each.
        ///
        /// The gap between two monitors carries part of the canvas that nobody
        /// sees, which is what the arrangement looks like to somebody standing
        /// in front of it.
        case spanning

        /// Every display, each carrying the whole canvas. For a row of screens
        /// in a shop window, or a piece repeated down a corridor.
        case mirroring

        /// One declaration per display, in the order the displays are arranged:
        /// left to right, and then top to bottom. A display past the end of the
        /// list stays dark, and a declaration past the end of the displays is
        /// ignored.
        case parts([Projection])

        /// Whether this is the one-display default, which opens exactly the run
        /// a piece has always opened.
        var isOne: Bool { self == .one }

        /// How many declarations this carries, for the rehearsal that has no
        /// displays to count.
        var declaredCount: Int? {
            if case .parts(let list) = self { return list.count }
            return nil
        }
    }
}

// MARK: - Working the declaration out against the displays

/// One display as the plan sees it: where it sits on the desk, and what its
/// corners are filed under.
///
/// Held apart from `NSScreen` so the plan is arithmetic over rectangles, which
/// is the half worth testing: a wall is decided by where the displays are, and
/// that can be stated without any of them being plugged in.
struct WallScreen: Equatable {

    /// The display's rectangle in desk coordinates, measured the way the canvas
    /// is: from the top left of the primary display, y downwards.
    var frame: Rectangle
    /// The same rectangle without the menu bar and the Dock, which is where a
    /// rehearsal lays its windows out.
    var visible: Rectangle
    /// What this display's corners are filed under.
    var key: String
    /// Whether this is the display the piece's own window opened on.
    var isPrimary: Bool

    init(frame: Rectangle, visible: Rectangle? = nil, key: String, isPrimary: Bool = false) {
        self.frame = frame
        self.visible = visible ?? frame
        self.key = key
        self.isPrimary = isPrimary
    }
}

/// One display of a wall, worked out: where its window goes, what it carries of
/// the canvas, and which display that is.
struct WallPart: Equatable {

    /// Where the window goes, in desk coordinates.
    var frame: Rectangle
    /// Which display this is filed under, or nil for a rehearsal, whose windows
    /// are on somebody's desk and stand for displays that are not here.
    var key: String?
    /// What this display carries.
    var projection: Installation.Projection
    /// Whether this is the part the piece's own window carries. Exactly one part
    /// is, and the window is moved to it.
    var isPrimary: Bool
}

/// Turning a declaration and a set of displays into one part per display.
///
/// Pure arithmetic over rectangles, so a wall of six projectors can be checked
/// with none of them plugged in.
enum WallPlan {

    /// The parts of the wall, one per display that carries anything.
    ///
    /// - Parameters:
    ///   - displays: what the sketch declared.
    ///   - base: the sketch's own ``Installation/Projection``, which every part
    ///     inherits its fades and its gamma from, and whose `shows` is the piece
    ///     of canvas the whole machine carries. A wall divides that piece rather
    ///     than the whole canvas, so one machine of a two-machine wall can drive
    ///     two projectors of its own.
    ///   - canvas: the canvas in pixels, for the proportions a rehearsal lays
    ///     its windows out at.
    ///   - screens: the displays, in any order.
    ///   - rehearsing: how many parts to lay out on one desk instead, for a wall
    ///     that has not been built yet.
    static func parts(_ displays: Installation.Displays,
                      base: Installation.Projection,
                      canvas: Vector2,
                      screens: [WallScreen],
                      rehearsing: Int? = nil) -> [WallPart] {
        // Left to right, then top to bottom: the order somebody reads a wall in,
        // and the order the declarations in `parts` are matched up with.
        let ordered = screens.sorted { a, b in
            a.frame.x == b.frame.x ? a.frame.y < b.frame.y : a.frame.x < b.frame.x
        }
        guard !ordered.isEmpty else { return [] }
        let home = ordered.first(where: \.isPrimary) ?? ordered[0]

        if let count = rehearsing {
            return rehearsal(displays, base: base, canvas: canvas, on: home, count: count)
        }

        var built: [WallPart]
        switch displays {
        case .one:
            built = [WallPart(frame: home.frame, key: home.key, projection: base, isPrimary: true)]
        case .mirroring:
            built = ordered.map {
                WallPart(frame: $0.frame, key: $0.key, projection: base, isPrimary: $0.isPrimary)
            }
        case .spanning:
            let wall = union(of: ordered.map(\.frame))
            built = ordered.map { screen in
                var part = base
                part.shows = slice(of: base.shows, taking: screen.frame, of: wall)
                // A display's own corners are the room's business, so a spread
                // canvas opens square and is dragged on to the wall from there.
                part.corners = .fit
                return WallPart(frame: screen.frame, key: screen.key,
                                projection: part, isPrimary: screen.isPrimary)
            }
        case .parts(let declared):
            built = zip(ordered, declared).map { screen, projection in
                WallPart(frame: screen.frame, key: screen.key,
                         projection: projection, isPrimary: screen.isPrimary)
            }
        }
        return withOnePrimary(built)
    }

    /// The whole wall the displays make between them.
    static func union(of frames: [Rectangle]) -> Rectangle {
        guard let first = frames.first else { return Rectangle(x: 0, y: 0, width: 0, height: 0) }
        var minX = first.x, minY = first.y
        var maxX = first.x + first.width, maxY = first.y + first.height
        for frame in frames.dropFirst() {
            minX = min(minX, frame.x)
            minY = min(minY, frame.y)
            maxX = max(maxX, frame.x + frame.width)
            maxY = max(maxY, frame.y + frame.height)
        }
        return Rectangle(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// The part of `base` that `screen` covers of `wall`, in the same fractions
    /// of the canvas that `base` is in.
    static func slice(of base: Rectangle, taking screen: Rectangle, of wall: Rectangle) -> Rectangle {
        guard wall.width > 0, wall.height > 0 else { return base }
        let u = (screen.x - wall.x) / wall.width
        let v = (screen.y - wall.y) / wall.height
        return Rectangle(x: base.x + u * base.width,
                         y: base.y + v * base.height,
                         width: base.width * screen.width / wall.width,
                         height: base.height * screen.height / wall.height)
    }

    /// Exactly one part is the one the piece's own window carries. The window is
    /// moved to it, so a display with no declaration never leaves the run with
    /// nowhere to draw.
    private static func withOnePrimary(_ parts: [WallPart]) -> [WallPart] {
        guard !parts.isEmpty, !parts.contains(where: \.isPrimary) else { return parts }
        var parts = parts
        parts[0].isPrimary = true
        return parts
    }

    // MARK: Rehearsing a wall that is not built yet

    /// The parts laid out as a row of windows on one desk, for seeing what each
    /// display will carry before there is a wall to carry it.
    ///
    /// They are laid out side by side with a gap, rather than overlapped as the
    /// real displays are: two beams sharing a band add their light, and two
    /// windows sharing a band would only hide one another.
    private static func rehearsal(_ displays: Installation.Displays,
                                  base: Installation.Projection,
                                  canvas: Vector2,
                                  on screen: WallScreen,
                                  count: Int) -> [WallPart] {
        let projections = rehearsedProjections(displays, base: base, count: count)
        guard !projections.isEmpty else { return [] }

        let area = screen.visible.inset(by: 0.04)
        let gap = 14.0
        let aspects = projections.map { pictureAspect($0.shows, canvas: canvas) }
        let spread = aspects.reduce(0, +)
        let room = max(1, area.width - gap * Double(projections.count - 1))
        let height = max(1, min(area.height, room / max(spread, 0.0001)))
        let width = height * spread + gap * Double(projections.count - 1)

        var x = area.x + (area.width - width) / 2
        let y = area.y + (area.height - height) / 2
        return projections.enumerated().map { index, projection in
            let tile = Rectangle(x: x, y: y, width: height * aspects[index], height: height)
            x += tile.width + gap
            return WallPart(frame: tile, key: nil, projection: projection, isPrimary: index == 0)
        }
    }

    /// What each rehearsed window carries. A spread canvas becomes `count` equal
    /// strips, which is the wall a row of matching displays would make.
    private static func rehearsedProjections(_ displays: Installation.Displays,
                                             base: Installation.Projection,
                                             count: Int) -> [Installation.Projection] {
        switch displays {
        case .one:
            return [base]
        case .mirroring:
            return Array(repeating: base, count: max(1, count))
        case .parts(let declared):
            return declared.isEmpty ? [base] : declared
        case .spanning:
            let strips = max(1, count)
            return (0..<strips).map { index in
                var part = base
                part.shows = Rectangle(x: base.shows.x + base.shows.width * Double(index) / Double(strips),
                                       y: base.shows.y,
                                       width: base.shows.width / Double(strips),
                                       height: base.shows.height)
                part.corners = .fit
                return part
            }
        }
    }

    /// The proportions of the part of the canvas a projection carries.
    static func pictureAspect(_ shows: Rectangle, canvas: Vector2) -> Double {
        guard shows.height > 0, canvas.y > 0 else { return 1 }
        return (shows.width * canvas.x) / (shows.height * canvas.y)
    }
}

private extension Rectangle {

    /// The same rectangle with a margin taken off every edge, as a fraction of
    /// the shorter side.
    func inset(by fraction: Double) -> Rectangle {
        let margin = min(width, height) * fraction
        return Rectangle(x: x + margin, y: y + margin,
                         width: max(1, width - margin * 2),
                         height: max(1, height - margin * 2))
    }
}

// MARK: - Reading the flags

/// The command line's say over a wall: which displays a piece goes on, and
/// whether it is being rehearsed at a desk instead.
///
/// The same shape as `--installation`: a piece can be put on a wall, taken off
/// one, or laid out for a look without editing a line of it.
enum WallFlags {

    /// `--rehearse` on its own, or `--rehearse 3`. Nil when it is not there.
    static func rehearsal(_ arguments: [String]) -> Int? {
        guard let index = arguments.firstIndex(of: "--rehearse") else { return nil }
        let next = arguments.index(after: index)
        guard next < arguments.endIndex, let count = Int(arguments[next]), count > 0 else { return 2 }
        return min(count, 8)
    }

    /// `--displays one|spanning|mirroring`. Nil when the sketch's own
    /// declaration stands.
    static func displays(_ arguments: [String]) -> Installation.Displays? {
        guard let index = arguments.firstIndex(of: "--displays") else { return nil }
        let next = arguments.index(after: index)
        guard next < arguments.endIndex else { return nil }
        switch arguments[next] {
        case "one": return .one
        case "spanning", "all": return .spanning
        case "mirroring", "mirror": return .mirroring
        default: return nil
        }
    }
}
