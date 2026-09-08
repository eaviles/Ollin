import Foundation
import simd

// DXF export: the drawing-exchange sink beside SVG, PDF, G-code, and embroidery.
// The same recorded frame is flattened to line work and fill outlines, clipped to
// the canvas, merged where ends touch, and written as a drawing that a CAD
// program, a laser cutter's own software, or a vector editor opens: a layer per
// color, LINE / POLYLINE / CIRCLE entities, in millimeters. Everything up to the
// final text stays in canvas space; millimeters and the y flip (a canvas grows
// down, a drawing grows up) enter only at emission, as they do for G-code.
//
// The file is the R12 dialect (AC1009): no handles, no object dictionary, and
// the POLYLINE / VERTEX / SEQEND form for a polyline. It is the oldest dialect
// still written, which is why every reader takes it, from a CAD import to a
// laser's own software. The public core is `DXF` plus `Drafting`, callable from
// a sketch (preview the layers, write the file from your own contours);
// `OllinApp.dxf(of:)` / `exportDXF` and the `--export-dxf` flag are the sugar.

// MARK: - Settings

/// How a frame becomes a DXF drawing: the physical width, a margin, and how
/// touching paths merge. The width is a required argument on purpose, the way
/// `GCode` asks for one: a drawing opened in a shop program has real
/// millimeters, and a default would size the part silently.
public struct DXF: Equatable, Sendable {
    /// The drawing's width in millimeters. The canvas width maps onto it, and
    /// the height follows the canvas aspect ratio.
    public var width: Double
    /// Extra millimeters around the drawing on every side.
    public var margin: Double
    /// Open paths whose ends meet within this many millimeters become one
    /// polyline, so a curve drawn as many calls arrives as one entity. Zero
    /// keeps every call its own entity.
    public var joinTolerance: Double

    public init(width: Double, margin: Double = 0, joinTolerance: Double = 0.1) {
        self.width = width
        self.margin = margin
        self.joinTolerance = joinTolerance
    }

    /// Plan the drawing for `paths` (canvas-space contours, drawn as line work
    /// on the default layer, `0`): clip to `canvas`, merge touching ends, and
    /// name each as a line or a polyline. The result previews and writes.
    public func drafting(_ paths: [Contour], in canvas: Rectangle) -> Drafting {
        plan([DraftBlock(layer: "0", color: .black, lines: paths, fills: [], circles: [])],
             in: canvas, alreadyClipped: false)
    }

    /// The finished DXF text for `paths`: `drafting(_:in:)` written out.
    public func text(_ paths: [Contour], in canvas: Rectangle) -> String {
        drafting(paths, in: canvas).text
    }

    /// Millimeters per canvas unit.
    func scale(for canvas: Rectangle) -> Double {
        width / max(canvas.width, 1e-9)
    }

    /// Shared planner behind the public `drafting` and the frame exporter (whose
    /// flattener has already clipped fills and strokes exactly). Each block is
    /// one layer's work: its lines are clipped and merged by the G-code planner
    /// (in draw order, never reordered), its fills become closed polylines, and
    /// its circles stay circles.
    func plan(_ blocks: [DraftBlock], in canvas: Rectangle, alreadyClipped: Bool) -> Drafting {
        let planner = GCode(.plotter(), width: width, margin: margin,
                            optimizesTravel: false, joinTolerance: joinTolerance)
        var layers: [Drafting.Layer] = []
        var entities: [Drafting.Entity] = []
        for block in blocks {
            if !layers.contains(where: { $0.name == block.layer }) {
                layers.append(Drafting.Layer(name: block.layer, color: block.color,
                                             colorIndex: Drafting.nearestIndex(to: block.color)))
            }
            let merged = planner.plan(block.lines, in: canvas, alreadyClipped: alreadyClipped).paths
            for contour in merged where contour.points.count >= 2 {
                if contour.points.count == 2, !contour.isClosed {
                    entities.append(Drafting.Entity(kind: .line(contour.points[0], contour.points[1]),
                                                    layer: block.layer))
                } else {
                    entities.append(Drafting.Entity(kind: .polyline(contour.points, closed: contour.isClosed),
                                                    layer: block.layer))
                }
            }
            for fill in block.fills {
                for contour in fill.contours where contour.points.count >= 3 {
                    entities.append(Drafting.Entity(kind: .polyline(contour.points, closed: true),
                                                    layer: block.layer))
                }
            }
            for circle in block.circles {
                entities.append(Drafting.Entity(kind: .circle(center: circle.center, radius: circle.radius),
                                                layer: block.layer))
            }
        }
        return Drafting(entities: entities, layers: layers, canvas: canvas,
                        scale: scale(for: canvas), margin: margin)
    }
}

/// One layer's work before it is planned: lines to clip and merge, fill regions
/// already clipped, and circles that survived as circles.
struct DraftBlock {
    var layer: String
    var color: Color
    var lines: [Contour]
    var fills: [Shape]
    var circles: [(center: Vector2, radius: Double)]
}

// MARK: - The drawing

/// A frame as the entities a DXF file holds, in canvas coordinates, with the
/// layers they sit on. Draw it to preview what a shop program will open, or
/// write `text` to a file.
public struct Drafting: Sendable {
    /// One layer: its name, the color it stands for, and the nearest of the
    /// nine standard drawing colors, which is what the file can say.
    public struct Layer: Sendable, Equatable {
        public var name: String
        public var color: Color
        /// The color index the layer is written with: 1 red, 2 yellow, 3 green,
        /// 4 cyan, 5 blue, 6 magenta, 7 the foreground (black on a light
        /// drawing), 8 gray, 9 light gray.
        public var colorIndex: Int
    }

    /// One entity, in canvas coordinates.
    public struct Entity: Sendable, Equatable {
        public enum Kind: Sendable, Equatable {
            /// A straight segment.
            case line(Vector2, Vector2)
            /// A run of points, open or closed.
            case polyline([Vector2], closed: Bool)
            /// A true circle, kept where nothing skewed it.
            case circle(center: Vector2, radius: Double)
        }
        public var kind: Kind
        /// The layer it sits on.
        public var layer: String
    }

    /// Every entity, in draw order within each layer.
    public var entities: [Entity]
    /// The layers, in the order they were first drawn on.
    public var layers: [Layer]

    let canvas: Rectangle
    let scale: Double
    let margin: Double

    /// The drawing's size in millimeters, margin included.
    public var size: (width: Double, height: Double) {
        (canvas.width * scale + 2 * margin, canvas.height * scale + 2 * margin)
    }

    /// The entities on one layer.
    public func entities(on layer: String) -> [Entity] {
        entities.filter { $0.layer == layer }
    }

    /// The DXF file as text.
    public var text: String { dxfText() }

    /// The DXF file as bytes.
    public var data: Data { Data(text.utf8) }

    // MARK: Colors

    /// The nine standard colors a layer can be written as, and what they show.
    static let standardColors: [(index: Int, red: Double, green: Double, blue: Double)] = [
        (1, 1, 0, 0), (2, 1, 1, 0), (3, 0, 1, 0), (4, 0, 1, 1), (5, 0, 0, 1),
        (6, 1, 0, 1), (7, 0, 0, 0), (8, 0.5, 0.5, 0.5), (9, 0.75, 0.75, 0.75),
    ]

    /// The standard color nearest to `color`, by distance in display values.
    static func nearestIndex(to color: Color) -> Int {
        var best = 7, bestDistance = Double.infinity
        for entry in standardColors {
            let dr = entry.red - color.red, dg = entry.green - color.green, db = entry.blue - color.blue
            let distance = dr * dr + dg * dg + db * db
            if distance < bestDistance { best = entry.index; bestDistance = distance }
        }
        return best
    }

    /// The layer a color is drawn on, named by the color's display bytes.
    static func layerName(for color: Color) -> String {
        let r = Int((color.red * 255).rounded()), g = Int((color.green * 255).rounded()),
            b = Int((color.blue * 255).rounded())
        return String(format: "color-%02X%02X%02X", r, g, b)
    }

    // MARK: Writing

    /// A canvas point in the drawing's millimeters: the margin added, and the y
    /// axis flipped so the canvas's top edge is the drawing's top.
    func place(_ p: Vector2) -> (x: Double, y: Double) {
        (margin + (p.x - canvas.x) * scale, margin + (canvas.height - (p.y - canvas.y)) * scale)
    }

    private func dxfText() -> String {
        var lines: [String] = []
        func tag(_ code: Int, _ value: String) {
            lines.append(String(format: "%3d", code))
            lines.append(value)
        }
        func number(_ value: Double) -> String {
            let text = String(format: "%.4f", value)
            return text == "-0.0000" ? "0.0000" : text
        }
        func point(_ p: Vector2, _ base: Int) {
            let placed = place(p)
            tag(base, number(placed.x))
            tag(base + 10, number(placed.y))
            tag(base + 20, "0.0")
        }

        let size = size
        tag(0, "SECTION")
        tag(2, "HEADER")
        tag(9, "$ACADVER")
        tag(1, "AC1009")
        tag(9, "$INSUNITS")
        tag(70, "4")
        tag(9, "$MEASUREMENT")
        tag(70, "1")
        tag(9, "$EXTMIN")
        tag(10, "0.0")
        tag(20, "0.0")
        tag(30, "0.0")
        tag(9, "$EXTMAX")
        tag(10, number(size.width))
        tag(20, number(size.height))
        tag(30, "0.0")
        tag(9, "$LIMMIN")
        tag(10, "0.0")
        tag(20, "0.0")
        tag(9, "$LIMMAX")
        tag(10, number(size.width))
        tag(20, number(size.height))
        tag(0, "ENDSEC")

        tag(0, "SECTION")
        tag(2, "TABLES")
        tag(0, "TABLE")
        tag(2, "LTYPE")
        tag(70, "1")
        tag(0, "LTYPE")
        tag(2, "CONTINUOUS")
        tag(70, "0")
        tag(3, "Solid line")
        tag(72, "65")
        tag(73, "0")
        tag(40, "0.0")
        tag(0, "ENDTAB")
        tag(0, "TABLE")
        tag(2, "LAYER")
        tag(70, "\(max(layers.count, 1))")
        for layer in layers {
            tag(0, "LAYER")
            tag(2, layer.name)
            tag(70, "0")
            tag(62, "\(layer.colorIndex)")
            tag(6, "CONTINUOUS")
        }
        tag(0, "ENDTAB")
        tag(0, "ENDSEC")

        tag(0, "SECTION")
        tag(2, "ENTITIES")
        for entity in entities {
            switch entity.kind {
            case let .line(a, b):
                tag(0, "LINE")
                tag(8, entity.layer)
                point(a, 10)
                point(b, 11)
            case let .polyline(points, closed):
                tag(0, "POLYLINE")
                tag(8, entity.layer)
                tag(66, "1")
                tag(70, closed ? "1" : "0")
                tag(10, "0.0")
                tag(20, "0.0")
                tag(30, "0.0")
                for p in points {
                    tag(0, "VERTEX")
                    tag(8, entity.layer)
                    point(p, 10)
                }
                tag(0, "SEQEND")
                tag(8, entity.layer)
            case let .circle(center, radius):
                tag(0, "CIRCLE")
                tag(8, entity.layer)
                point(center, 10)
                tag(40, number(radius * scale))
            }
        }
        tag(0, "ENDSEC")
        tag(0, "EOF")
        return lines.joined(separator: "\r\n") + "\r\n"
    }
}

// MARK: - Flattening a recorded frame

/// Flatten one recorded frame into layer blocks: strokes along their
/// centerlines, fills as regions, clip regions applied exactly, everything
/// clipped to the canvas, and a circle that nothing skewed or clipped kept as a
/// circle. A new block starts whenever the color changes, in draw order, so an
/// entity drawn later is written later.
func draftBlocks(_ commands: [SVGCommand], canvas: Rectangle) -> [DraftBlock] {
    // The circles first: a circle stays a circle when its transform is a
    // similarity (a turn, a uniform scale, a move) and no clip could cut it.
    var remaining: [SVGCommand] = []
    var circles: [(color: Color, center: Vector2, radius: Double)] = []
    var clipDepth = 0
    for command in commands {
        switch command {
        case .clipPush: clipDepth += 1
        case .clipPop: clipDepth = max(0, clipDepth - 1)
        case let .draw(record):
            guard clipDepth == 0, case let .ellipse(center, rx, ry) = record.geometry,
                  abs(rx - ry) <= 1e-9 * max(rx, ry, 1), rx > 0 else { break }
            let origin = transformed(center, record.transform)
            // The images of the unit vectors are the matrix's own columns, read
            // there rather than through two points, since single-precision
            // rounding at canvas scale is larger than the test below.
            let m = record.transform
            let u = Vector2(Double(m.columns.0.x), Double(m.columns.0.y))
            let v = Vector2(Double(m.columns.1.x), Double(m.columns.1.y))
            let radius = rx * u.length
            guard abs(u.length - v.length) <= 1e-4 * max(u.length, 1),
                  abs(u.dot(v)) <= 1e-4 * max(u.length * v.length, 1),
                  origin.x - radius >= canvas.x, origin.x + radius <= canvas.x + canvas.width,
                  origin.y - radius >= canvas.y, origin.y + radius <= canvas.y + canvas.height
            else { break }
            if let fill = record.style.fill, let color = paintColor(fill) {
                circles.append((color, origin, radius))
            }
            if let stroke = record.style.stroke, let color = paintColor(stroke) {
                circles.append((color, origin, radius))
            }
            continue
        }
        remaining.append(command)
    }

    var blocks = stitchBlocks(remaining, canvas: canvas).map {
        DraftBlock(layer: Drafting.layerName(for: $0.color), color: $0.color,
                   lines: $0.lines, fills: $0.fills, circles: [])
    }
    for circle in circles {
        let name = Drafting.layerName(for: circle.color)
        if let index = blocks.firstIndex(where: { $0.layer == name }) {
            blocks[index].circles.append((circle.center, circle.radius))
        } else {
            blocks.append(DraftBlock(layer: name, color: circle.color, lines: [], fills: [],
                                     circles: [(circle.center, circle.radius)]))
        }
    }
    return blocks
}

// MARK: - OllinApp entry points

public extension OllinApp {
    /// Render one frame of `sketch` as a drawing: no window, no GPU. Drives the
    /// sketch headlessly the way `svg(of:)` does and plans the recorded work for
    /// `settings`: strokes as lines and polylines along their centerlines, fills
    /// as closed polylines (or as line work, when `hatching` shades them), a
    /// circle as a circle, each color on its own layer, and raster images
    /// skipped. Draw the result's `entities` to preview what a shop program
    /// will open.
    static func drafting(of sketch: Sketch, settings: DXF, frame: Int = 0,
                         fps: Double = 60, hatching: Hatching? = nil) -> Drafting {
        let recording = recordVectorFrame(of: sketch, frame: frame, fps: fps, hatching: hatching)
        let canvas = Rectangle(x: 0, y: 0, width: Double(recording.width),
                               height: Double(recording.height))
        let blocks = draftBlocks(recording.commands, canvas: canvas)
        return settings.plan(blocks, in: canvas, alreadyClipped: true)
    }

    /// Render one frame of `sketch` as the text of a DXF file.
    static func dxf(of sketch: Sketch, settings: DXF, frame: Int = 0,
                    fps: Double = 60, hatching: Hatching? = nil) -> String {
        drafting(of: sketch, settings: settings, frame: frame, fps: fps, hatching: hatching).text
    }

    /// Render one frame of `sketch` and write it as a DXF file. The
    /// drawing-exchange counterpart of `exportGCode`; the basis for the
    /// `--export-dxf` flag.
    static func exportDXF(_ sketch: Sketch, to path: String, settings: DXF,
                          frame: Int = 0, fps: Double = 60, hatching: Hatching? = nil) {
        let drawing = drafting(of: sketch, settings: settings, frame: frame, fps: fps,
                               hatching: hatching)
        do {
            try drawing.text.write(toFile: path, atomically: true, encoding: .utf8)
            let size = drawing.size
            print("Ollin: exported frame \(frame) → \(path) (DXF, "
                  + "\(drawing.entities.count) entit\(drawing.entities.count == 1 ? "y" : "ies") on "
                  + "\(drawing.layers.count) layer\(drawing.layers.count == 1 ? "" : "s"), "
                  + "\(Int(size.width.rounded())) × \(Int(size.height.rounded())) mm)")
        } catch {
            fatalError("Ollin: failed to write \(path): \(error)")
        }
    }
}
