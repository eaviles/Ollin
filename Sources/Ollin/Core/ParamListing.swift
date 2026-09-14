import Foundation

// The parameters a sketch declares, said out loud (`--list-params`). The other
// half of `--param`: one names a value to set, this one says what there is to
// set and what it holds right now.

/// A sketch's `@Param` parameters as text, written for a person and in the
/// spelling `--param` takes, so a line read here is a line that can be typed
/// straight back.
enum ParamListing {

    /// The whole listing: a count, the ungrouped parameters, then one block per
    /// group in the order the sketch declares them (which is the order the
    /// inspector stacks its cards in).
    ///
    /// The values are read after `setup()`, so they are the values the first
    /// frame is drawn with, `--param` and a starting cue included.
    @MainActor
    static func text(for sketch: Sketch) -> String {
        let handles = sketch.parameters()
        guard !handles.isEmpty else { return "no parameters" }
        let rows = handles.map(row(for:))
        let nameWidth = rows.map(\.name.count).max() ?? 0
        let kindWidth = rows.map(\.kind.count).max() ?? 0
        let valueWidth = rows.map(\.value.count).max() ?? 0

        var lines = ["\(handles.count) parameter\(handles.count == 1 ? "" : "s"), as --param takes them"]
        var groups: [String] = []
        for handle in handles {
            guard let group = handle.group, !groups.contains(group) else { continue }
            groups.append(group)
        }
        func block(_ title: String?, _ members: [Int]) {
            guard !members.isEmpty else { return }
            lines.append("")
            if let title { lines.append("  " + title) }
            for index in members {
                let row = rows[index]
                // The value before what the parameter accepts, so a menu with a
                // long roster runs off to the right instead of pushing the one
                // column a person came to read.
                var line = "  " + row.name.padding(toLength: nameWidth, withPad: " ", startingAt: 0)
                line += "  " + row.kind.padding(toLength: kindWidth, withPad: " ", startingAt: 0)
                line += "  " + row.value.padding(toLength: valueWidth, withPad: " ", startingAt: 0)
                line += "  " + row.range
                if !handles[index].isShown { line += "   (hidden right now)" }
                while line.hasSuffix(" ") { line.removeLast() }
                lines.append(line)
            }
        }
        block(nil, handles.indices.filter { handles[$0].group == nil })
        for group in groups {
            block(group, handles.indices.filter { handles[$0].group == group })
        }
        return lines.joined(separator: "\n")
    }

    /// One parameter's four columns: what it is called, what kind of value it
    /// holds, what it will accept, and what it holds now.
    @MainActor
    private static func row(for handle: ParamHandle) -> (name: String, kind: String, range: String, value: String) {
        (handle.name, kind(of: handle.control), accepts(handle.control), value(of: handle.param.stored))
    }

    /// The type as a sketch spells it, which is what the `--param` table on the
    /// export page names each kind by. A menu is the one row whose Swift type
    /// the erased parameter no longer carries, so it says what it is instead.
    private static func kind(of control: ParamControl) -> String {
        switch control {
        case .slider: "Double"
        case .stepper: "Int"
        case .toggle: "Bool"
        case .menu: "menu"
        case .colorWell: "Color"
        case .vector: "Vector2"
        case .vector3: "Vector3"
        case .rectangle: "Rectangle"
        case .insets: "Insets"
        case .range: "ClosedRange"
        case .text: "String"
        case .swatches: "colors"
        }
    }

    /// What the parameter will take: a range, a list of choices, or nothing to
    /// say (a color and a string take anything of their kind).
    private static func accepts(_ control: ParamControl) -> String {
        switch control {
        case .slider(let s):
            let step = s.step.map { ", by \(number($0))" } ?? ""
            return "\(number(s.range.lowerBound))...\(number(s.range.upperBound))" + step
        case .stepper(let s):
            return "\(s.range.lowerBound)...\(s.range.upperBound)"
        case .menu(let m):
            return m.options.joined(separator: ", ")
        case .vector(let v):
            return "x \(span(v.xRange)), y \(span(v.yRange))"
        case .vector3(let v):
            return "x \(span(v.xRange)), y \(span(v.yRange)), z \(span(v.zRange))"
        case .rectangle(let r):
            return "x \(span(r.xRange)), y \(span(r.yRange)), "
                + "w \(span(r.widthRange)), h \(span(r.heightRange))"
        case .insets(let i):
            return "each edge \(span(i.edgeRange))"
        case .range(let r):
            return "within \(span(r.outer))"
        case .swatches(let s):
            return "\(s.count.lowerBound) to \(s.count.upperBound) colors"
        case .toggle, .colorWell, .text:
            return ""
        }
    }

    /// The value in the spelling `--param` reads back, so every row is a flag
    /// that can be pasted. The inverse of `ParamOverride.stored(_:like:)`, and
    /// exact for every kind but a color: a color is said in hex, which is how
    /// the flag spells one and how a person reads one, so pasting one back
    /// lands on the nearest eight-bit step rather than on the same float.
    static func value(of stored: ParamStored) -> String {
        switch stored {
        case .number(let x): number(x)
        case .boolean(let flag): flag ? "true" : "false"
        case .option(let name): name
        case .color(let r, let g, let b, let a): hex(r, g, b, a)
        case .vector(let x, let y): "\(number(x)),\(number(y))"
        case .vector3(let x, let y, let z): "\(number(x)),\(number(y)),\(number(z))"
        case .rectangle(let x, let y, let width, let height):
            "\(number(x)),\(number(y)),\(number(width)),\(number(height))"
        case .insets(let top, let right, let bottom, let left):
            top == right && right == bottom && bottom == left
                ? number(top)
                : "\(number(top)),\(number(right)),\(number(bottom)),\(number(left))"
        case .range(let lower, let upper): "\(number(lower))...\(number(upper))"
        case .text(let text): text
        case .colors(let stops, _):
            stops.enumerated()
                .map { hex($1.red, $1.green, $1.blue, $1.alpha) + place($1, at: $0, of: stops.count) }
                .joined(separator: ",")
        }
    }

    /// A stop's place, written only when it is not where an even spread would
    /// already put it, which is how `--param` reads a strip back.
    private static func place(_ stop: ParamColorStop, at index: Int, of count: Int) -> String {
        guard count > 1 else { return "" }
        let even = Double(index) / Double(count - 1)
        return abs(stop.position - even) < 1e-6 ? "" : "@" + number(stop.position)
    }

    private static func span(_ range: ClosedRange<Double>) -> String {
        "\(number(range.lowerBound))...\(number(range.upperBound))"
    }

    /// A number as short as it can be said *and still be the same number*: a
    /// whole one keeps no point, and a fraction takes the fewest digits that
    /// read back as exactly itself. Shortening any further would break the one
    /// promise the listing makes, which is that a line can be pasted back.
    static func number(_ value: Double) -> String {
        guard value.isFinite else { return "\(value)" }
        if value == value.rounded(), abs(value) < 1e15 { return String(Int(value)) }
        for digits in 1 ... 9 {
            let text = String(format: "%.\(digits)f", value)
            if Double(text) == value { return text }
        }
        return String(value)
    }

    /// `#RRGGBB`, with the alpha pair only when it carries something.
    private static func hex(_ red: Double, _ green: Double, _ blue: Double, _ alpha: Double) -> String {
        func byte(_ value: Double) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
        let base = String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
        return alpha >= 1 ? base : base + String(format: "%02X", byte(alpha))
    }
}
