import Foundation

// MARK: - Parameters as controls

/// A parameter the page offers as a control: one of the sketch's `@Param`s, as
/// the recording found it, with the control its type asks for (a slider for a
/// number, a stepper for an integer, a switch, a color well, a field per part
/// of a point or a pair of ends). A parameter is offered only when the probe
/// could wire every effect it has on the recording, so a control on the page
/// moves the picture the way the Mac would have drawn it at that setting; the
/// rest stay at their recorded values and the exporter says why.
struct WebControl: Equatable {
    enum Kind: String {
        case number, integer, toggle, color, vector, vector3, range
    }

    /// One scalar of the control: a plain number or switch has one part named
    /// `""`; a color has `red`, `green`, `blue`, and `alpha`; a point `x` and
    /// `y`; a pair of ends `lower` and `upper`.
    struct Part: Equatable {
        var name: String
        var lower: Double
        var upper: Double
        var step: Double?
        /// The recording's axis that carries this part, or `nil` when the
        /// part stays at its recorded value (a color's alpha that nothing
        /// reads).
        var axis: Int?
    }

    var name: String
    var label: String
    var group: String?
    var kind: Kind
    var parts: [Part]
    /// The value the recording was made with, by part.
    var values: [String: Double]

    var meta: [String: Any] {
        var m: [String: Any] = [
            "name": name, "label": label, "kind": kind.rawValue,
            "parts": parts.map { p -> [String: Any] in
                var d: [String: Any] = ["name": p.name, "value": values[p.name] ?? 0, "axis": p.axis ?? -1]
                if p.lower.isFinite, p.upper.isFinite { d["lo"] = p.lower; d["hi"] = p.upper }
                if let s = p.step, s > 0 { d["step"] = s }
                return d
            },
        ]
        if let group { m["group"] = group }
        return m
    }
}

/// One scalar of a control and its effect on the recording: the columns it
/// moves, each with the slope the column has in it at every recorded frame.
/// The page adds `slope × (value − base)` onto the column, so a control moves
/// the picture without the Mac in the room.
struct WebAxis: Equatable {
    /// The control this axis belongs to, and its name as a formula reads it
    /// (`radius`, or `ink.red` for one part of a parameter).
    var control: Int
    var name: String
    /// The recorded value, which the page starts at.
    var base: Double
    var columns: [WebAxisColumn]
}

/// A column an axis moves. The region says which table the column indexes:
/// the frame vector, the scene block, or the per-frame facts (the clear's
/// three channels, then the exposure). The transform says what the column is
/// linear in: the value itself, or the value taken from sRGB to linear light,
/// which is how a color reaches the clear.
struct WebAxisColumn: Equatable {
    enum Region: Int {
        case vector = 0, scene = 1, fact = 2
    }
    var region: Region
    var index: Int
    var transform: Int
    /// The slope per recorded frame.
    var slopes: [Float]

    static let identity = 0
    static let srgbToLinear = 1
}

/// A parameter the page does not offer, and why, for the exporter's summary.
struct WebLeftOut: Equatable {
    var name: String
    var reason: String
}

// MARK: - The probe

extension OllinApp {
    /// What the probe found: the controls the page offers, their axes, and the
    /// parameters left at their recorded values.
    struct WebControlsResult {
        var controls: [WebControl] = []
        var axes: [WebAxis] = []
        var leftOut: [WebLeftOut] = []
    }

    /// A part of a parameter before the probe: what to set it to, and the
    /// settings to try.
    private struct WebAxisCandidate {
        var control: Int
        var part: String
        var name: String
        var base: Double
        /// The settings to try, in order, each flagged when it is an end of
        /// the range.
        var settings: [(value: Double, isEnd: Bool)]
        var isColorChannel: Bool
        var isBoolean: Bool
    }

    private enum WebProbeOutcome {
        case wired([WebAxisColumn])
        case inert
        case failed(String)
    }

    static let webReasonNoControl = "a kind the page has no control for"
    static let webReasonDriven = "driven by a formula"
    static let webReasonInert = "does not change the recording"
    static let webReasonCast = "changes what is drawn"
    static let webReasonNonlinear = "does not move the picture along a line"
    static let webReasonCoupled = "acts together with another parameter"
    static let webReasonNondeterministic = "the sketch draws differently on each run"

    /// Probe `sketch`'s parameters against `baseline`: each part of each
    /// parameter is set to a few other values on a fresh sketch, the recording
    /// is made again, and every column the setting moved is fitted to a line
    /// in it at every frame. A part whose columns all fit is wired; one that
    /// changes the cast, or moves a column some other way, leaves its
    /// parameter at its recorded value. Then the wired parts are moved together
    /// once, so a pair that only looks independent one at a time is caught.
    static func webControls(of sketch: Sketch, baseValues: [String: ParamStored], baseline: [WebFrame],
                            frames: Int, fps: Double, skip: Int, width: Int, height: Int,
                            remake: () -> Sketch) -> WebControlsResult {
        var result = WebControlsResult()
        var controls: [WebControl] = []
        var candidates: [WebAxisCandidate] = []

        // The names a formula drives, whole or by part: the page carries those
        // live already, and a control would fight the formula.
        var driven: Set<String> = []
        for track in sketch.automation?.tracks ?? [] where track.isWorkedOut {
            if track.formula != nil { driven.insert(track.name) }
            for part in track.parts.keys { driven.insert("\(track.name).\(part)") }
        }

        for handle in sketch.parameters() {
            guard let stored = baseValues[handle.name] else { continue }
            let name = handle.name
            var kind: WebControl.Kind
            var parts: [WebControl.Part] = []
            var values: [String: Double] = [:]
            var axisParts: [(part: String, base: Double, lower: Double, upper: Double, step: Double?, integer: Bool, color: Bool, bool: Bool)] = []
            switch (handle.control, stored) {
            case (.slider(let s), .number(let v)):
                kind = .number
                parts = [.init(name: "", lower: s.range.lowerBound, upper: s.range.upperBound, step: s.step, axis: nil)]
                values[""] = v
                axisParts = [("", v, s.range.lowerBound, s.range.upperBound, s.step, false, false, false)]
            case (.stepper(let s), .number(let v)):
                kind = .integer
                parts = [.init(name: "", lower: Double(s.range.lowerBound), upper: Double(s.range.upperBound), step: Double(max(1, s.step)), axis: nil)]
                values[""] = v
                axisParts = [("", v, Double(s.range.lowerBound), Double(s.range.upperBound), Double(max(1, s.step)), true, false, false)]
            case (.toggle, .boolean(let b)):
                kind = .toggle
                parts = [.init(name: "", lower: 0, upper: 1, step: 1, axis: nil)]
                values[""] = b ? 1 : 0
                axisParts = [("", b ? 1 : 0, 0, 1, 1, true, false, true)]
            case (.colorWell, .color(let r, let g, let b, let a)):
                kind = .color
                for (part, v) in [("red", r), ("green", g), ("blue", b), ("alpha", a)] {
                    parts.append(.init(name: part, lower: 0, upper: 1, step: nil, axis: nil))
                    values[part] = v
                    axisParts.append((part, v, 0, 1, nil, false, part != "alpha", false))
                }
            case (.vector(let c), .vector(let x, let y)):
                kind = .vector
                for (part, v, range) in [("x", x, c.xRange), ("y", y, c.yRange)] {
                    parts.append(.init(name: part, lower: range.lowerBound, upper: range.upperBound, step: nil, axis: nil))
                    values[part] = v
                    axisParts.append((part, v, range.lowerBound, range.upperBound, nil, false, false, false))
                }
            case (.vector3(let c), .vector3(let x, let y, let z)):
                kind = .vector3
                for (part, v, range) in [("x", x, c.xRange), ("y", y, c.yRange), ("z", z, c.zRange)] {
                    parts.append(.init(name: part, lower: range.lowerBound, upper: range.upperBound, step: nil, axis: nil))
                    values[part] = v
                    axisParts.append((part, v, range.lowerBound, range.upperBound, nil, false, false, false))
                }
            case (.range(let c), .range(let lower, let upper)):
                // The lower end probes below the upper and the upper above
                // the lower, since a crossed pair is put back in order.
                kind = .range
                parts = [.init(name: "lower", lower: c.outer.lowerBound, upper: c.outer.upperBound, step: nil, axis: nil),
                         .init(name: "upper", lower: c.outer.lowerBound, upper: c.outer.upperBound, step: nil, axis: nil)]
                values["lower"] = lower
                values["upper"] = upper
                axisParts = [("lower", lower, c.outer.lowerBound, upper, nil, false, false, false),
                             ("upper", upper, lower, c.outer.upperBound, nil, false, false, false)]
            default:
                result.leftOut.append(WebLeftOut(name: name, reason: webReasonNoControl))
                continue
            }
            let axisNames = axisParts.map { $0.part.isEmpty ? name : "\(name).\($0.part)" }
            if driven.contains(name) || axisNames.contains(where: driven.contains) {
                result.leftOut.append(WebLeftOut(name: name, reason: webReasonDriven))
                continue
            }
            let index = controls.count
            controls.append(WebControl(name: name, label: handle.label, group: handle.group, kind: kind,
                                       parts: parts, values: values))
            for (i, p) in axisParts.enumerated() {
                let settings: [(value: Double, isEnd: Bool)] = p.bool
                    ? [(p.base == 0 ? 1 : 0, false)]
                    : webProbeSettings(base: p.base, lower: p.lower, upper: p.upper, step: p.step, integer: p.integer)
                guard !settings.isEmpty else { continue }
                candidates.append(WebAxisCandidate(control: index, part: p.part, name: axisNames[i], base: p.base,
                                                   settings: settings, isColorChannel: p.color, isBoolean: p.bool))
            }
        }
        guard !controls.isEmpty else { return result }

        // A sketch that draws differently on a fresh run (unseeded randomness,
        // the clock) cannot be probed: every column would move on its own.
        do {
            let again = try webProbeRecording(remake: remake, width: width, height: height, frames: frames,
                                              fps: fps, skip: skip, settings: [])
            guard again == baseline else {
                for c in controls { result.leftOut.append(WebLeftOut(name: c.name, reason: webReasonNondeterministic)) }
                return result
            }
        } catch {
            for c in controls { result.leftOut.append(WebLeftOut(name: c.name, reason: webReasonNondeterministic)) }
            return result
        }

        // Each part on its own: three settings, or the one a switch has. An
        // end of the range that empties the cast (a radius of zero draws
        // nothing, a stroke with no alpha is skipped) is passed over, and the
        // line is fitted inside it; an inner setting that changes the cast
        // fails the part.
        var outcomes: [WebProbeOutcome] = []
        var used: [[Double]] = []
        for candidate in candidates {
            var probes: [[WebFrame]] = []
            var values: [Double] = []
            var outcome: WebProbeOutcome? = nil
            for setting in candidate.settings {
                if probes.count == 3 { break }
                do {
                    let frames = try webProbeRecording(remake: remake, width: width, height: height, frames: frames,
                                                       fps: fps, skip: skip,
                                                       settings: [(controls[candidate.control].name, candidate.part,
                                                                   setting.value, candidate.isBoolean)])
                    guard webSameCast(baseline, frames) else {
                        if setting.isEnd { continue }
                        outcome = .failed(webReasonCast)
                        break
                    }
                    probes.append(frames)
                    values.append(setting.value)
                } catch {
                    if setting.isEnd { continue }
                    outcome = .failed(webReasonCast)
                    break
                }
            }
            if outcome == nil, probes.count < (candidate.isBoolean ? 1 : 2) { outcome = .failed(webReasonCast) }
            used.append(values)
            if let outcome { outcomes.append(outcome); continue }
            let settings = [candidate.base] + values
            let recordings = [baseline] + probes
            var columns: [WebAxisColumn] = []
            var failed = false
            for region in [WebAxisColumn.Region.vector, .scene, .fact] {
                switch webFitAxis(settings: settings, recordings: recordings, region: region,
                                  colorChannel: candidate.isColorChannel) {
                case .wired(let found): columns += found
                case .inert: break
                case .failed: failed = true
                }
                if failed { break }
            }
            if failed { outcomes.append(.failed(webReasonNonlinear)) }
            else if columns.isEmpty { outcomes.append(.inert) }
            else { outcomes.append(.wired(columns)) }
        }

        // The wired parts together: a column that two parts move must move by
        // the sum of what each did alone, or neither is wired.
        var wired: [Int: [WebAxisColumn]] = [:]
        var reasons: [Int: String] = [:]
        for (i, outcome) in outcomes.enumerated() {
            switch outcome {
            case .wired(let columns): wired[i] = columns
            case .inert: break
            case .failed(let reason): reasons[i] = reason
            }
        }
        while wired.count >= 2 {
            let active = wired.keys.sorted()
            let settings = active.map { i -> (String, String, Double, Bool) in
                let c = candidates[i]
                return (controls[c.control].name, c.part, used[i][0], c.isBoolean)
            }
            let joint: [WebFrame]
            do {
                joint = try webProbeRecording(remake: remake, width: width, height: height, frames: frames,
                                              fps: fps, skip: skip, settings: settings)
            } catch {
                for i in active { wired[i] = nil; reasons[i] = webReasonCoupled }
                break
            }
            guard webSameCast(baseline, joint) else {
                for i in active { wired[i] = nil; reasons[i] = webReasonCoupled }
                break
            }
            var dropped: Set<Int> = []
            for region in [WebAxisColumn.Region.vector, .scene, .fact] {
                let failing = webSuperpositionFailures(baseline: baseline, joint: joint, region: region,
                                                       axes: active.map { i in
                    (columns: wired[i] ?? [], base: candidates[i].base, setting: used[i][0])
                })
                for column in failing {
                    for i in active where (wired[i] ?? []).contains(where: { $0.region == region && $0.index == column }) {
                        dropped.insert(i)
                    }
                }
            }
            guard !dropped.isEmpty else { break }
            for i in dropped { wired[i] = nil; reasons[i] = webReasonCoupled }
        }

        // A control is offered when every part that changes the recording is
        // wired; a color keeps its alpha at the recorded value when only the
        // alpha could not be, since a well without an opacity slider is still a well.
        for ci in controls.indices {
            var control = controls[ci]
            let mine = candidates.indices.filter { candidates[$0].control == ci }
            var anyWired = false
            var reason: String? = nil
            for i in mine {
                let part = candidates[i].part
                if let columns = wired[i] {
                    let axis = WebAxis(control: ci, name: candidates[i].name, base: candidates[i].base, columns: columns)
                    result.axes.append(axis)
                    if let p = control.parts.firstIndex(where: { $0.name == part }) { control.parts[p].axis = result.axes.count - 1 }
                    anyWired = true
                } else if let r = reasons[i] {
                    if control.kind == .color, part == "alpha" { continue }
                    reason = reason ?? r
                }
            }
            if let reason {
                result.axes.removeAll { $0.control == ci }
                result.leftOut.append(WebLeftOut(name: control.name, reason: reason))
                continue
            }
            guard anyWired else {
                result.leftOut.append(WebLeftOut(name: control.name, reason: webReasonInert))
                continue
            }
            result.controls.append(control)
        }
        // The axes point at their control by index; renumber onto the offered list.
        var renumbered: [WebAxis] = []
        for (ci, control) in result.controls.enumerated() {
            for (pi, part) in control.parts.enumerated() {
                guard let a = part.axis else { continue }
                var axis = result.axes[a]
                axis.control = ci
                result.controls[ci].parts[pi].axis = renumbered.count
                renumbered.append(axis)
            }
        }
        result.axes = renumbered
        return result
    }

    /// The other values to set a part to, in the order to try them: the ends
    /// of its range, then two points inside it at the golden section, so no
    /// symmetric curve passes as a line; snapped to the step, never the
    /// recorded value itself. The probe takes the first three that keep the
    /// cast. A part with no finite range probes a span around its value.
    static func webProbeSettings(base: Double, lower: Double, upper: Double, step: Double?,
                                 integer: Bool) -> [(value: Double, isEnd: Bool)] {
        var lo = lower, hi = upper
        if !lo.isFinite || !hi.isFinite || hi <= lo {
            let span = max(1, abs(base))
            lo = base - span
            hi = base + span
        }
        var out: [(value: Double, isEnd: Bool)] = []
        for (raw, isEnd) in [(lo, true), (hi, true), (lo + 0.381966 * (hi - lo), false), (lo + 0.618034 * (hi - lo), false)] {
            var x = raw
            if let step, step > 0 { x = min(hi, lo + ((x - lo) / step).rounded() * step) }
            if integer { x = x.rounded() }
            let scale = max(1, abs(x), abs(base))
            if abs(x - base) <= 1e-9 * scale { continue }
            if out.contains(where: { abs($0.value - x) <= 1e-9 * scale }) { continue }
            out.append((x, isEnd))
        }
        return out
    }

    /// A fresh sketch with `settings` applied after its `setup()`, recorded
    /// over the same frames as the baseline.
    private static func webProbeRecording(remake: () -> Sketch, width: Int, height: Int, frames: Int, fps: Double,
                                          skip: Int, settings: [(name: String, part: String, value: Double, isBoolean: Bool)]) throws -> [WebFrame] {
        let probe = remake()
        probe.setCanvasSize(width: Double(width), height: Double(height))
        probe.runSetup()
        var handles: [String: ParamHandle] = [:]
        for handle in probe.parameters() where handles[handle.name] == nil { handles[handle.name] = handle }
        for s in settings {
            guard let handle = handles[s.name] else {
                throw WebExportRefusal(call: "a parameter a fresh sketch does not declare (\(s.name))", frame: 0)
            }
            let stored: ParamStored
            if s.part.isEmpty {
                stored = s.isBoolean ? .boolean(s.value != 0) : .number(s.value)
            } else {
                stored = Automation.applying([s.part: s.value], to: handle.param.stored)
            }
            handle.param.restore(stored)
        }
        return try runWebFrames(probe, frames: frames, fps: fps, skip: skip, width: width, height: height,
                                recorder: WebGraphRecorder())
    }

    /// Whether two recordings are the same cast frame for frame: the graph,
    /// the lengths, and every column that names a thing rather than measures
    /// it (a shape's tag, a gradient's row, a program's kinds and length).
    static func webSameCast(_ a: [WebFrame], _ b: [WebFrame]) -> Bool {
        guard a.count == b.count else { return false }
        for k in a.indices {
            let x = a[k], y = b[k]
            guard x.graph == y.graph, x.vector.count == y.vector.count, x.scene.count == y.scene.count,
                  (x.clear == nil) == (y.clear == nil), x.toneMapMode == y.toneMapMode else { return false }
            for c in webDiscreteColumns(of: x.graph) where x.vector[c] != y.vector[c] { return false }
        }
        return true
    }

    /// The columns of a frame whose value names a thing: the structural
    /// columns of the field programs, a shape's tag and its two gradient rows,
    /// a composed field's paint kinds and rows, a raymarched field's.
    static func webDiscreteColumns(of g: WebGraph) -> [Int] {
        var columns = g.structuralColumns
        for i in 0 ..< g.instanceCount {
            let o = i * WebInstance.floats
            columns += [o + WebInstance.shapeColumn, o + 28, o + 29]
        }
        for i in 0 ..< g.groupCount {
            let o = g.groupOffset + i * WebGroup.floats
            columns += [o + 22, o + 23, o + 24, o + 25]
        }
        for i in 0 ..< g.fieldCount {
            let o = g.fieldOffset + i * WebField.floats
            columns += [o + 30, o + 31]
        }
        return columns
    }

    /// One region of a frame as the probe reads it.
    private static func webRegion(_ f: WebFrame, _ region: WebAxisColumn.Region) -> [Float] {
        switch region {
        case .vector: return f.vector
        case .scene: return f.scene
        case .fact:
            if let c = f.clear { return [c.x, c.y, c.z, f.exposure] }
            return [.nan, .nan, .nan, f.exposure]
        }
    }

    /// How far a column may stray from its line: a ten-thousandth of what it
    /// moved by, or a few float32 steps at its size, whichever is larger.
    private static func webTolerance(spread: Float, magnitude: Float) -> Float {
        max(spread * 1e-4, magnitude * 4e-6, 1e-6)
    }

    private static func webTransform(_ x: Double, _ transform: Int) -> Double {
        transform == WebAxisColumn.srgbToLinear ? Color.srgbToLinear(min(max(x, 0), 1)) : x
    }

    /// The columns of `region` that the settings move, each fitted to a line
    /// in the setting at every frame (through the setting itself first, then
    /// through its linear-light value for a color channel), with its slope per
    /// frame. `.inert` when nothing moved, `.failed` when a moved column fits
    /// no line.
    private static func webFitAxis(settings: [Double], recordings: [[WebFrame]], region: WebAxisColumn.Region,
                                   colorChannel: Bool) -> WebProbeOutcome {
        let n = recordings[0].count
        let m = settings.count
        let values = recordings.map { $0.map { webRegion($0, region) } }
        let discrete = Set(recordings[0].flatMap { webDiscreteColumns(of: $0.graph) })
        // Which columns move, and how far each may stray.
        var magnitude: [Int: Float] = [:]
        var spread: [Int: Float] = [:]
        for k in 0 ..< n {
            let count = values[0][k].count
            for c in 0 ..< count {
                var lo = Float.greatestFiniteMagnitude, hi = -Float.greatestFiniteMagnitude
                for j in 0 ..< m {
                    let v = values[j][k][c]
                    if v.isNaN { continue }
                    lo = min(lo, v)
                    hi = max(hi, v)
                    magnitude[c] = max(magnitude[c] ?? 0, abs(v))
                }
                if lo <= hi { spread[c] = max(spread[c] ?? 0, hi - lo) }
            }
        }
        var touched: [Int] = []
        for (c, s) in spread where s > webTolerance(spread: s, magnitude: magnitude[c] ?? 0) {
            if region == .vector, discrete.contains(c) { return .failed(webReasonCast) }
            touched.append(c)
        }
        touched.sort()
        guard !touched.isEmpty else { return .inert }

        var columns: [WebAxisColumn] = []
        for c in touched {
            let tolerance = webTolerance(spread: spread[c] ?? 0, magnitude: magnitude[c] ?? 0)
            var fitted: WebAxisColumn? = nil
            for transform in [WebAxisColumn.identity] + (colorChannel ? [WebAxisColumn.srgbToLinear] : []) {
                let xs = settings.map { webTransform($0, transform) }
                let mx = xs.reduce(0, +) / Double(m)
                let variance = xs.reduce(0) { $0 + ($1 - mx) * ($1 - mx) }
                guard variance > 0 else { break }
                var slopes = [Float](repeating: 0, count: n)
                var ok = true
                for k in 0 ..< n {
                    guard c < values[0][k].count else { continue }
                    let vs = (0 ..< m).map { Double(values[$0][k][c]) }
                    if vs.contains(where: \.isNaN) { continue }
                    let mv = vs.reduce(0, +) / Double(m)
                    var covariance = 0.0
                    for j in 0 ..< m { covariance += (xs[j] - mx) * (vs[j] - mv) }
                    let slope = covariance / variance
                    let intercept = mv - slope * mx
                    for j in 0 ..< m where abs(vs[j] - (intercept + slope * xs[j])) > Double(tolerance) {
                        ok = false
                        break
                    }
                    if !ok { break }
                    slopes[k] = Float(slope)
                }
                if ok {
                    fitted = WebAxisColumn(region: region, index: c, transform: transform, slopes: slopes)
                    break
                }
            }
            guard let fitted else { return .failed(webReasonNonlinear) }
            columns.append(fitted)
        }
        return .wired(columns)
    }

    /// The columns of `region` that the joint recording moves by other than
    /// the sum of what each axis did alone.
    private static func webSuperpositionFailures(baseline: [WebFrame], joint: [WebFrame], region: WebAxisColumn.Region,
                                                 axes: [(columns: [WebAxisColumn], base: Double, setting: Double)]) -> Set<Int> {
        var failing: Set<Int> = []
        for k in baseline.indices {
            let base = webRegion(baseline[k], region)
            let observed = webRegion(joint[k], region)
            guard base.count == observed.count else { continue }
            var predicted = base
            var involved: Set<Int> = []
            for axis in axes {
                for column in axis.columns where column.region == region && column.index < predicted.count {
                    let delta = webTransform(axis.setting, column.transform) - webTransform(axis.base, column.transform)
                    predicted[column.index] += Float(Double(column.slopes[k]) * delta)
                    involved.insert(column.index)
                }
            }
            for c in involved where !base[c].isNaN {
                let spread = abs(observed[c] - base[c])
                let tolerance = 2 * webTolerance(spread: spread, magnitude: max(abs(observed[c]), abs(base[c])))
                if abs(observed[c] - predicted[c]) > tolerance { failing.insert(c) }
            }
        }
        return failing
    }
}
