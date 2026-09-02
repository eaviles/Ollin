// Moving a shape among the shapes drawn beside it, by moving its line.
//
// A shape drawn later lands on top, so which shape covers which is the order
// of the calls in the file. Reordering a shape by hand means moving its call
// past the neighboring one, which is the one gesture the number rewriter
// cannot serve: nothing on the line changes, the line changes place.
//
// The ink a shape is drawn with is set by the `fill`/`stroke` calls above it,
// so a line moved past one of those would come out in the wrong color. The
// move carries the ink along: the ink verbs the shape was drawn with are
// restated where it lands, the ink the shapes after it had is put back, and
// an ink line left with nothing to color is removed. Anything else standing
// between the two shapes (a `translate`, a `let`, a nested block, a call the
// scanner does not know) refuses the move by name, since moving past it could
// change more than the order.
//
// It works on lines: the block a call stands in is read as a list of
// statements, one per line except a call spread over several, and nested
// braces are one opaque item. Every line the author wrote survives, in the
// author's own spelling, with the moved and restated lines taking the
// indentation of the line they stand beside.

import Foundation
import Ollin

extension SourceEdit {

    /// What a reorder did.
    package struct Reorder: Equatable {
        /// The file's text with the call moved.
        package let text: String
        /// How many shapes the call moved past.
        package let steps: Int
        /// The 1-based line the call now starts on.
        package let line: Int
        /// The statement a move to the front or the back stopped at, as the
        /// file writes it, when one stood in the way after at least one step.
        package let stoppedBy: String?
    }

    /// The file's text with the call at `line`/`column` moved among the
    /// shapes drawn beside it.
    ///
    /// One step moves it past the next (or previous) draw call in its block. A
    /// move to the front or the back repeats that until nothing is left to
    /// pass, or until a statement stands in the way, in which case what was
    /// done stands and `stoppedBy` names it. Fails when the call is already at
    /// the edge, when a statement the move cannot carry ink across stands
    /// between the two shapes, or when the ink the shape needs cannot be read
    /// off the block.
    package static func reordering(_ source: String, line: Int, column: Int,
                                   by step: SourceReorderStep) throws -> Reorder {
        switch step {
        case .forward, .backward:
            let moved = try reorderingOnce(source, line: line, column: column,
                                           forward: step == .forward)
            return Reorder(text: moved.text, steps: 1, line: moved.line, stoppedBy: nil)
        case .toFront, .toBack:
            var text = source
            var at = line
            var steps = 0
            while true {
                do {
                    let moved = try reorderingOnce(text, line: at, column: column,
                                                   forward: step == .toFront)
                    text = moved.text
                    at = moved.line
                    steps += 1
                } catch Failure.alreadyAtTheEdge {
                    break
                } catch Failure.blockedBy(let statement) where steps > 0 {
                    return Reorder(text: text, steps: steps, line: at, stoppedBy: statement)
                } catch Failure.inkUnknown(let statement) where steps > 0 {
                    return Reorder(text: text, steps: steps, line: at, stoppedBy: statement)
                }
            }
            guard steps > 0 else { throw Failure.alreadyAtTheEdge }
            return Reorder(text: text, steps: steps, line: at, stoppedBy: nil)
        }
    }

    // MARK: One step

    /// One line of the block, as the move reads it.
    private enum Item {
        /// A draw call, the lines it spans (inclusive), and the ink set above
        /// it: nothing more is read off it.
        case draw(first: Int, last: Int)
        /// An ink verb, one line, and the kind of ink it sets.
        case ink(line: Int, kind: String)
        case blank(line: Int)
        case comment(line: Int)
        /// A statement the move will not carry ink across, or a nested block
        /// folded into one item.
        case other(first: Int, last: Int)

        var first: Int {
            switch self {
            case .draw(let first, _), .other(let first, _): return first
            case .ink(let line, _), .blank(let line), .comment(let line): return line
            }
        }
        var last: Int {
            switch self {
            case .draw(_, let last), .other(_, let last): return last
            case .ink(let line, _), .blank(let line), .comment(let line): return line
            }
        }
        var isInk: Bool { if case .ink = self { return true } else { return false } }
        var isComment: Bool { if case .comment = self { return true } else { return false } }
        var isDraw: Bool { if case .draw = self { return true } else { return false } }
        /// Whether the move may pass over this line without carrying anything.
        var isPassable: Bool {
            switch self {
            case .ink, .blank, .comment: return true
            case .draw, .other: return false
            }
        }
    }

    /// The verbs that set ink, and the kind each sets, so a `fill` and a
    /// `noFill` are read as the same setting.
    private static let inkVerbs: [String: String] = [
        "fill": "fill", "noFill": "fill",
        "stroke": "stroke", "noStroke": "stroke",
        "strokeWeight": "strokeWeight",
        "strokeCap": "strokeCap", "strokeJoin": "strokeJoin", "strokeAlign": "strokeAlign",
        "hollow": "hollow", "solid": "hollow",
        "blendMode": "blendMode",
    ]

    /// What a shape is drawn with when nothing in the block says: the ink the
    /// drawer starts a frame with. Only the three kinds a sketch changes
    /// often; the rest refuse rather than guess.
    private static let defaultInk: [String: String] = [
        "fill": "fill(.white)",
        "stroke": "stroke(.black)",
        "strokeWeight": "strokeWeight(1)",
    ]

    /// The kinds that only matter while there is a stroke to draw: a shape
    /// under `noStroke()` does not carry them, and does not need them back.
    private static let strokeDetails: Set<String> = ["strokeWeight", "strokeCap", "strokeJoin", "strokeAlign"]

    private static func reorderingOnce(_ source: String, line: Int, column: Int,
                                       forward: Bool) throws -> (text: String, line: Int) {
        let bytes = Array(source.utf8)
        var lines = source.components(separatedBy: "\n")
        // Byte offset at which each line starts, so a byte index maps to a line.
        var lineStarts: [Int] = [0]
        for (index, byte) in bytes.enumerated() where byte == UInt8(ascii: "\n") {
            lineStarts.append(index + 1)
        }
        func lineIndex(ofByte byte: Int) -> Int {
            var low = 0, high = lineStarts.count - 1
            while low < high {
                let mid = (low + high + 1) / 2
                if lineStarts[mid] <= byte { low = mid } else { high = mid - 1 }
            }
            return low
        }

        guard let open = openParen(in: bytes, line: line, column: column),
              let close = closeParen(in: bytes, openParen: open) else {
            throw Failure.callNotFound
        }
        let first = lineIndex(ofByte: open)
        let last = lineIndex(ofByte: close)

        // The call has to be the whole of its lines: the name and the `(` after
        // the indentation, and nothing after the `)` but a comment.
        let head = String(decoding: bytes[lineStarts[first] ..< open], as: UTF8.self)
        let lead = head.prefix(while: { $0 == " " || $0 == "\t" })
        guard drawName(of: String(head.dropFirst(lead.count)) + "(") != nil else {
            throw Failure.notAlone(line: lines[first].trimmingCharacters(in: .whitespaces))
        }
        let tail = String(decoding: bytes[(close + 1) ..< (last + 1 < lineStarts.count ? lineStarts[last + 1] - 1 : bytes.count)],
                          as: UTF8.self)
        let tailTrimmed = tail.trimmingCharacters(in: .whitespaces)
        guard tailTrimmed.isEmpty || tailTrimmed.hasPrefix("//") else {
            throw Failure.notAlone(line: lines[last].trimmingCharacters(in: .whitespaces))
        }

        // The block: from the line after the brace that opens it to the line
        // before the one that closes it, nested braces folded.
        let blockStart = startOfBlock(lines, above: first)
        let blockEnd = endOfBlock(lines, below: last)
        let items = readItems(lines, bytes: bytes, lineStarts: lineStarts,
                              from: blockStart, to: blockEnd, lineIndex: lineIndex)
        guard let shape = items.firstIndex(where: { $0.first == first && $0.isDraw }) else {
            throw Failure.callNotFound
        }

        // The neighbor it moves past, and what stands between.
        let direction = forward ? 1 : -1
        var neighbor: Int?
        var index = shape + direction
        while index >= 0, index < items.count {
            let item = items[index]
            if item.isDraw { neighbor = index; break }
            guard item.isPassable else {
                throw Failure.blockedBy(statement: lines[item.first].trimmingCharacters(in: .whitespaces))
            }
            index += direction
        }
        guard let neighbor else { throw Failure.alreadyAtTheEdge }
        let between = forward ? Array(items[(shape + 1) ..< neighbor]) : Array(items[(neighbor + 1) ..< shape])

        // The ink in force at a point in the block: kind to the line that set it.
        func ink(before itemIndex: Int) -> [String: String] {
            var state: [String: String] = [:]
            for item in items[0 ..< itemIndex] {
                if case .ink(let line, let kind) = item {
                    state[kind] = lines[line].trimmingCharacters(in: .whitespaces)
                }
            }
            return state
        }
        /// The run of comments and ink standing directly above an item, with no
        /// blank line breaking it: the item's own.
        func own(of itemIndex: Int) -> [Item] {
            var run: [Item] = []
            var at = itemIndex - 1
            while at >= 0, items[at].isInk || items[at].isComment {
                run.insert(items[at], at: 0)
                at -= 1
            }
            return run
        }
        /// Whether a kind of ink is set again after `itemIndex` before any
        /// shape could use it, so a line setting it there would be dead.
        func isResetBeforeUse(_ kind: String, after itemIndex: Int) -> Bool {
            for item in items[(itemIndex + 1)...] {
                switch item {
                case .ink(_, let setKind) where setKind == kind: return true
                case .ink, .blank, .comment: continue
                case .draw, .other: return false
                }
            }
            return true   // the block ends: nothing else uses it
        }

        let indent = String(lines[first].prefix(while: { $0 == " " || $0 == "\t" }))
        var removed = Set<Int>()
        var restated: [String] = []
        var restored: [String] = []
        let shapeOwn = own(of: shape)
        let movedComments = shapeOwn.filter(\.isComment).map { lines[$0.first] }
        for item in shapeOwn where item.isComment { removed.insert(item.first) }
        for line in items[shape].first ... items[shape].last { removed.insert(line) }

        let inkAtShape = ink(before: shape)
        let insertAt: Int
        if forward {
            // Landing after the neighbor. The ink between the two is what the
            // neighbor changed; the shape wants its own back for those kinds.
            let changed = between.compactMap { item -> String? in
                if case .ink(_, let kind) = item { return kind } else { return nil }
            }
            let inkAtNeighbor = ink(before: neighbor)
            for kind in orderedUnique(changed) where inkAtShape[kind] != inkAtNeighbor[kind] {
                if strokeDetails.contains(kind), inkAtShape["stroke"] == "noStroke()" { continue }
                guard let mine = inkAtShape[kind] ?? defaultInk[kind] else {
                    throw Failure.inkUnknown(statement: inkAtNeighbor[kind] ?? kind)
                }
                restated.append(mine)
                // The shapes after the neighbor keep what they had, unless
                // nothing uses it before it is set again.
                if !isResetBeforeUse(kind, after: neighbor), let theirs = inkAtNeighbor[kind] {
                    restored.append(theirs)
                }
            }
            // Ink above the shape that nothing reads once it has gone.
            for item in shapeOwn {
                if case .ink(let line, let kind) = item, changed.contains(kind) {
                    removed.insert(line)
                }
            }
            insertAt = items[neighbor].last + 1
        } else {
            // Landing before the neighbor's own ink and comments, so the
            // neighbor keeps them. The ink between the two, and the neighbor's
            // own, is what the shape had over the neighbor.
            let neighborOwn = own(of: neighbor)
            let landing = neighbor - neighborOwn.count
            let inkAtLanding = ink(before: landing)
            var changed: [String] = []
            for item in neighborOwn + between {
                if case .ink(_, let kind) = item { changed.append(kind) }
            }
            for kind in orderedUnique(changed) where inkAtShape[kind] != inkAtLanding[kind] {
                if strokeDetails.contains(kind), inkAtShape["stroke"] == "noStroke()" { continue }
                guard let mine = inkAtShape[kind] ?? defaultInk[kind] else {
                    throw Failure.inkUnknown(statement: inkAtLanding[kind] ?? kind)
                }
                restated.append(mine)
                // The neighbor sets some of these itself; the rest it had from
                // above, and gets back.
                let neighborSets = neighborOwn.contains {
                    if case .ink(_, let setKind) = $0 { return setKind == kind } else { return false }
                }
                if !neighborSets {
                    guard let theirs = inkAtLanding[kind] ?? defaultInk[kind] else {
                        throw Failure.inkUnknown(statement: mine)
                    }
                    restored.append(theirs)
                }
            }
            // Ink between the two that nothing reads once the shape has gone.
            for item in between {
                if case .ink(let line, let kind) = item, isResetBeforeUse(kind, after: shape) {
                    removed.insert(line)
                }
            }
            insertAt = neighborOwn.first?.first ?? items[neighbor].first
        }

        // Put it together: the lines that stay, with the moved block put in.
        let shapeLines = (items[shape].first ... items[shape].last).map { lines[$0] }
        let block = movedComments + restated.map { indent + $0 } + shapeLines + restored.map { indent + $0 }
        var out: [String] = []
        var newLine = first
        var touchedStart = lines.count, touchedEnd = 0
        for (number, text) in lines.enumerated() {
            if number == insertAt {
                touchedStart = min(touchedStart, out.count)
                newLine = out.count + movedComments.count + restated.count
                out += block
                touchedEnd = max(touchedEnd, out.count)
            }
            if number == first { touchedStart = min(touchedStart, out.count) }
            if !removed.contains(number) { out.append(text) }
            // One line past the shape's old place: the ink put back there by
            // an earlier move is what a move the other way makes redundant.
            if number == items[shape].last { touchedEnd = max(touchedEnd, out.count + 1) }
        }
        if insertAt >= lines.count {
            touchedStart = min(touchedStart, out.count)
            newLine = out.count + movedComments.count + restated.count
            out += block
            touchedEnd = max(touchedEnd, out.count)
        }
        lines = out

        // A move can leave an ink line saying what is already in force, in
        // the stretch it touched: a restore from an earlier step the shape has
        // now moved back over. Those go, and nothing outside the stretch is
        // read, so a line the author wrote twice on purpose elsewhere stays.
        let joined = lines.joined(separator: "\n")
        let newBytes = Array(joined.utf8)
        var newStarts: [Int] = [0]
        for (index, byte) in newBytes.enumerated() where byte == UInt8(ascii: "\n") {
            newStarts.append(index + 1)
        }
        func newLineIndex(ofByte byte: Int) -> Int {
            var low = 0, high = newStarts.count - 1
            while low < high {
                let mid = (low + high + 1) / 2
                if newStarts[mid] <= byte { low = mid } else { high = mid - 1 }
            }
            return low
        }
        let newBlockStart = startOfBlock(lines, above: newLine)
        let newBlockEnd = endOfBlock(lines, below: newLine)
        let newItems = readItems(lines, bytes: newBytes, lineStarts: newStarts,
                                 from: newBlockStart, to: newBlockEnd, lineIndex: newLineIndex)
        var inForce: [String: String] = [:]
        var redundant = Set<Int>()
        for item in newItems {
            guard case .ink(let number, let kind) = item else { continue }
            let text = lines[number].trimmingCharacters(in: .whitespaces)
            if inForce[kind] == text, number >= touchedStart, number < touchedEnd {
                redundant.insert(number)
            }
            inForce[kind] = text
        }
        if !redundant.isEmpty {
            let before = redundant.filter { $0 < newLine }.count
            lines = lines.enumerated().filter { !redundant.contains($0.offset) }.map(\.element)
            newLine -= before
        }
        return (lines.joined(separator: "\n"), newLine + 1)
    }

    // MARK: Reading the block

    /// The name of a draw call at the start of `text`, or nil: `draw`, a
    /// capital, the rest of the name, and the `(`.
    private static func drawName(of text: String) -> String? {
        guard text.hasPrefix("draw") else { return nil }
        var name = "draw"
        var rest = text.dropFirst(4)
        guard let firstLetter = rest.first, firstLetter.isUppercase else { return nil }
        while let character = rest.first, character.isLetter || character.isNumber || character == "_" {
            name.append(character)
            rest = rest.dropFirst()
        }
        guard rest.first == "(" else { return nil }
        return name
    }

    /// The ink verb at the start of `text`, or nil.
    private static func inkKind(of text: String) -> String? {
        var name = ""
        var rest = Substring(text)
        while let character = rest.first, character.isLetter || character.isNumber || character == "_" {
            name.append(character)
            rest = rest.dropFirst()
        }
        guard rest.first == "(", let kind = inkVerbs[name] else { return nil }
        return kind
    }

    private static func opensBlock(_ trimmed: String) -> Bool {
        !trimmed.hasPrefix("//") && trimmed.hasSuffix("{")
    }

    private static func closesBlock(_ trimmed: String) -> Bool {
        trimmed.hasPrefix("}")
    }

    /// The first line of the block a line stands in: the line after the
    /// brace that opens it, or the top of the file.
    private static func startOfBlock(_ lines: [String], above line: Int) -> Int {
        var depth = 0
        var at = line - 1
        while at >= 0 {
            let trimmed = lines[at].trimmingCharacters(in: .whitespaces)
            if closesBlock(trimmed) { depth += 1 }
            if opensBlock(trimmed) {
                if depth == 0 { return at + 1 }
                depth -= 1
            }
            at -= 1
        }
        return 0
    }

    /// One past the last line of the block: the brace that closes it, or the
    /// end of the file.
    private static func endOfBlock(_ lines: [String], below line: Int) -> Int {
        var depth = 0
        var at = line + 1
        while at < lines.count {
            let trimmed = lines[at].trimmingCharacters(in: .whitespaces)
            if closesBlock(trimmed) {
                if depth == 0 { return at }
                depth -= 1
            }
            if opensBlock(trimmed) { depth += 1 }
            at += 1
        }
        return lines.count
    }

    /// The block's lines as items, in order, nested braces folded into one
    /// and a call spread over lines read as one.
    private static func readItems(_ lines: [String], bytes: [UInt8], lineStarts: [Int],
                                  from start: Int, to end: Int,
                                  lineIndex: (Int) -> Int) -> [Item] {
        var items: [Item] = []
        var at = start
        while at < end {
            let text = lines[at]
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                items.append(.blank(line: at)); at += 1; continue
            }
            if trimmed.hasPrefix("//") {
                items.append(.comment(line: at)); at += 1; continue
            }
            if opensBlock(trimmed) {
                // Fold the nested block, to its closing brace.
                var depth = 1
                var scan = at + 1
                while scan < end, depth > 0 {
                    let inner = lines[scan].trimmingCharacters(in: .whitespaces)
                    if closesBlock(inner) { depth -= 1 }
                    if opensBlock(inner) { depth += 1 }
                    scan += 1
                }
                items.append(.other(first: at, last: min(scan, end) - 1))
                at = scan
                continue
            }
            if drawName(of: trimmed) != nil,
               let open = text.utf8.firstIndex(of: UInt8(ascii: "(")) {
                let openByte = lineStarts[at] + text.utf8.distance(from: text.utf8.startIndex, to: open)
                let last = closeParen(in: bytes, openParen: openByte).map(lineIndex) ?? at
                items.append(.draw(first: at, last: max(at, last)))
                at = max(at, last) + 1
                continue
            }
            if let kind = inkKind(of: trimmed) {
                items.append(.ink(line: at, kind: kind)); at += 1; continue
            }
            items.append(.other(first: at, last: at))
            at += 1
        }
        return items
    }

    /// The byte index of the `)` closing the call whose `(` is at
    /// `openParen`, skipping strings and comments the way the argument
    /// scanner does.
    static func closeParen(in bytes: [UInt8], openParen: Int) -> Int? {
        var depth = 0
        var index = openParen
        while index < bytes.count {
            let byte = bytes[index]
            switch byte {
            case UInt8(ascii: "\""):
                index = endOfString(bytes, from: index)
                continue
            case UInt8(ascii: "/") where index + 1 < bytes.count:
                if bytes[index + 1] == UInt8(ascii: "/") || bytes[index + 1] == UInt8(ascii: "*") {
                    index = endOfComment(bytes, from: index)
                    continue
                }
            case UInt8(ascii: "("), UInt8(ascii: "["), UInt8(ascii: "{"):
                depth += 1
            case UInt8(ascii: ")"), UInt8(ascii: "]"), UInt8(ascii: "}"):
                depth -= 1
                if depth == 0 { return index }
            default:
                break
            }
            index += 1
        }
        return nil
    }

    private static func orderedUnique(_ kinds: [String]) -> [String] {
        var seen = Set<String>()
        return kinds.filter { seen.insert($0).inserted }
    }
}
