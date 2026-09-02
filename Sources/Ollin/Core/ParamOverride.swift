import Foundation

// Parameter values carried into a run from the command line. Every export already
// writes the `@Param` values it rendered with into its recipe; this is the way
// back in, so a value read off a recipe (or found in the inspector, or written
// down in a note) re-renders without editing the sketch.

/// One parameter value named on the command line: `--param radius=140`. The flag
/// repeats, so a run carries as many as it needs.
///
/// The text is read against the parameter's own kind, so a color, a vector, a menu
/// choice and a swatch strip arrive as readily as a number, and the value lands
/// through the same restore path the hosts use to carry a tuned parameter across a
/// reload (so it clamps to the declared range, the way dragging the row does).
///
/// It applies after `setup()` and before the first frame: a value given here
/// wins over the sketch's own `setup()`, and the export recipe (written once the
/// sketch has run) names the value the frame was really drawn with.
struct ParamOverride: Equatable, Sendable {
    /// The `@Param` property name, spelled as it is in Swift (`radius`, not `Radius`).
    let name: String
    /// The value as typed: everything after the first `=`.
    let text: String
}

/// What reading a flag or a value came to: the thing itself, or a line saying
/// what went wrong. A plain result rather than a thrown error, because every
/// caller here reports the line and carries on to the next parameter.
enum ParamRead<Value> {
    case value(Value)
    case problem(String)
}

// MARK: - Reading the flags

extension ParamOverride {

    static let usage = "usage: --param <name>=<value>, repeatable (--param radius=140 --param tint=#FF0066)"

    /// Every `--param name=value` in `args`, in the order given, so a parameter named
    /// twice ends on the last value. A flag with no `=` is a usage error, which
    /// is where a swept parameter's bare name lands, so the message points at the
    /// sheet's own flag.
    static func parse(_ args: [String]) -> ParamRead<[ParamOverride]> {
        var found: [ParamOverride] = []
        var hint = usage
        if args.contains("--export-sweep") {
            hint += "\nthe parameter a sheet sweeps is named with --sweep-param"
        }
        var i = 0
        while i < args.count {
            guard args[i] == "--param" else { i += 1; continue }
            guard i + 1 < args.count else { return .problem(hint) }
            let entry = args[i + 1]
            guard let mark = entry.firstIndex(of: "="), mark != entry.startIndex else {
                return .problem("--param \(entry): a value needs a name and an =\n" + hint)
            }
            found.append(ParamOverride(name: String(entry[..<mark]),
                                       text: String(entry[entry.index(after: mark)...])))
            i += 2
        }
        return .value(found)
    }
}

// MARK: - Reading a value against its parameter

extension ParamOverride {

    /// Read `text` as a value of the same kind as `current`, which is the parameter's
    /// value right now. Returns the payload to restore, or a line saying what
    /// the kind expects. A menu choice is not read here: it needs the parameter's own
    /// list of choices, which only its control carries.
    static func stored(_ text: String, like current: ParamStored) -> ParamRead<ParamStored> {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        switch current {
        case .number:
            guard let value = Double(trimmed), value.isFinite else {
                return .problem("expected a number, like 140 or 0.35")
            }
            return .value(.number(value))
        case .boolean:
            guard let value = boolean(trimmed) else {
                return .problem("expected true or false (yes, no, on, off, 1 and 0 also read)")
            }
            return .value(.boolean(value))
        case .option:
            return .problem("expected one of the parameter's choices")
        case .color:
            guard let color = color(trimmed) else {
                return .problem("expected a hex color like #FF0066, or numbers from 0 to 1 like 1,0.4,0")
            }
            return .value(Color.stored(color))
        case .vector:
            guard let n = numbers(trimmed, count: 2) else {
                return .problem("expected two numbers, like 540,540")
            }
            return .value(.vector(x: n[0], y: n[1]))
        case .vector3:
            guard let n = numbers(trimmed, count: 3) else {
                return .problem("expected three numbers, like 0,120,0")
            }
            return .value(.vector3(x: n[0], y: n[1], z: n[2]))
        case .rectangle:
            guard let n = numbers(trimmed, count: 4) else {
                return .problem("expected four numbers, x,y,width,height, like 40,40,200,120")
            }
            return .value(.rectangle(x: n[0], y: n[1], width: n[2], height: n[3]))
        case .insets:
            // One number sets every edge, the way a margin usually reads.
            if let n = numbers(trimmed, count: 1) {
                return .value(.insets(top: n[0], right: n[0], bottom: n[0], left: n[0]))
            }
            guard let n = numbers(trimmed, count: 4) else {
                return .problem("expected one number for every edge, or four: top,right,bottom,left")
            }
            return .value(.insets(top: n[0], right: n[1], bottom: n[2], left: n[3]))
        case .range:
            guard let (lower, upper) = range(trimmed) else {
                return .problem("expected two numbers, like 0.2...0.8 or 0.2,0.8")
            }
            return .value(.range(lower: lower, upper: upper))
        case .text:
            // A text parameter keeps what was typed, spaces included.
            return .value(.text(text))
        case .colors(_, let space):
            guard let stops = stops(trimmed) else {
                return .problem("expected hex colors, like #FFF,#F06,#036"
                                + " (a stop can name its place: #FFF@0,#036@0.75)")
            }
            // The parameter keeps the space it mixes in; only the colors move.
            return .value(.colors(stops: stops, space: space))
        }
    }

    private static func boolean(_ text: String) -> Bool? {
        switch text.lowercased() {
        case "true", "yes", "on", "1": return true
        case "false", "no", "off", "0": return false
        default: return nil
        }
    }

    /// Exactly `count` numbers, separated by commas.
    private static func numbers(_ text: String, count: Int) -> [Double]? {
        let parts = text.split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == count else { return nil }
        let values = parts.compactMap(Double.init)
        guard values.count == count, values.allSatisfy(\.isFinite) else { return nil }
        return values
    }

    private static func color(_ text: String) -> Color? {
        if let color = Color(hex: text) { return color }
        guard let n = numbers(text, count: 3) ?? numbers(text, count: 4) else { return nil }
        return Color(red: n[0], green: n[1], blue: n[2], alpha: n.count > 3 ? n[3] : 1)
    }

    /// `0.2...0.8` or `0.2,0.8`, either way round: the smaller number is the
    /// lower end, so a range written backwards still lands.
    private static func range(_ text: String) -> (Double, Double)? {
        var pair = numbers(text, count: 2)
        if pair == nil, let mark = text.range(of: "...") {
            let lower = Double(text[..<mark.lowerBound].trimmingCharacters(in: .whitespaces))
            let upper = Double(text[mark.upperBound...].trimmingCharacters(in: .whitespaces))
            if let lower, let upper, lower.isFinite, upper.isFinite { pair = [lower, upper] }
        }
        guard let pair else { return nil }
        return (Swift.min(pair[0], pair[1]), Swift.max(pair[0], pair[1]))
    }

    /// A list of hex colors, each free to name its place with `@`. Colors given
    /// no place are spread evenly, the way a palette's are.
    private static func stops(_ text: String) -> [ParamColorStop]? {
        let parts = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard !parts.isEmpty else { return nil }
        var given: [(place: Double?, color: Color)] = []
        for part in parts {
            var body = part
            var place: Double?
            if let mark = part.lastIndex(of: "@") {
                guard let value = Double(part[part.index(after: mark)...]
                    .trimmingCharacters(in: .whitespaces)), value.isFinite else { return nil }
                place = value
                body = String(part[..<mark]).trimmingCharacters(in: .whitespaces)
            }
            guard let color = Color(hex: body) else { return nil }
            given.append((place, color))
        }
        let even = given.count > 1
            ? (0 ..< given.count).map { Double($0) / Double(given.count - 1) }
            : [0]
        return given.enumerated().map {
            ParamColorStop(position: $1.place ?? even[$0], color: $1.color)
        }
    }
}

// MARK: - Applying them

extension ParamOverride {

    /// Apply every override to `sketch`, and return a line for each one that
    /// could not be applied. Nothing is silently skipped: a run that asked for a
    /// value it did not get would render a frame the recipe then describes
    /// wrongly, so the caller stops instead.
    @MainActor
    static func apply(_ overrides: [ParamOverride], to sketch: Sketch) -> [String] {
        guard !overrides.isEmpty else { return [] }
        let handles = sketch.parameters()
        var problems: [String] = []
        for override in overrides {
            guard let handle = handles.first(where: { $0.name == override.name }) else {
                let available = handles.map(\.name).sorted().joined(separator: ", ")
                problems.append("no @Param named '\(override.name)'; this sketch has: "
                                + (available.isEmpty ? "none" : available))
                continue
            }
            // A menu choice is matched against the parameter's own list of choices,
            // which is what the control carries; every other kind reads its text
            // against the value the parameter holds now.
            if case .option = handle.param.stored {
                if let problem = choose(override, on: handle) { problems.append(problem) }
                continue
            }
            switch stored(override.text, like: handle.param.stored) {
            case .value(let payload):
                handle.param.restore(payload)
            case .problem(let reason):
                problems.append("--param \(override.name)=\(override.text): \(reason)")
            }
        }
        return problems
    }

    @MainActor
    private static func choose(_ override: ParamOverride, on handle: ParamHandle) -> String? {
        guard case .menu(let menu) = handle.control else {
            return "--param \(override.name)=\(override.text): this parameter takes a named choice,"
                + " and it offers no list to match against"
        }
        let wanted = folded(override.text)
        guard let index = menu.options.firstIndex(where: { folded($0) == wanted }) else {
            return "--param \(override.name)=\(override.text): expected one of: "
                + menu.options.joined(separator: ", ")
        }
        menu.write(index)
        return nil
    }

    /// Choices match loosely, so `easeOut`, `ease-out` and `"Ease Out"` all find
    /// the same one.
    private static func folded(_ name: String) -> String {
        name.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}

// MARK: - The command line, and the seam every drive goes through

extension OllinApp {

    /// The parameter values this run was started with (`--param name=value`), read
    /// once while the command line is parsed and applied to every sketch a drive
    /// makes: each tile of a contact sheet gets them, not only the first.
    static var paramOverrides: [ParamOverride] = []

    /// Read the `--param` flags, and stop the run when one cannot be read at
    /// all. Called at the top of `handleCommandLine`, so the windowed path picks
    /// them up too.
    static func readParamOverrides(_ args: [String]) {
        switch ParamOverride.parse(args) {
        case .value(let overrides):
            paramOverrides = overrides
        case .problem(let message):
            FileHandle.standardError.write(Data((message + "\n").utf8))
            exit(1)
        }
    }
}

extension Sketch {

    /// Run `setup()`, then apply whatever `--param name=value` set on top of it.
    /// Every drive calls this rather than `setup()` directly, so a value given
    /// on the command line wins over the sketch's own `setup()` and reaches the
    /// export recipe, which is written once the sketch has run.
    ///
    /// A value that cannot be applied stops the run rather than rendering
    /// something nobody asked for.
    func runSetup() {
        setup()
        applyCommandLineParams()
    }

    /// Apply this run's `--param` values on their own, for a caller that runs
    /// `setup()` itself because something else has to happen in between (the
    /// window path restores a saved checkpoint there).
    func applyCommandLineParams() {
        let problems = ParamOverride.apply(OllinApp.paramOverrides, to: self)
        guard problems.isEmpty else {
            for problem in problems {
                FileHandle.standardError.write(Data(("Ollin: " + problem + "\n").utf8))
            }
            exit(1)
        }
    }
}
