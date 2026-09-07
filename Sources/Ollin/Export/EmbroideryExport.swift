import Foundation
import simd

// Embroidery export: one frame's line work and fills as the stitches an embroidery
// machine sews, written as a `.dst` file, the stitch format nearly every machine
// and every embroidery program reads. The public core is `Embroidery` plus
// `Stitching`, callable from a sketch (preview the stitches, or write the file
// from your own contours); the frame exporter, the `OllinApp` entry points, and
// the `--export-embroidery` flag are the sugar over it, the way `GCode` and
// `Toolpath` sit under `--export-gcode`.
//
// The pipeline stays in canvas space until the file is written: millimeters, the
// tenth-millimeter grid, and the y flip (a canvas grows down, a hoop grows up)
// enter only in `Stitching.dst(label:)`.

// MARK: - Settings

/// How a frame becomes stitches: the design's physical width, the running-stitch
/// pitch, how fills are laid, and the ordering. The width is a required argument
/// on purpose, the way `GCode` asks for one: a hoop has real millimeters, and a
/// default would size the design silently.
public struct Embroidery: Equatable, Sendable {
    /// The design's width in millimeters. The canvas width maps onto it, and the
    /// height follows the canvas aspect ratio.
    public var width: Double
    /// Extra millimeters around the design on every side.
    public var margin: Double
    /// The running-stitch pitch in millimeters: no stitch along a line is longer
    /// than this, and a line's corners are always hit exactly. Clamped to
    /// `0.3...12`, the range a machine can sew in one motion.
    public var stitchLength: Double
    /// Millimeters between the rows a fill is laid in (a tatami fill), or `nil`
    /// to sew only each fill's outline as a running stitch.
    public var fillSpacing: Double?
    /// The angle the fill rows run at, in radians.
    public var fillAngle: Double
    /// Reorder the paths within each color to shorten the jumps between them.
    /// Ordering changes only the jumps, never what is sewn.
    public var optimizesTravel: Bool
    /// Open paths whose ends meet within this many millimeters sew as one path.
    public var joinTolerance: Double

    public init(width: Double, margin: Double = 0, stitchLength: Double = 2.5,
                fillSpacing: Double? = 0.4, fillAngle: Double = 0,
                optimizesTravel: Bool = true, joinTolerance: Double = 0.1) {
        self.width = width
        self.margin = margin
        self.stitchLength = min(max(stitchLength, 0.3), 12)
        self.fillSpacing = fillSpacing.map { max($0, 0.1) }
        self.fillAngle = fillAngle
        self.optimizesTravel = optimizesTravel
        self.joinTolerance = joinTolerance
    }

    /// Plan the stitches for `paths` (canvas-space contours, sewn as line work in
    /// one thread): clip to `canvas`, merge touching ends, order to shorten the
    /// jumps, and lay a running stitch along each. The result previews and writes.
    public func stitches(_ paths: [Contour], in canvas: Rectangle) -> Stitching {
        plan([StitchBlock(color: .black, lines: paths, fills: [])], in: canvas, alreadyClipped: false)
    }

    /// The finished `.dst` file for `paths`: `stitches(_:in:)` written out.
    public func data(_ paths: [Contour], in canvas: Rectangle, label: String = "OLLIN") -> Data {
        stitches(paths, in: canvas).dst(label: label)
    }

    /// Millimeters per canvas unit.
    func scale(for canvas: Rectangle) -> Double {
        width / max(canvas.width, 1e-9)
    }

    /// Shared planner behind the public `stitches` and the frame exporter (whose
    /// flattener has already clipped fills and strokes exactly). Each block is
    /// one thread: its fills are laid as rows (or as outlines), its lines as
    /// running stitches, and a color change separates it from the next.
    func plan(_ blocks: [StitchBlock], in canvas: Rectangle, alreadyClipped: Bool) -> Stitching {
        let scale = scale(for: canvas)
        let pitch = stitchLength / scale
        let page = canvasShape(canvas)
        let origin = canvas.center
        var stitches: [Stitch] = []
        var threads: [Color] = []
        var position = origin
        var threadLength = 0.0
        var jumpLength = 0.0
        var stitchCount = 0
        var jumpCount = 0

        for block in blocks {
            var work = block.lines.filter { $0.points.count >= 2 }
            if !alreadyClipped {
                work = work.flatMap { clipPolyline($0, to: page, convexAllInside: canvas) }
            }
            // A fill is rows of running stitch across it, or its outline alone.
            for region in block.fills {
                if let spacing = fillSpacing {
                    let rows = hatchLines(region.contours.map(\.points), winding: region.winding,
                                          spacing: spacing / scale, angle: fillAngle,
                                          crossHatches: false)
                    work.append(contentsOf: rows.filter { $0.count >= 2 }.map { Contour($0, closed: false) })
                } else {
                    work.append(contentsOf: region.contours.filter { $0.points.count >= 3 }
                        .map { Contour($0.points, closed: true) })
                }
            }
            if joinTolerance > 0 {
                work = mergedPaths(work, tolerance: joinTolerance / scale, sequentialOnly: !optimizesTravel)
            }
            if optimizesTravel {
                work = orderedPaths(work, from: position)
            }
            guard !work.isEmpty else { continue }
            if !threads.isEmpty {
                stitches.append(Stitch(position: position, kind: .colorChange))
            }
            threads.append(block.color)

            for path in work {
                var points = path.points
                if path.isClosed { points.append(points[0]) }
                // Reach the path's start: one stitch if it is within the pitch, else
                // a jump (the thread lifts and the machine carries it over).
                let hop = position.distance(to: points[0])
                if hop > 1e-9 {
                    if hop <= pitch {
                        stitches.append(Stitch(position: points[0], kind: .stitch))
                        stitchCount += 1
                        threadLength += hop
                    } else {
                        stitches.append(Stitch(position: points[0], kind: .jump))
                        jumpCount += 1
                        jumpLength += hop
                    }
                } else if stitches.isEmpty {
                    stitches.append(Stitch(position: points[0], kind: .stitch))
                    stitchCount += 1
                }
                position = points[0]
                // A running stitch along each segment: equal steps no longer than
                // the pitch, so every corner is a penetration.
                for i in 1 ..< points.count {
                    let from = points[i - 1], to = points[i]
                    let length = from.distance(to: to)
                    guard length > 1e-9 else { continue }
                    let steps = max(1, Int((length / pitch).rounded(.up)))
                    for k in 1 ... steps {
                        let p = from.lerp(to: to, Double(k) / Double(steps))
                        stitches.append(Stitch(position: p, kind: .stitch))
                    }
                    stitchCount += steps
                    threadLength += length
                    position = to
                }
            }
        }
        return Stitching(stitches: stitches, threads: threads,
                         stitchCount: stitchCount, jumpCount: jumpCount,
                         colorChanges: max(0, threads.count - 1),
                         threadLength: threadLength * scale, jumpLength: jumpLength * scale,
                         settings: self, canvas: canvas)
    }
}

/// One thread's worth of a frame: its line work and its fill regions, in canvas
/// space, in the order they were drawn.
struct StitchBlock {
    var color: Color
    var lines: [Contour]
    var fills: [Shape]
}

// MARK: - Stitches

/// One needle penetration, or the move that lifts the thread between two, or a
/// change of thread. Canvas space, so a sketch can draw the plan over itself.
public struct Stitch: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// The needle goes down here; the thread runs from the previous stitch.
        case stitch
        /// The frame moves here with the needle up; the thread is carried, not sewn.
        case jump
        /// The machine stops for the next thread; the position does not move.
        case colorChange
    }
    public var position: Vector2
    public var kind: Kind

    public init(position: Vector2, kind: Kind) {
        self.position = position
        self.kind = kind
    }
}

/// A planned design: every stitch in sewing order, the threads in the order the
/// machine asks for them, the measured counts and lengths, and the `.dst` bytes.
/// Made by `Embroidery.stitches(_:in:)` or `OllinApp.stitching(of:)`; a sketch can
/// draw `stitches` to preview the sewing.
public struct Stitching: Sendable {
    /// Every penetration, jump, and color change, in the order the machine runs.
    public var stitches: [Stitch]
    /// The thread colors in the order they are sewn, one per color change plus one.
    public var threads: [Color]
    /// Needle penetrations.
    public var stitchCount: Int
    /// Lifts of the thread between paths (each may take several file records).
    public var jumpCount: Int
    /// Stops for a new thread.
    public var colorChanges: Int
    /// Millimeters of running stitch.
    public var threadLength: Double
    /// Millimeters carried over in jumps, the part ordering works to shrink.
    public var jumpLength: Double
    var settings: Embroidery
    var canvas: Rectangle

    /// The design's size in millimeters, margin included.
    public var size: (width: Double, height: Double) {
        let scale = settings.scale(for: canvas)
        return (canvas.width * scale + 2 * settings.margin,
                canvas.height * scale + 2 * settings.margin)
    }

    /// The `.dst` file: a 512-byte header and one three-byte record per stitch,
    /// jump, or color change, each a displacement on a tenth-millimeter grid of
    /// at most 121 steps, so a long jump takes several records. `label` is the
    /// design name the machine shows, at most 16 characters. The design starts
    /// at the canvas center, so a hoop centered on the design sews it whole.
    public func dst(label: String = "OLLIN") -> Data {
        let scale = settings.scale(for: canvas) * 10       // tenth-millimeters per canvas unit
        let start = canvas.center
        func grid(_ p: Vector2) -> SIMD2<Int> {
            // A hoop's y grows upward, a canvas's downward.
            SIMD2(Int(((p.x - start.x) * scale).rounded()),
                  Int(((start.y - p.y) * scale).rounded()))
        }
        var records: [UInt8] = []
        var position = SIMD2<Int>(0, 0)
        var minX = 0, maxX = 0, minY = 0, maxY = 0
        var count = 0
        for stitch in stitches {
            switch stitch.kind {
            case .colorChange:
                records.append(contentsOf: dstRecord(dx: 0, dy: 0, flags: 0xC0))
                count += 1
            case .stitch, .jump:
                let target = grid(stitch.position)
                let delta = target &- position
                let steps = max(1, Int((Double(max(abs(delta.x), abs(delta.y))) / 121).rounded(.up)))
                var laid = SIMD2<Int>(0, 0)
                for k in 1 ... steps {
                    let next = SIMD2(delta.x * k / steps, delta.y * k / steps)
                    let step = next &- laid
                    records.append(contentsOf: dstRecord(dx: step.x, dy: step.y,
                                                         flags: stitch.kind == .jump ? 0x80 : 0))
                    count += 1
                    laid = next
                }
                position = target
                minX = min(minX, position.x); maxX = max(maxX, position.x)
                minY = min(minY, position.y); maxY = max(maxY, position.y)
            }
        }
        records.append(contentsOf: [0x00, 0x00, 0xF3])

        func field(_ key: String, _ value: String, width: Int) -> String {
            key + ":" + value.padding(toLength: width, withPad: " ", startingAt: 0) + "\r"
        }
        func digits(_ v: Int, _ n: Int) -> String {
            String(format: "%0\(n)d", max(0, v))
        }
        func signed(_ v: Int) -> String {
            (v < 0 ? "-" : "+") + String(format: "%5d", abs(v))
        }
        var header = ""
        header += field("LA", String(label.prefix(16)), width: 16)
        header += field("ST", digits(count, 7), width: 7)
        header += field("CO", digits(colorChanges, 3), width: 3)
        header += field("+X", digits(maxX, 5), width: 5)
        header += field("-X", digits(-minX, 5), width: 5)
        header += field("+Y", digits(maxY, 5), width: 5)
        header += field("-Y", digits(-minY, 5), width: 5)
        header += field("AX", signed(position.x), width: 6)
        header += field("AY", signed(position.y), width: 6)
        header += field("MX", signed(0), width: 6)
        header += field("MY", signed(0), width: 6)
        header += field("PD", "******", width: 9)
        var bytes = Array(header.utf8)
        bytes.append(0x1A)
        while bytes.count < 512 { bytes.append(0x20) }
        return Data(bytes + records)
    }
}

/// One `.dst` record: `dx`/`dy` in tenth-millimeters, each within ±121, encoded
/// as the sum of the steps 81, 27, 9, 3, 1 on its own bits, with the control bits
/// in the third byte (`0x80` a jump, `0xC0` a color change).
func dstRecord(dx: Int, dy: Int, flags: UInt8) -> [UInt8] {
    precondition(abs(dx) <= 121 && abs(dy) <= 121, "a .dst record moves at most 12.1 mm")
    var b0: UInt8 = 0, b1: UInt8 = 0, b2: UInt8 = 0x03 | flags
    var x = dx, y = dy
    if x > 40 { b2 |= 0x04; x -= 81 } else if x < -40 { b2 |= 0x08; x += 81 }
    if x > 13 { b1 |= 0x04; x -= 27 } else if x < -13 { b1 |= 0x08; x += 27 }
    if x > 4 { b0 |= 0x04; x -= 9 } else if x < -4 { b0 |= 0x08; x += 9 }
    if x > 1 { b1 |= 0x01; x -= 3 } else if x < -1 { b1 |= 0x02; x += 3 }
    if x > 0 { b0 |= 0x01; x -= 1 } else if x < 0 { b0 |= 0x02; x += 1 }
    if y > 40 { b2 |= 0x20; y -= 81 } else if y < -40 { b2 |= 0x10; y += 81 }
    if y > 13 { b1 |= 0x20; y -= 27 } else if y < -13 { b1 |= 0x10; y += 27 }
    if y > 4 { b0 |= 0x20; y -= 9 } else if y < -4 { b0 |= 0x10; y += 9 }
    if y > 1 { b1 |= 0x80; y -= 3 } else if y < -1 { b1 |= 0x40; y += 3 }
    if y > 0 { b0 |= 0x80; y -= 1 } else if y < 0 { b0 |= 0x40; y += 1 }
    assert(x == 0 && y == 0)
    return [b0, b1, b2]
}

// MARK: - Flattening a recorded frame

/// Flatten one recorded frame into thread blocks: strokes along their
/// centerlines, fills as regions (rows or outlines are decided later, by the
/// settings), clip regions applied exactly, and everything clipped to the canvas.
/// A new block starts whenever the color changes, in draw order, so what is sewn
/// later lies on top the way it was drawn on top; a sketch that wants fewer
/// thread changes draws each color's shapes together.
func stitchBlocks(_ commands: [SVGCommand], canvas: Rectangle) -> [StitchBlock] {
    let page = canvasShape(canvas)
    var clipStack: [Shape] = []
    var blocks: [StitchBlock] = []
    func block(for color: Color) -> Int {
        let key = Color(red: (color.red * 255).rounded() / 255,
                        green: (color.green * 255).rounded() / 255,
                        blue: (color.blue * 255).rounded() / 255)
        if let last = blocks.last, last.color == key { return blocks.count - 1 }
        blocks.append(StitchBlock(color: key, lines: [], fills: []))
        return blocks.count - 1
    }
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
            if let fill = record.style.fill, let color = threadColor(fill),
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
                if region.contours.contains(where: { $0.points.count >= 3 }) {
                    blocks[block(for: color)].fills.append(region)
                }
            }
            if let stroke = record.style.stroke, let color = threadColor(stroke) {
                let strokePaths = record.geometry.strokePaths
                    ?? fillContours(record.geometry).map { outline in
                        outline.contours.map { ($0, true) }
                    } ?? []
                var pieces: [Contour] = []
                for (points, closed) in strokePaths {
                    var part = [Contour(points.map(toDevice), closed: closed)]
                    for clip in clipStack {
                        part = part.flatMap { clipPolyline($0, to: clip) }
                    }
                    part = part.flatMap { clipPolyline($0, to: page, convexAllInside: canvas) }
                    pieces.append(contentsOf: part)
                }
                if !pieces.isEmpty {
                    blocks[block(for: color)].lines.append(contentsOf: pieces)
                }
            }
        }
    }
    return blocks
}

/// The thread a paint asks for: a solid color as itself, a gradient as the middle
/// of its ramp (a thread is one color). Nothing for a fully transparent paint.
private func threadColor(_ paint: Paint) -> Color? {
    let color: Color
    switch paint {
    case .color(let c): color = c
    case .gradient(let g): color = g.ramp.color(at: 0.5)
    }
    return color.alpha > 0 ? color : nil
}

// MARK: - OllinApp entry points

public extension OllinApp {
    /// Render one frame of `sketch` as a stitching plan: no window, no GPU. Drives
    /// the sketch headlessly the way `svg(of:)` does and plans the recorded work
    /// for `settings`: strokes sew along their centerlines, fills as rows (or as
    /// outlines), each color in draw order as its own thread, and raster images
    /// are skipped. Draw the result's `stitches` to preview the sewing.
    static func stitching(of sketch: Sketch, settings: Embroidery, frame: Int = 0,
                          fps: Double = 60) -> Stitching {
        let recording = recordVectorFrame(of: sketch, frame: frame, fps: fps, hatching: nil)
        let canvas = Rectangle(x: 0, y: 0, width: Double(recording.width),
                               height: Double(recording.height))
        let blocks = stitchBlocks(recording.commands, canvas: canvas)
        return settings.plan(blocks, in: canvas, alreadyClipped: true)
    }

    /// Render one frame of `sketch` as the bytes of a `.dst` embroidery file.
    static func embroidery(of sketch: Sketch, settings: Embroidery, frame: Int = 0,
                           fps: Double = 60, label: String = "OLLIN") -> Data {
        stitching(of: sketch, settings: settings, frame: frame, fps: fps).dst(label: label)
    }

    /// Render one frame of `sketch` and write it as a `.dst` embroidery file. The
    /// thread-facing counterpart of `exportGCode`; the basis for the
    /// `--export-embroidery` flag.
    static func exportEmbroidery(_ sketch: Sketch, to path: String, settings: Embroidery,
                                 frame: Int = 0, fps: Double = 60) {
        let label = String(((path as NSString).lastPathComponent as NSString)
            .deletingPathExtension.uppercased().prefix(16))
        let plan = stitching(of: sketch, settings: settings, frame: frame, fps: fps)
        do {
            try plan.dst(label: label.isEmpty ? "OLLIN" : label)
                .write(to: URL(fileURLWithPath: path), options: .atomic)
            let size = plan.size
            print("Ollin: exported frame \(frame) → \(path) (embroidery, "
                  + "\(plan.stitchCount) stitches, \(plan.threads.count) thread"
                  + "\(plan.threads.count == 1 ? "" : "s"), "
                  + "\(Int(size.width.rounded())) × \(Int(size.height.rounded())) mm)")
        } catch {
            fatalError("Ollin: failed to write \(path): \(error)")
        }
    }
}
