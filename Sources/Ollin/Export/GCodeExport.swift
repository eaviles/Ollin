import Foundation
import simd

// G-code export: the machine-facing vector sink beside the SVG and PDF
// serializers. The same recorded frame (see SVGExport.swift) is flattened to
// line work, clipped to the canvas, ordered to shorten pen-up travel, and
// written as a G-code program a pen plotter, laser cutter, or CNC router runs
// directly. Everything up to the final text stays in canvas space; physical
// millimeters enter only at emission, where the y axis also flips, because a
// canvas grows downward while a machine bed grows upward from its origin.
//
// The public core is `GCode` plus `Toolpath`, callable from a sketch (preview
// the plot order, measure pen-down and travel distance, feed the program
// text anywhere); `OllinApp.gcode(of:)` / `exportGCode` are the sugar over it.
//
// Dialect notes the emitters encode, so they are not re-derived per machine:
// a laser controller fires only during feed moves (G1) and always blanks the
// beam on a rapid (G0), so travels are rapids and no off command is needed
// between paths; the power word S and the feed F are modal, written only when
// they change; the program is absolute millimeters (G90, G21) ending in M2.

// MARK: - Settings

/// How a frame's line work becomes a G-code program for one machine. Create it
/// with a machine profile and the physical width the canvas maps to, then hand
/// it contours (`toolpath(_:in:)` / `program(_:in:)`) or a whole sketch
/// (`OllinApp.gcode(of:settings:)`).
///
/// Only line work travels: a stroke is plotted along its centerline (a pen has
/// its own width), and a solid fill contributes its outline unless a
/// `Hatching` turns it into line shading first.
public struct GCode: Equatable, Sendable {

    /// How a plotter lifts and lowers its pen between paths.
    public enum Pen: Equatable, Sendable {
        /// The controller moves a real or virtual Z axis: `down` to draw,
        /// `up` to travel (many pen machines treat any Z above zero as up).
        case zAxis(up: Double, down: Double)
        /// The controller drives a servo through the spindle-power word:
        /// `M3 S<down>` lowers the pen, `M3 S<up>` raises it, each followed by
        /// a short dwell so the servo lands before the head moves. The two
        /// values are whatever the controller maps its servo range to.
        case servo(up: Double, down: Double)
    }

    /// How a laser's power is applied along a cut.
    public enum LaserMode: Equatable, Sendable {
        /// Power scales with the head's actual speed (M4), so corners where
        /// it slows to turn do not scorch. Prefer this when the controller
        /// supports it.
        case dynamic
        /// Power held constant while cutting (M3).
        case constant
    }

    /// The machine a program is written for. Use the factory for the machine
    /// you have; each carries its own curated defaults.
    public struct Machine: Equatable, Sendable {
        enum Kind: Equatable, Sendable {
            case plotter(pen: Pen, feed: Double)
            case laser(power: Double, mode: LaserMode, feed: Double,
                       passes: Int, powerScale: Double)
            case mill(depth: Double, depthPerPass: Double, safeHeight: Double,
                      feed: Double, plungeFeed: Double, spindleSpeed: Double)
        }
        var kind: Kind

        /// A pen plotter. `pen` is how the pen lifts (Z hop by default);
        /// `feed` is the drawing speed in mm/min.
        public static func plotter(pen: Pen = .zAxis(up: 5, down: 0),
                                   feed: Double = 2400) -> Machine {
            Machine(kind: .plotter(pen: pen, feed: feed))
        }

        /// A laser cutter or engraver. `power` is 0...1 of full power, written
        /// as the S word scaled by `powerScale` (most controllers default the
        /// full-power S value to 1000). `passes` repeats each path in place,
        /// for cutting through in several light passes.
        public static func laser(power: Double = 0.75, mode: LaserMode = .dynamic,
                                 feed: Double = 1200, passes: Int = 1,
                                 powerScale: Double = 1000) -> Machine {
            Machine(kind: .laser(power: min(max(power, 0), 1), mode: mode,
                                 feed: feed, passes: max(1, passes),
                                 powerScale: powerScale))
        }

        /// A CNC router or mill cutting `depth` mm into the stock, at most
        /// `depthPerPass` mm per pass. Travels happen at `safeHeight` above
        /// the stock; plunges use `plungeFeed`, cuts use `feed` (mm/min).
        public static func mill(depth: Double = 1, depthPerPass: Double = 0.5,
                                safeHeight: Double = 5, feed: Double = 600,
                                plungeFeed: Double = 200,
                                spindleSpeed: Double = 10000) -> Machine {
            Machine(kind: .mill(depth: max(0, depth),
                                depthPerPass: max(0.01, depthPerPass),
                                safeHeight: safeHeight, feed: feed,
                                plungeFeed: plungeFeed, spindleSpeed: spindleSpeed))
        }
    }

    public var machine: Machine

    /// Physical width of the drawn area, in millimeters: the canvas width maps
    /// to exactly this, and the height follows the canvas aspect. Explicit on
    /// purpose, the same way a mesh export asks for its size: a machine needs
    /// real units, and a silent default would cut at a silent size.
    public var width: Double

    /// Extra border in millimeters between the machine origin and the drawing,
    /// added on all sides. The total footprint is `width + 2 * margin` across.
    public var margin: Double

    /// Reorder the paths so pen-up travel between them is short (a greedy
    /// nearest-neighbor walk from the machine origin, free to reverse a path
    /// or start a closed loop at any of its points). Off, paths run in draw
    /// order.
    public var optimizesTravel: Bool

    /// Open paths whose ends meet within this distance (millimeters) merge
    /// into one, so the pen stays down across what was drawn as several calls.
    /// A merged path whose own ends meet closes into a loop. Zero disables it.
    public var joinTolerance: Double

    public init(_ machine: Machine, width: Double, margin: Double = 0,
                optimizesTravel: Bool = true, joinTolerance: Double = 0.1) {
        self.machine = machine
        self.width = width
        self.margin = margin
        self.optimizesTravel = optimizesTravel
        self.joinTolerance = joinTolerance
    }

    /// Plan the machine's route through `paths` (canvas-space contours,
    /// treated as line work): clip to `canvas`, merge touching ends, order to
    /// shorten travel, and measure. The result previews and emits.
    public func toolpath(_ paths: [Contour], in canvas: Rectangle) -> Toolpath {
        plan(paths, in: canvas, alreadyClipped: false)
    }

    /// The finished G-code program for `paths`: `toolpath(_:in:)` emitted.
    public func program(_ paths: [Contour], in canvas: Rectangle) -> String {
        toolpath(paths, in: canvas).program
    }

    /// Shared planner behind the public `toolpath` and the frame exporter
    /// (whose flattener has already clipped fills and strokes exactly).
    func plan(_ paths: [Contour], in canvas: Rectangle, alreadyClipped: Bool) -> Toolpath {
        let scale = width / max(canvas.width, 1e-9)
        var work = paths.filter { $0.points.count >= 2 }
        if !alreadyClipped {
            let page = canvasShape(canvas)
            work = work.flatMap { clipPolyline($0, to: page, convexAllInside: canvas) }
        }
        if joinTolerance > 0 {
            work = mergedPaths(work, tolerance: joinTolerance / scale, sequentialOnly: !optimizesTravel)
        }
        let origin = Vector2(canvas.x, canvas.y + canvas.height)
        if optimizesTravel {
            work = orderedPaths(work, from: origin)
        }
        var travels: [(from: Vector2, to: Vector2)] = []
        var drawn = 0.0
        var position = origin
        for path in work {
            travels.append((from: position, to: path.points[0]))
            drawn += pathLength(path)
            position = path.isClosed ? path.points[0] : path.points[path.points.count - 1]
        }
        travels.append((from: position, to: origin))
        let travel = travels.reduce(0.0) { $0 + $1.from.distance(to: $1.to) }
        return Toolpath(paths: work, travels: travels,
                        drawnLength: drawn * scale, travelLength: travel * scale,
                        settings: self, canvas: canvas)
    }
}

// MARK: - Toolpath

/// A planned machine route: the line work in plot order (canvas space), the
/// pen-up travels between paths (from the machine origin and back to it), the
/// measured distances, and the G-code text. Made by `GCode.toolpath(_:in:)`;
/// a sketch can draw `paths` and `travels` to preview the plot.
public struct Toolpath: Sendable {
    /// The line work, clipped, merged, and in the order the machine runs it.
    public var paths: [Contour]
    /// The pen-up moves: origin to the first path, between paths, and home
    /// again. Canvas space, like `paths`.
    public var travels: [(from: Vector2, to: Vector2)]
    /// Millimeters of pen-down (or cutting) motion, over one pass.
    public var drawnLength: Double
    /// Millimeters of pen-up travel, the part ordering works to shrink.
    public var travelLength: Double
    var settings: GCode
    var canvas: Rectangle

    /// The G-code program text.
    public var program: String { text(recipe: nil, skippedImages: 0) }
}

// MARK: - Geometry helpers

private func pathLength(_ contour: Contour) -> Double {
    let pts = contour.points
    guard pts.count >= 2 else { return 0 }
    var total = 0.0
    for i in 0..<(pts.count - 1) { total += pts[i].distance(to: pts[i + 1]) }
    if contour.isClosed { total += pts[pts.count - 1].distance(to: pts[0]) }
    return total
}

func canvasShape(_ rect: Rectangle) -> Shape {
    Shape([Vector2(rect.x, rect.y),
           Vector2(rect.x + rect.width, rect.y),
           Vector2(rect.x + rect.width, rect.y + rect.height),
           Vector2(rect.x, rect.y + rect.height)])
}

/// Clip a polyline (open or closed) to the filled region of `shape`, honoring
/// its winding: the pieces inside survive as open paths, and a contour that
/// never leaves stays whole. When `convexAllInside` is the rectangle `shape`
/// outlines, a contour with every point inside skips the segment work (inside
/// a convex region, the segments between inside points cannot leave).
func clipPolyline(_ contour: Contour, to shape: Shape,
                  convexAllInside: Rectangle? = nil) -> [Contour] {
    let pts = contour.points
    guard pts.count >= 2 else { return [] }
    if let rect = convexAllInside, pts.allSatisfy({ rect.contains($0) }) {
        return [contour]
    }
    var walk = pts
    if contour.isClosed { walk.append(pts[0]) }

    var pieces: [[Vector2]] = []
    var run: [Vector2] = []
    var anyExcluded = false
    func endRun() {
        if run.count >= 2 { pieces.append(run) }
        run = []
    }
    func keep(_ a: Vector2, _ b: Vector2) {
        if let last = run.last, last.distanceSquared(to: a) < 1e-18 {
            run.append(b)
        } else {
            endRun()
            run = [a, b]
        }
    }
    for i in 0..<(walk.count - 1) {
        let a = walk[i], b = walk[i + 1]
        var ts: [Double] = [0, 1]
        for clipContour in shape.contours {
            let cpts = clipContour.points
            guard cpts.count >= 2 else { continue }
            for j in cpts.indices {
                let c = cpts[j], d = cpts[(j + 1) % cpts.count]
                let r = b - a, s = d - c
                let denominator = r.x * s.y - r.y * s.x
                guard abs(denominator) > 1e-12 else { continue }
                let qp = c - a
                let t = (qp.x * s.y - qp.y * s.x) / denominator
                let u = (qp.x * r.y - qp.y * r.x) / denominator
                if t > 0, t < 1, u >= 0, u < 1 { ts.append(t) }
            }
        }
        ts.sort()
        for k in 0..<(ts.count - 1) {
            let t0 = ts[k], t1 = ts[k + 1]
            guard t1 - t0 > 1e-9 else { continue }
            let mid = a + (b - a) * ((t0 + t1) / 2)
            if shape.contains(mid) {
                keep(a + (b - a) * t0, a + (b - a) * t1)
            } else {
                anyExcluded = true
                endRun()
            }
        }
    }
    endRun()
    if !anyExcluded, pieces.count == 1 {
        return [contour]                       // untouched: keep exact points
    }
    // A clipped closed contour re-enters at its seam: when the first piece
    // starts where the last one ends (the original start point), they are one.
    if contour.isClosed, pieces.count >= 2,
       let firstStart = pieces.first?.first, let lastEnd = pieces.last?.last,
       firstStart.distanceSquared(to: lastEnd) < 1e-12 {
        var joined = pieces.removeLast()
        joined.append(contentsOf: pieces.removeFirst().dropFirst())
        pieces.append(joined)
    }
    return pieces.map { Contour($0, closed: false) }
}

/// Merge open paths whose ends meet within `tolerance` (canvas units) so the
/// pen stays down across them; a chain whose own ends meet becomes a closed
/// loop. `sequentialOnly` restricts the search to neighbors in draw order,
/// for when the caller asked the overall order to be preserved.
func mergedPaths(_ paths: [Contour], tolerance: Double, sequentialOnly: Bool) -> [Contour] {
    guard tolerance > 0 else { return paths }
    let tolSquared = tolerance * tolerance
    var out: [Contour] = []
    var pool = paths
    var index = 0
    while index < pool.count {
        let base = pool[index]
        guard !base.isClosed else { out.append(base); index += 1; continue }
        var chain = base.points
        var extended = true
        while extended {
            extended = false
            var j = index + 1
            while j < pool.count {
                let candidate = pool[j]
                if candidate.isClosed { j += 1; continue }
                if sequentialOnly && j != index + 1 { break }
                let cpts = candidate.points
                if chain[chain.count - 1].distanceSquared(to: cpts[0]) < tolSquared {
                    chain.append(contentsOf: cpts.dropFirst())
                } else if chain[chain.count - 1].distanceSquared(to: cpts[cpts.count - 1]) < tolSquared {
                    chain.append(contentsOf: cpts.reversed().dropFirst())
                } else if chain[0].distanceSquared(to: cpts[cpts.count - 1]) < tolSquared {
                    chain.insert(contentsOf: cpts.dropLast(), at: 0)
                } else if chain[0].distanceSquared(to: cpts[0]) < tolSquared {
                    chain.insert(contentsOf: cpts.reversed().dropLast(), at: 0)
                } else {
                    j += 1
                    continue
                }
                pool.remove(at: j)
                extended = true
            }
        }
        if chain.count >= 4, chain[0].distanceSquared(to: chain[chain.count - 1]) < tolSquared {
            chain.removeLast()
            out.append(Contour(chain, closed: true))
        } else {
            out.append(Contour(chain, closed: false))
        }
        index += 1
    }
    return out
}

/// One step of the greedy tour: which of the original paths to take next, and
/// which of its vertices to enter at. A closed path rotates to start there; an
/// open one entered at its last vertex is walked backwards.
package struct PathOrderStep: Equatable, Sendable {
    /// Index into the array handed to `orderedPathSteps`.
    package var index: Int
    /// Vertex index to enter at: any vertex of a closed path, the first or the
    /// last of an open one.
    package var entry: Int
}

/// Plan a greedy nearest-neighbor walk over `paths` from `origin`: each step
/// takes the path whose nearest usable entry point is closest, reversing an
/// open path or rotating a closed one to enter there.
///
/// The plan is separate from applying it because two callers need the same
/// tour over different path types: the plotter walks `Contour`s, and the laser
/// walks paths that also carry a color per point, which have to be reversed
/// and rotated alongside their points.
package func orderedPathSteps(_ paths: [Contour], from origin: Vector2) -> [PathOrderStep] {
    var remaining = Array(paths.enumerated())
    var steps: [PathOrderStep] = []
    steps.reserveCapacity(paths.count)
    var position = origin
    while !remaining.isEmpty {
        var bestIndex = 0
        var bestDistance = Double.infinity
        var bestEntry = 0                     // vertex index (closed) or 0/last (open)
        for (i, entry) in remaining.enumerated() {
            let path = entry.element
            if path.isClosed {
                for (v, point) in path.points.enumerated() {
                    let d = position.distanceSquared(to: point)
                    if d < bestDistance { bestDistance = d; bestIndex = i; bestEntry = v }
                }
            } else {
                let start = position.distanceSquared(to: path.points[0])
                if start < bestDistance { bestDistance = start; bestIndex = i; bestEntry = 0 }
                let last = path.points.count - 1
                let end = position.distanceSquared(to: path.points[last])
                if end < bestDistance { bestDistance = end; bestIndex = i; bestEntry = last }
            }
        }
        let chosen = remaining.remove(at: bestIndex)
        let path = chosen.element
        if path.isClosed {
            position = path.points[bestEntry]
        } else {
            position = bestEntry == 0 ? path.points[path.points.count - 1] : path.points[0]
        }
        steps.append(PathOrderStep(index: chosen.offset, entry: bestEntry))
    }
    return steps
}

/// Order paths by the greedy walk `orderedPathSteps` plans, applied to the
/// contours themselves.
func orderedPaths(_ paths: [Contour], from origin: Vector2) -> [Contour] {
    orderedPathSteps(paths, from: origin).map { step in
        let path = paths[step.index]
        if path.isClosed {
            guard step.entry > 0 else { return path }
            return Contour(Array(path.points[step.entry...]) + Array(path.points[..<step.entry]),
                           closed: true)
        }
        guard step.entry != 0 else { return path }
        return Contour(path.points.reversed(), closed: false)
    }
}

// MARK: - Emission

private func num(_ value: Double) -> String {
    var s = String(format: "%.3f", value)
    while s.hasSuffix("0") { s.removeLast() }
    if s.hasSuffix(".") { s.removeLast() }
    return s == "-0" ? "0" : s
}

extension Toolpath {
    /// Emit the program. The exporter passes the reproduction recipe and the
    /// skipped-image count; the public `program` passes neither.
    func text(recipe: String?, skippedImages: Int) -> String {
        let scale = settings.width / max(canvas.width, 1e-9)
        let heightMM = canvas.height * scale
        func mapped(_ p: Vector2) -> Vector2 {
            Vector2(settings.margin + (p.x - canvas.x) * scale,
                    settings.margin + (canvas.y + canvas.height - p.y) * scale)
        }

        var lines: [String] = []
        if let recipe {
            for line in recipe.split(separator: "\n") { lines.append("; \(line)") }
        }
        lines.append("; canvas \(num(canvas.width)) x \(num(canvas.height)) px maps to "
                     + "\(num(settings.width)) x \(num(heightMM)) mm"
                     + (settings.margin > 0 ? ", margin \(num(settings.margin)) mm" : ""))
        lines.append("; \(machineDescription)")
        lines.append("; paths \(paths.count), draw \(num(drawnLength)) mm, travel \(num(travelLength)) mm")
        if skippedImages > 0 {
            lines.append(skippedImages == 1
                ? "; note: 1 image draw call has no line work and was skipped"
                : "; note: \(skippedImages) image draw calls have no line work and were skipped")
        }
        lines.append("G21 ; millimeters")
        lines.append("G90 ; absolute coordinates")
        lines.append("G17 ; XY plane")

        var modalF: Double?
        var modalS: Double?
        func rapid(_ p: Vector2) { lines.append("G0 X\(num(p.x)) Y\(num(p.y))") }
        func cut(_ p: Vector2, feed: Double, power: Double? = nil) {
            var line = "G1 X\(num(p.x)) Y\(num(p.y))"
            if let power, modalS != power { line += " S\(num(power))"; modalS = power }
            if modalF != feed { line += " F\(num(feed))"; modalF = feed }
            lines.append(line)
        }

        switch settings.machine.kind {
        case let .plotter(pen, feed):
            func penUp() {
                switch pen {
                case let .zAxis(up, _): lines.append("G0 Z\(num(up))")
                case let .servo(up, _): lines.append("M3 S\(num(up))"); lines.append("G4 P0.15")
                }
            }
            func penDown() {
                switch pen {
                case let .zAxis(_, down): lines.append("G0 Z\(num(down))")
                case let .servo(_, down): lines.append("M3 S\(num(down))"); lines.append("G4 P0.15")
                }
            }
            penUp()
            for path in paths {
                let pts = path.points.map(mapped)
                rapid(pts[0])
                penDown()
                for p in pts.dropFirst() { cut(p, feed: feed) }
                if path.isClosed { cut(pts[0], feed: feed) }
                penUp()
            }

        case let .laser(power, mode, feed, passes, powerScale):
            lines.append(mode == .dynamic ? "M4 S0 ; laser enabled, zero power"
                                          : "M3 S0 ; laser enabled, zero power")
            let s = min(max(power, 0), 1) * powerScale
            for path in paths {
                let pts = path.points.map(mapped)
                for _ in 0..<passes {
                    rapid(pts[0])
                    for p in pts.dropFirst() { cut(p, feed: feed, power: s) }
                    if path.isClosed { cut(pts[0], feed: feed, power: s) }
                }
            }
            lines.append("M5 ; laser off")

        case let .mill(depth, depthPerPass, safeHeight, feed, plungeFeed, spindleSpeed):
            lines.append("M3 S\(num(spindleSpeed)) ; spindle on")
            lines.append("G0 Z\(num(safeHeight))")
            var levels: [Double] = []
            var z = 0.0
            let step = min(depthPerPass, max(depth, 0.01))
            while z > -depth + 1e-9 {
                z = max(z - step, -depth)
                levels.append(z)
            }
            func plunge(to z: Double) {
                var line = "G1 Z\(num(z))"
                if modalF != plungeFeed { line += " F\(num(plungeFeed))"; modalF = plungeFeed }
                lines.append(line)
            }
            for path in paths {
                let pts = path.points.map(mapped)
                if path.isClosed {
                    // A loop ends where it starts, so each pass plunges deeper
                    // without retracting between them.
                    rapid(pts[0])
                    for level in levels {
                        plunge(to: level)
                        for p in pts.dropFirst() { cut(p, feed: feed) }
                        cut(pts[0], feed: feed)
                    }
                    lines.append("G0 Z\(num(safeHeight))")
                } else {
                    for level in levels {
                        rapid(pts[0])
                        plunge(to: level)
                        for p in pts.dropFirst() { cut(p, feed: feed) }
                        lines.append("G0 Z\(num(safeHeight))")
                    }
                }
            }
            lines.append("M5 ; spindle off")
        }

        lines.append("G0 X0 Y0 ; home")
        lines.append("M2 ; end")
        return lines.joined(separator: "\n") + "\n"
    }

    private var machineDescription: String {
        switch settings.machine.kind {
        case let .plotter(pen, feed):
            let penWords: String
            switch pen {
            case let .zAxis(up, down): penWords = "pen up Z\(num(up)), down Z\(num(down))"
            case let .servo(up, down): penWords = "pen servo up S\(num(up)), down S\(num(down))"
            }
            return "machine: pen plotter, feed \(num(feed)) mm/min, \(penWords)"
        case let .laser(power, mode, feed, passes, powerScale):
            let clamped = min(max(power, 0), 1)
            return "machine: laser, power \(num(clamped * 100))% (S\(num(clamped * powerScale))), "
                 + "\(mode == .dynamic ? "dynamic" : "constant") power, feed \(num(feed)) mm/min, "
                 + "\(passes) pass\(passes == 1 ? "" : "es")"
        case let .mill(depth, depthPerPass, safeHeight, feed, plungeFeed, spindleSpeed):
            return "machine: mill, depth \(num(depth)) mm in \(num(min(depthPerPass, max(depth, 0.01)))) mm passes, "
                 + "safe Z\(num(safeHeight)), spindle \(num(spindleSpeed)) rpm, "
                 + "feed \(num(feed)) mm/min, plunge \(num(plungeFeed)) mm/min"
        }
    }
}

// MARK: - Flattening a recorded frame

/// Flatten one recorded frame to plot-ready contours in canvas space: strokes
/// along their centerlines, fills as their outlines (a `Hatching` has already
/// turned fills into line work when one was asked for), clip regions applied
/// exactly, and everything clipped to the canvas. Fills clip as regions (a
/// boolean intersection keeps the closing edge the render shows at a clip or
/// canvas boundary); strokes clip as lines (only the visible part of an
/// outline plots).
func gcodeContours(_ commands: [SVGCommand], canvas: Rectangle) -> [Contour] {
    let page = canvasShape(canvas)
    var clipStack: [Shape] = []
    var out: [Contour] = []
    for command in commands {
        switch command {
        case let .clipPush(shape, transform):
            clipStack.append(Shape(contours: shape.contours.map {
                Contour($0.points.map { transformed($0, transform) }, closed: $0.isClosed)
            }, winding: shape.winding))
        case .clipPop:
            if !clipStack.isEmpty { clipStack.removeLast() }
        case let .draw(record):
            let toDevice = { (p: Vector2) in transformed(p, record.transform) }
            if record.style.stroke != nil {
                let strokePaths = record.geometry.strokePaths
                    ?? fillContours(record.geometry).map { outline in
                        outline.contours.map { ($0, true) }
                    } ?? []
                for (points, closed) in strokePaths {
                    var pieces = [Contour(points.map(toDevice), closed: closed)]
                    for clip in clipStack {
                        pieces = pieces.flatMap { clipPolyline($0, to: clip) }
                    }
                    pieces = pieces.flatMap {
                        clipPolyline($0, to: page, convexAllInside: canvas)
                    }
                    out.append(contentsOf: pieces)
                }
            }
            if record.style.fill != nil, record.style.stroke == nil,
               let (contours, winding) = fillContours(record.geometry) {
                var region = Shape(contours: contours.map {
                    Contour($0.map(toDevice), closed: true)
                }, winding: winding)
                let allInside = clipStack.isEmpty && region.contours.allSatisfy {
                    $0.points.allSatisfy { canvas.contains($0) }
                }
                if !allInside {
                    for clip in clipStack { region = region.intersection(clip) }
                    region = region.intersection(page)
                }
                out.append(contentsOf: region.contours.filter { $0.points.count >= 3 })
            }
        }
    }
    return out
}

/// Apply a 2D homogeneous CTM to a point, in `Double` (shared with the
/// hatching transform in SVGExport.swift).
func transformed(_ p: Vector2, _ m: simd_float3x3) -> Vector2 {
    let v = m * SIMD3<Float>(Float(p.x), Float(p.y), 1)
    return Vector2(Double(v.x), Double(v.y))
}

// MARK: - OllinApp entry points

public extension OllinApp {
    /// Render one frame of `sketch` as a G-code program string: no window, no
    /// GPU. Drives the sketch headlessly the way `svg(of:)` does and plans the
    /// recorded line work for `settings`'s machine: strokes plot along their
    /// centerlines, fills contribute their outlines (pass `hatching` to shade
    /// them as line work instead), raster images are skipped with a note.
    static func gcode(of sketch: Sketch, settings: GCode, frame: Int = 0,
                      fps: Double = 60, hatching: Hatching? = nil) -> String {
        let recording = recordVectorFrame(of: sketch, frame: frame, fps: fps,
                                          hatching: hatching)
        let canvas = Rectangle(x: 0, y: 0, width: Double(recording.width),
                               height: Double(recording.height))
        let contours = gcodeContours(recording.commands, canvas: canvas)
        let toolpath = settings.plan(contours, in: canvas, alreadyClipped: true)
        return toolpath.text(recipe: recording.recipe,
                             skippedImages: recording.skippedImages)
    }

    /// Render one frame of `sketch` and write it as a G-code file. The
    /// machine-facing counterpart of `exportSVG`; the basis for the
    /// `--export-gcode` flag.
    static func exportGCode(_ sketch: Sketch, to path: String, settings: GCode,
                            frame: Int = 0, fps: Double = 60,
                            hatching: Hatching? = nil) {
        let program = gcode(of: sketch, settings: settings, frame: frame,
                            fps: fps, hatching: hatching)
        do {
            try program.write(toFile: path, atomically: true, encoding: .utf8)
            print("Ollin: exported frame \(frame) → \(path) (G-code)")
        } catch {
            fatalError("Ollin: failed to write \(path): \(error)")
        }
    }
}
