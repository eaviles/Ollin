import Foundation

/// A parameter driven by a formula (`drive($radius, "150 + sin(time) * 40")`),
/// as the page carries it: the formula's text as JavaScript, the names it
/// reads, and the parameter's own range and step, which the Mac applies to
/// every value the formula answers and the page applies the same way. A shape
/// column the recorder finds to be an affine function of the parameter is
/// wired to it, so the page works the motion out live from the formula rather
/// than reading it back frame by frame.
struct WebFormula: Equatable {
    /// The parameter's name, or `name.part` for one part of a parameter that
    /// holds more than one number.
    var name: String
    /// The text the formula was written as.
    var source: String
    /// The same formula as a JavaScript expression over `v` (the names) and
    /// `Fx` (the page's small helper set).
    var javaScript: String
    /// The names the formula reads.
    var reads: [String]
    /// The parameter's range and step, applied after evaluation; `nil` for a
    /// part or a parameter without one.
    var lowerBound: Double?
    var upperBound: Double?
    var step: Double?
    /// Whether the parameter holds an integer, so the value is rounded.
    var isInteger: Bool

    var meta: [String: Any] {
        var m: [String: Any] = ["name": name, "js": javaScript, "reads": reads, "integer": isInteger]
        if let lo = lowerBound, let hi = upperBound, lo.isFinite, hi.isFinite {
            m["lo"] = lo
            m["hi"] = hi
        }
        if let step, step > 0 { m["step"] = step }
        return m
    }
}

/// The automation's clock as the page replays it: where a formula's `time`
/// stands when the sketch clock reads `t`.
struct WebAutomationClock: Equatable {
    var start: Double
    var speed: Double
    var loops: Bool
    var duration: Double

    var meta: [String: Any] { ["start": start, "speed": speed, "loops": loops, "duration": duration] }
}

/// The formula tree written out as JavaScript. Every function and operator
/// keeps the semantics `FormulaNode.value` gives it: truth is "a number, and
/// not zero", `mod` floors, `round` rounds half away from zero, `step` reads
/// its edge first, and `&&` / `||` short-circuit.
enum FormulaJS {
    /// The expression, or `nil` for a formula that reads a noise field, which
    /// the page has no copy of.
    static func compile(_ formula: Formula) -> String? {
        guard !formula.usesNoise else { return nil }
        return emit(formula.tree, names: formula.variables)
    }

    /// The helpers the expressions call, defined once on the page.
    static let helpers = """
    var Fx = {
      T: function (x) { return x === x && x !== 0; },
      M: function (a, b) { return b === 0 ? NaN : a - b * Math.floor(a / b); },
      round: function (x) { return x < 0 ? -Math.round(-x) : Math.round(x); },
      sign: function (x) { return x > 0 ? 1 : (x < 0 ? -1 : 0); },
      fract: function (x) { return x - Math.floor(x); },
      sat: function (x) { return Math.min(Math.max(x, 0), 1); },
      clamp: function (x, lo, hi) { return Math.min(Math.max(x, lo), hi); },
      ss: function (e0, e1, x) { var t = Math.min(Math.max((x - e0) / (e1 - e0), 0), 1); return t * t * (3 - 2 * t); },
      map: function (x, a, b, c, d) { return c + (d - c) * ((x - a) / (b - a)); },
      param: function (x, f) {
        if (f.lo !== undefined) {
          x = Math.min(Math.max(x, f.lo), f.hi);
          if (f.step > 0) { x = f.lo + Fx.round((x - f.lo) / f.step) * f.step; x = Math.min(x, f.hi); }
        }
        if (f.integer) x = Fx.round(x);
        return x;
      }
    };
    """

    private static func emit(_ node: FormulaNode, names: [String]) -> String {
        switch node {
        case .number(let v):
            return literal(v)
        case .variable(let index):
            let name = index < names.count ? names[index] : ""
            return "v[\(OllinApp.jsString(name))]"
        case .negate(let e):
            return "(-\(emit(e, names: names)))"
        case .not(let e):
            return "(Fx.T(\(emit(e, names: names))) ? 0 : 1)"
        case .binary(let op, let l, let r):
            let a = emit(l, names: names), b = emit(r, names: names)
            switch op {
            case .add: return "(\(a) + \(b))"
            case .subtract: return "(\(a) - \(b))"
            case .multiply: return "(\(a) * \(b))"
            case .divide: return "(\(a) / \(b))"
            case .remainder: return "Fx.M(\(a), \(b))"
            case .power: return "Math.pow(\(a), \(b))"
            case .less: return "(\(a) < \(b) ? 1 : 0)"
            case .lessEqual: return "(\(a) <= \(b) ? 1 : 0)"
            case .greater: return "(\(a) > \(b) ? 1 : 0)"
            case .greaterEqual: return "(\(a) >= \(b) ? 1 : 0)"
            case .equal: return "(\(a) === \(b) ? 1 : 0)"
            case .notEqual: return "(\(a) !== \(b) ? 1 : 0)"
            case .and: return "(Fx.T(\(a)) && Fx.T(\(b)) ? 1 : 0)"
            case .or: return "(Fx.T(\(a)) || Fx.T(\(b)) ? 1 : 0)"
            }
        case .call(let function, let arguments):
            let a = arguments.map { emit($0, names: names) }
            func arg(_ i: Int) -> String { i < a.count ? a[i] : "0" }
            switch function {
            case .sin: return "Math.sin(\(arg(0)))"
            case .cos: return "Math.cos(\(arg(0)))"
            case .tan: return "Math.tan(\(arg(0)))"
            case .asin: return "Math.asin(\(arg(0)))"
            case .acos: return "Math.acos(\(arg(0)))"
            case .atan: return "Math.atan(\(arg(0)))"
            case .sinh: return "Math.sinh(\(arg(0)))"
            case .cosh: return "Math.cosh(\(arg(0)))"
            case .tanh: return "Math.tanh(\(arg(0)))"
            case .atan2: return "Math.atan2(\(arg(0)), \(arg(1)))"
            case .abs: return "Math.abs(\(arg(0)))"
            case .sign: return "Fx.sign(\(arg(0)))"
            case .floor: return "Math.floor(\(arg(0)))"
            case .ceil: return "Math.ceil(\(arg(0)))"
            case .round: return "Fx.round(\(arg(0)))"
            case .trunc: return "Math.trunc(\(arg(0)))"
            case .fract: return "Fx.fract(\(arg(0)))"
            case .sqrt: return "Math.sqrt(\(arg(0)))"
            case .exp: return "Math.exp(\(arg(0)))"
            case .log: return "Math.log(\(arg(0)))"
            case .log2: return "Math.log2(\(arg(0)))"
            case .log10: return "Math.log10(\(arg(0)))"
            case .pow: return "Math.pow(\(arg(0)), \(arg(1)))"
            case .hypot: return "Math.hypot(\(arg(0)), \(arg(1)))"
            case .radians: return "(\(arg(0)) * Math.PI / 180)"
            case .degrees: return "(\(arg(0)) * 180 / Math.PI)"
            case .saturate: return "Fx.sat(\(arg(0)))"
            case .min: return "Math.min(\(a.joined(separator: ", ")))"
            case .max: return "Math.max(\(a.joined(separator: ", ")))"
            case .mod: return "Fx.M(\(arg(0)), \(arg(1)))"
            case .step: return "(\(arg(1)) < \(arg(0)) ? 0 : 1)"
            case .clamp: return "Fx.clamp(\(arg(0)), \(arg(1)), \(arg(2)))"
            case .lerp, .mix: return "(\(arg(0)) + (\(arg(1)) - \(arg(0))) * \(arg(2)))"
            case .smoothstep: return "Fx.ss(\(arg(0)), \(arg(1)), \(arg(2)))"
            case .map: return "Fx.map(\(arg(0)), \(arg(1)), \(arg(2)), \(arg(3)), \(arg(4)))"
            case .if: return "(Fx.T(\(arg(0))) ? \(arg(1)) : \(arg(2)))"
            case .noise, .signedNoise: return "NaN"
            }
        }
    }

    private static func literal(_ v: Double) -> String {
        if v.isNaN { return "NaN" }
        if v.isInfinite { return v < 0 ? "(-Infinity)" : "Infinity" }
        if v < 0 { return "(\(v))" }
        return "\(v)"
    }
}

// MARK: - Reading a sketch's formulas

extension OllinApp {
    /// The formulas driving `sketch`'s parameters that the page can carry, in
    /// an order where a formula that reads another driven parameter comes
    /// after it. A formula that reads a noise field, or one caught in a ring
    /// of formulas that read each other (which the Mac leaves alone too),
    /// stays behind, and its parameter is then a plain recorded value.
    static func webFormulas(of sketch: Sketch) -> [WebFormula] {
        guard let automation = sketch.automation else { return [] }
        var handles: [String: ParamHandle] = [:]
        for handle in sketch.parameters() { handles[handle.name] = handle }

        var candidates: [WebFormula] = []
        for track in automation.tracks where track.isWorkedOut && !track.usesNoise {
            guard let handle = handles[track.name] else { continue }
            if let formula = track.formula {
                guard let js = FormulaJS.compile(formula) else { continue }
                var entry = WebFormula(name: track.name, source: formula.source, javaScript: js,
                                       reads: formula.variables, lowerBound: nil, upperBound: nil,
                                       step: nil, isInteger: false)
                switch handle.control {
                case .slider(let slider):
                    entry.lowerBound = slider.range.lowerBound
                    entry.upperBound = slider.range.upperBound
                    entry.step = slider.step
                case .stepper(let stepper):
                    entry.lowerBound = Double(stepper.range.lowerBound)
                    entry.upperBound = Double(stepper.range.upperBound)
                    entry.step = stepper.step > 1 ? Double(stepper.step) : nil
                    entry.isInteger = true
                case .toggle:
                    // A switch reads the number as on when it is anything but
                    // zero; nothing a shape column can be affine in.
                    continue
                default:
                    continue
                }
                candidates.append(entry)
            }
            for part in track.parts.keys.sorted() {
                guard let formula = track.parts[part], let js = FormulaJS.compile(formula) else { continue }
                candidates.append(WebFormula(name: "\(track.name).\(part)", source: formula.source,
                                             javaScript: js, reads: formula.variables,
                                             lowerBound: nil, upperBound: nil, step: nil, isInteger: false))
            }
        }

        // The order the Mac evaluates in: a formula after every driven name it
        // reads. What is left after that is a ring, and stays behind.
        let driven = Set(candidates.map(\.name))
        var ordered: [WebFormula] = []
        var pending = candidates
        var placed: Set<String> = []
        while !pending.isEmpty {
            guard let next = pending.firstIndex(where: { f in
                f.reads.allSatisfy { !driven.contains($0) || placed.contains($0) || $0 == f.name }
            }) else { break }
            let f = pending.remove(at: next)
            placed.insert(f.name)
            ordered.append(f)
        }
        return ordered
    }

    /// The numbers a formula may read besides the clock, the canvas, and the
    /// pointer: every parameter that is a number or a switch, and every part of
    /// one that holds more than one, as they stand now.
    static func webConstants(of sketch: Sketch) -> [String: Double] {
        var values: [String: Double] = [:]
        for handle in sketch.parameters() {
            switch handle.param.stored {
            case .number(let v): values[handle.name] = v
            case .boolean(let v): values[handle.name] = v ? 1 : 0
            default:
                for (part, number) in Automation.parts(of: handle.param.stored) {
                    values["\(handle.name).\(part)"] = number
                }
            }
        }
        return values
    }

    /// The value a driven name holds right now, read back from its parameter
    /// (which applies its own range), so the page fits against what the sketch
    /// drew with.
    static func webFormulaValue(named name: String, in handles: [String: ParamHandle]) -> Double? {
        if let handle = handles[name] {
            switch handle.param.stored {
            case .number(let v): return v
            case .boolean(let v): return v ? 1 : 0
            default: return nil
            }
        }
        guard let dot = name.lastIndex(of: ".") else { return nil }
        let base = String(name[..<dot]), part = String(name[name.index(after: dot)...])
        guard let handle = handles[base] else { return nil }
        return Automation.parts(of: handle.param.stored)[part]
    }

    /// The automation's clock, for the page to stand a formula's `time` on.
    static func webAutomationClock(of sketch: Sketch) -> WebAutomationClock? {
        guard let automation = sketch.automation else { return nil }
        return WebAutomationClock(start: automation.start, speed: automation.speed,
                                  loops: automation.loops, duration: automation.duration)
    }
}
