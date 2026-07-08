import Foundation

// SVG import: read vector artwork into `Shape`s and `Contour`s, the import half
// of the vector story (`--export-svg` is the export half). The parser is
// CPU-only and covers the subset generative work actually meets: `<path>` with
// the full path-data grammar (including elliptical arcs), the basic shapes
// (`rect`, `circle`, `ellipse`, `line`, `polyline`, `polygon`), groups,
// `transform` lists, presentation and inline styles, and the two fill rules
// (mapped onto `FillWinding`). Unsupported containers (`defs`, `clipPath`,
// `mask`, `symbol`, `pattern`, `marker`, text) are skipped whole, so a file
// that uses them still yields its plain geometry. Geometry, path grammar, and
// the arc conversion are implemented from the W3C SVG specification.

/// A vector document read from an SVG file: an ordered list of drawable
/// elements, each a `Shape` with the fill and stroke it was authored with.
///
/// Load one with `loadSVG("artwork.svg")` (or the `data:`/`resource:in:`
/// initializers), then either draw it as authored with `drawSVG(_:)` or mine
/// its geometry: `shapes` and `contours` feed everything the rest of the
/// framework does with vector geometry (shape booleans, offsets, hatching,
/// `resampled(spacing:)` dot effects, SVG re-export).
///
/// ```swift
/// if let art = loadSVG("crest.svg") {
///     drawSVG(art, in: Rectangle(x: 100, y: 100, width: 400, height: 400))
///     for contour in art.contours { drawPolyline(contour.points) }
/// }
/// ```
///
/// Coordinates come back in the document's own user space (the `viewBox`),
/// y-down from the top-left like the canvas, so nothing is flipped. Use
/// `fitted(in:)` to scale the artwork into a canvas rectangle.
public struct SVG: Equatable, Sendable {
    /// One drawable element: its outline geometry plus the paint it was
    /// authored with. Elements arrive in document order (back to front).
    public struct Element: Equatable, Sendable {
        /// The element's geometry. Closed contours fill; open ones (a `line`,
        /// a `polyline`, an unclosed path) are stroke-only.
        public var shape: Shape
        /// The fill color, `nil` when the element has `fill="none"`. A paint
        /// the importer can't resolve (a gradient reference) falls back to
        /// mid-gray so the artwork's form still shows.
        public var fill: Color?
        /// The stroke color, `nil` when unstroked (the SVG default).
        public var stroke: Color?
        /// The stroke width in document units, already scaled by the
        /// element's transforms.
        public var strokeWidth: Double
        /// How stroke segments join and end, as authored
        /// (`stroke-linejoin` / `stroke-linecap`; miter and butt by default).
        public var join: StrokeJoin
        public var cap: StrokeCap
        /// The element's `id` attribute, for reaching one element by name.
        public var name: String?

        public init(shape: Shape, fill: Color? = nil, stroke: Color? = nil,
                    strokeWidth: Double = 1, join: StrokeJoin = .miter,
                    cap: StrokeCap = .butt, name: String? = nil) {
            self.shape = shape
            self.fill = fill
            self.stroke = stroke
            self.strokeWidth = strokeWidth
            self.join = join
            self.cap = cap
            self.name = name
        }
    }

    /// The drawable elements in document order.
    public var elements: [Element]

    /// The document's coordinate space: the `viewBox` when the file declares
    /// one, else the tight bounds of the imported geometry.
    public var bounds: Rectangle

    public init(elements: [Element], bounds: Rectangle) {
        self.elements = elements
        self.bounds = bounds
    }

    // MARK: Loading

    /// Read an SVG file at a filesystem path. Returns `nil` when the file
    /// can't be read or contains no importable geometry.
    public init?(contentsOf path: String) {
        self.init(url: URL(fileURLWithPath: path))
    }

    /// Read an SVG file from a URL.
    public init?(url: URL) {
        guard let data = try? Data(contentsOf: url) else { return nil }
        self.init(data: data)
    }

    /// Read an SVG document from raw data (a downloaded file, an inline
    /// string's UTF-8 bytes).
    public init?(data: Data) {
        let parser = SVGDocumentParser()
        guard let document = parser.parse(data) else { return nil }
        self = document
    }

    /// Read an SVG bundled as a resource. Pass the caller's bundle explicitly
    /// (`.module` from inside a package target); a default would resolve to
    /// the framework's own bundle, not the caller's.
    public init?(resource: String, withExtension ext: String? = "svg", in bundle: Bundle) {
        guard let url = bundle.url(forResource: resource, withExtension: ext) else { return nil }
        self.init(url: url)
    }

    // MARK: Geometry access

    /// Every element's shape, in document order, with the paint dropped.
    public var shapes: [Shape] { elements.map(\.shape) }

    /// Every contour across all elements, in document order: the artwork as
    /// plain line-work, ready for `resampled(spacing:)`, offsets, or plotting.
    public var contours: [Contour] { elements.flatMap(\.shape.contours) }

    /// The first element whose `id` matches `name`, if any.
    public func element(named name: String) -> Element? {
        elements.first { $0.name == name }
    }

    /// A copy scaled uniformly to fit `container` (letterboxed and centered,
    /// like `Rectangle(fitting:in:)`), stroke widths scaled to match.
    public func fitted(in container: Rectangle) -> SVG {
        guard bounds.width > 0, bounds.height > 0 else { return self }
        let target = Rectangle(fitting: Vector2(bounds.width, bounds.height), in: container)
        let scale = target.width / bounds.width
        let origin = Vector2(bounds.x, bounds.y)
        let corner = Vector2(target.x, target.y)
        let moved = elements.map { element in
            var out = element
            out.shape = element.shape.mapPoints { corner + ($0 - origin) * scale }
            out.strokeWidth = element.strokeWidth * scale
            return out
        }
        return SVG(elements: moved, bounds: target)
    }
}

// MARK: - Sketch sugar

public extension Sketch {
    /// Load an SVG file by path (see `SVG`). Returns `nil` when the file can't
    /// be read or holds no importable geometry.
    func loadSVG(_ path: String) -> SVG? { SVG(contentsOf: path) }

    /// Load an SVG file from a URL.
    func loadSVG(_ url: URL) -> SVG? { SVG(url: url) }

    /// Draw an imported document as authored: each element with its own fill,
    /// stroke, and stroke width, in document order, in the document's own
    /// coordinates (the current transform applies). The sketch's fill/stroke
    /// state is untouched afterward.
    func drawSVG(_ svg: SVG) {
        drawer.pushState()
        for element in svg.elements {
            guard element.fill != nil || element.stroke != nil else { continue }
            if let fill = element.fill { drawer.fill(fill) } else { drawer.noFill() }
            if let stroke = element.stroke {
                drawer.stroke(stroke)
                drawer.strokeWeight(element.strokeWidth)
                drawer.strokeJoin(element.join)
                drawer.strokeCap(element.cap)
            } else {
                drawer.noStroke()
            }
            drawer.drawShape(element.shape)
        }
        drawer.popState()
    }

    /// Draw an imported document scaled to fit a canvas rectangle
    /// (`fitted(in:)` + `drawSVG(_:)`).
    func drawSVG(_ svg: SVG, in rect: Rectangle) {
        drawSVG(svg.fitted(in: rect))
    }
}

// MARK: - Affine transform

/// A 2D affine transform in SVG's six-value form (a b c d e f):
/// x' = a·x + c·y + e, y' = b·x + d·y + f.
struct SVGTransform: Equatable {
    var a = 1.0, b = 0.0, c = 0.0, d = 1.0, e = 0.0, f = 0.0

    static let identity = SVGTransform()

    /// self × other (apply `other` first, then self), the order a child
    /// transform composes onto its parent's.
    func concatenating(_ m: SVGTransform) -> SVGTransform {
        SVGTransform(a: a * m.a + c * m.b,
                     b: b * m.a + d * m.b,
                     c: a * m.c + c * m.d,
                     d: b * m.c + d * m.d,
                     e: a * m.e + c * m.f + e,
                     f: b * m.e + d * m.f + f)
    }

    func apply(_ p: Vector2) -> Vector2 {
        Vector2(a * p.x + c * p.y + e, b * p.x + d * p.y + f)
    }

    /// The average scale factor (√|det|): how the transform scales lengths,
    /// used to carry stroke widths through.
    var lengthScale: Double { abs(a * d - b * c).squareRoot() }

    static func translate(_ tx: Double, _ ty: Double) -> SVGTransform {
        SVGTransform(e: tx, f: ty)
    }
    static func scale(_ sx: Double, _ sy: Double) -> SVGTransform {
        SVGTransform(a: sx, d: sy)
    }
    static func rotate(degrees: Double) -> SVGTransform {
        let r = degrees * .pi / 180
        return SVGTransform(a: cos(r), b: sin(r), c: -sin(r), d: cos(r))
    }
    static func skewX(degrees: Double) -> SVGTransform {
        SVGTransform(c: tan(degrees * .pi / 180))
    }
    static func skewY(degrees: Double) -> SVGTransform {
        SVGTransform(b: tan(degrees * .pi / 180))
    }
}

// MARK: - Path data

/// One pen command of a parsed subpath, in user space (untransformed). The
/// subpath is transformed and flattened into a `Contour` after parsing, so
/// curve sampling density reflects the final on-canvas size.
enum SVGPathCommand: Equatable {
    case move(Vector2)
    case line(Vector2)
    case cubic(Vector2, Vector2, Vector2)   // control1, control2, end
    case quad(Vector2, Vector2)             // control, end
    case close
}

/// Parses SVG path data (`d`) and the shared number/list grammar. Written from
/// the specification's grammar: numbers may pack together with signs or a
/// second decimal point as separators, arc flags may sit unseparated, and a
/// leading `m`'s later pairs are implicit line commands.
struct SVGPathScanner {
    private let scalars: [UnicodeScalar]
    private var pos = 0

    init(_ text: String) {
        scalars = Array(text.unicodeScalars)
    }

    var isAtEnd: Bool {
        var i = pos
        while i < scalars.count, Self.isSeparator(scalars[i]) { i += 1 }
        return i >= scalars.count
    }

    private static func isSeparator(_ s: UnicodeScalar) -> Bool {
        s == " " || s == "," || s == "\n" || s == "\r" || s == "\t"
    }

    private mutating func skipSeparators() {
        while pos < scalars.count, Self.isSeparator(scalars[pos]) { pos += 1 }
    }

    /// True when the next non-separator character starts a number.
    var nextIsNumber: Bool {
        var i = pos
        while i < scalars.count, Self.isSeparator(scalars[i]) { i += 1 }
        guard i < scalars.count else { return false }
        let s = scalars[i]
        return ("0"..."9").contains(s) || s == "." || s == "-" || s == "+"
    }

    /// The next command letter, if the next non-separator character is one.
    mutating func scanCommand() -> Character? {
        skipSeparators()
        guard pos < scalars.count else { return nil }
        let s = scalars[pos]
        guard ("a"..."z").contains(s) || ("A"..."Z").contains(s) else { return nil }
        pos += 1
        return Character(s)
    }

    /// One number: sign, integer digits, at most one decimal point, optional
    /// exponent. Stops at the second decimal point, so `1.5.5` reads as 1.5
    /// then .5, the way the grammar packs coordinates.
    mutating func scanNumber() -> Double? {
        skipSeparators()
        var i = pos
        var seenDigit = false
        var seenDot = false
        if i < scalars.count, scalars[i] == "+" || scalars[i] == "-" { i += 1 }
        while i < scalars.count {
            let s = scalars[i]
            if ("0"..."9").contains(s) { seenDigit = true; i += 1 }
            else if s == ".", !seenDot { seenDot = true; i += 1 }
            else { break }
        }
        guard seenDigit else { return nil }
        // Optional exponent.
        if i < scalars.count, scalars[i] == "e" || scalars[i] == "E" {
            var j = i + 1
            if j < scalars.count, scalars[j] == "+" || scalars[j] == "-" { j += 1 }
            var expDigits = false
            while j < scalars.count, ("0"..."9").contains(scalars[j]) { expDigits = true; j += 1 }
            if expDigits { i = j }
        }
        let text = String(String.UnicodeScalarView(scalars[pos..<i]))
        pos = i
        return Double(text)
    }

    /// An arc flag: a bare `0` or `1`, possibly glued to the next number.
    mutating func scanFlag() -> Bool? {
        skipSeparators()
        guard pos < scalars.count else { return nil }
        switch scalars[pos] {
        case "0": pos += 1; return false
        case "1": pos += 1; return true
        default: return nil
        }
    }

    mutating func scanPoint() -> Vector2? {
        guard let x = scanNumber(), let y = scanNumber() else { return nil }
        return Vector2(x, y)
    }
}

/// Parse a `d` attribute into subpaths of pen commands (user space).
/// Malformed data parses as far as it stays well-formed, then stops.
func parseSVGPathData(_ d: String) -> [[SVGPathCommand]] {
    var scanner = SVGPathScanner(d)
    var subpaths: [[SVGPathCommand]] = []
    var current: [SVGPathCommand] = []
    var pen = Vector2.zero
    var subpathStart = Vector2.zero
    var lastCubicControl: Vector2? = nil
    var lastQuadControl: Vector2? = nil
    var command: Character? = nil

    func flush() {
        if !current.isEmpty { subpaths.append(current) }
        current = []
    }
    func finishedSubpaths() -> [[SVGPathCommand]] {
        flush()
        return subpaths
    }

    while !scanner.isAtEnd {
        if let next = scanner.scanCommand() {
            command = next
        } else if command == nil || !scanner.nextIsNumber {
            break   // stray characters: stop at the last well-formed command
        }
        guard let cmd = command else { break }
        let relative = cmd.isLowercase
        let upper = Character(cmd.uppercased())
        var resetCubic = true
        var resetQuad = true

        switch upper {
        case "M":
            guard var p = scanner.scanPoint() else { return finishedSubpaths() }
            if relative { p = pen + p }
            flush()
            current.append(.move(p))
            pen = p
            subpathStart = p
            // Later pairs are implicit line commands.
            command = relative ? "l" : "L"
        case "L":
            guard var p = scanner.scanPoint() else { return finishedSubpaths() }
            if relative { p = pen + p }
            current.append(.line(p))
            pen = p
        case "H":
            guard let x = scanner.scanNumber() else { return finishedSubpaths() }
            let p = Vector2(relative ? pen.x + x : x, pen.y)
            current.append(.line(p))
            pen = p
        case "V":
            guard let y = scanner.scanNumber() else { return finishedSubpaths() }
            let p = Vector2(pen.x, relative ? pen.y + y : y)
            current.append(.line(p))
            pen = p
        case "C":
            guard var c1 = scanner.scanPoint(), var c2 = scanner.scanPoint(),
                  var p = scanner.scanPoint() else { return finishedSubpaths() }
            if relative { c1 = pen + c1; c2 = pen + c2; p = pen + p }
            current.append(.cubic(c1, c2, p))
            lastCubicControl = c2
            resetCubic = false
            pen = p
        case "S":
            guard var c2 = scanner.scanPoint(), var p = scanner.scanPoint() else { return finishedSubpaths() }
            if relative { c2 = pen + c2; p = pen + p }
            // First control reflects the previous cubic's second control
            // about the pen; without a preceding cubic it is the pen itself.
            let c1 = lastCubicControl.map { pen * 2 - $0 } ?? pen
            current.append(.cubic(c1, c2, p))
            lastCubicControl = c2
            resetCubic = false
            pen = p
        case "Q":
            guard var c = scanner.scanPoint(), var p = scanner.scanPoint() else { return finishedSubpaths() }
            if relative { c = pen + c; p = pen + p }
            current.append(.quad(c, p))
            lastQuadControl = c
            resetQuad = false
            pen = p
        case "T":
            guard var p = scanner.scanPoint() else { return finishedSubpaths() }
            if relative { p = pen + p }
            let c = lastQuadControl.map { pen * 2 - $0 } ?? pen
            current.append(.quad(c, p))
            lastQuadControl = c
            resetQuad = false
            pen = p
        case "A":
            guard let rx = scanner.scanNumber(), let ry = scanner.scanNumber(),
                  let rotation = scanner.scanNumber(),
                  let largeArc = scanner.scanFlag(), let sweep = scanner.scanFlag(),
                  var p = scanner.scanPoint() else { return finishedSubpaths() }
            if relative { p = pen + p }
            current.append(contentsOf: arcCommands(from: pen, to: p, rx: rx, ry: ry,
                                                   rotationDegrees: rotation,
                                                   largeArc: largeArc, sweep: sweep))
            pen = p
        case "Z":
            current.append(.close)
            pen = subpathStart
            flush()
            // Z takes no arguments; a number here is malformed, and clearing
            // the command makes the next pass stop instead of spinning.
            command = nil
        default:
            return finishedSubpaths()
        }
        if resetCubic { lastCubicControl = nil }
        if resetQuad { lastQuadControl = nil }
    }
    return finishedSubpaths()
}

/// An elliptical arc as cubic segments (at most 90° each): endpoint form to
/// center form, radius correction included, per the specification's
/// implementation notes (F.6.5/F.6.6).
func arcCommands(from p1: Vector2, to p2: Vector2, rx rxIn: Double, ry ryIn: Double,
                 rotationDegrees: Double, largeArc: Bool, sweep: Bool) -> [SVGPathCommand] {
    if p1 == p2 { return [] }
    var rx = abs(rxIn), ry = abs(ryIn)
    if rx == 0 || ry == 0 { return [.line(p2)] }

    let phi = rotationDegrees * .pi / 180
    let cosPhi = cos(phi), sinPhi = sin(phi)
    let dx = (p1.x - p2.x) / 2, dy = (p1.y - p2.y) / 2
    let x1p = cosPhi * dx + sinPhi * dy
    let y1p = -sinPhi * dx + cosPhi * dy

    // Radii too small to span the endpoints scale up to just fit.
    let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
    if lambda > 1 {
        let s = lambda.squareRoot()
        rx *= s
        ry *= s
    }

    let sign: Double = largeArc != sweep ? 1 : -1
    let numerator = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
    let denominator = rx * rx * y1p * y1p + ry * ry * x1p * x1p
    let coef = sign * max(0, numerator / denominator).squareRoot()
    let cxp = coef * rx * y1p / ry
    let cyp = -coef * ry * x1p / rx
    let cx = cosPhi * cxp - sinPhi * cyp + (p1.x + p2.x) / 2
    let cy = sinPhi * cxp + cosPhi * cyp + (p1.y + p2.y) / 2

    func angle(_ ux: Double, _ uy: Double, _ vx: Double, _ vy: Double) -> Double {
        let dot = ux * vx + uy * vy
        let len = ((ux * ux + uy * uy) * (vx * vx + vy * vy)).squareRoot()
        guard len > 0 else { return 0 }
        var a = acos(min(1, max(-1, dot / len)))
        if ux * vy - uy * vx < 0 { a = -a }
        return a
    }
    let theta1 = angle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
    var delta = angle((x1p - cxp) / rx, (y1p - cyp) / ry,
                      (-x1p - cxp) / rx, (-y1p - cyp) / ry)
    if !sweep, delta > 0 { delta -= 2 * .pi }
    if sweep, delta < 0 { delta += 2 * .pi }

    // Split into segments of at most a quarter turn; each becomes one cubic.
    let segments = max(1, Int((abs(delta) / (.pi / 2)).rounded(.up)))
    let step = delta / Double(segments)
    let alpha = 4.0 / 3.0 * tan(step / 4)

    func point(at theta: Double) -> Vector2 {
        Vector2(cx + rx * cosPhi * cos(theta) - ry * sinPhi * sin(theta),
                cy + rx * sinPhi * cos(theta) + ry * cosPhi * sin(theta))
    }
    func derivative(at theta: Double) -> Vector2 {
        Vector2(-rx * cosPhi * sin(theta) - ry * sinPhi * cos(theta),
                -rx * sinPhi * sin(theta) + ry * cosPhi * cos(theta))
    }

    var out: [SVGPathCommand] = []
    var theta = theta1
    for _ in 0..<segments {
        let next = theta + step
        let c1 = point(at: theta) + derivative(at: theta) * alpha
        let c2 = point(at: next) - derivative(at: next) * alpha
        out.append(.cubic(c1, c2, point(at: next)))
        theta = next
    }
    return out
}

/// Transform a subpath's control points and flatten it into a `Contour`.
/// Transforming *before* flattening keeps the curve sampling density matched
/// to the final on-canvas size (control points carry through an affine map
/// exactly; arcs were already converted to cubics in user space).
func flattenSVGSubpath(_ commands: [SVGPathCommand], transform: SVGTransform) -> Contour? {
    var path = Path()
    var closed = false
    for command in commands {
        switch command {
        case .move(let p): path.move(to: transform.apply(p))
        case .line(let p): path.line(to: transform.apply(p))
        case .cubic(let c1, let c2, let p):
            path.cubicCurve(to: transform.apply(p),
                            control1: transform.apply(c1), control2: transform.apply(c2))
        case .quad(let c, let p):
            path.quadCurve(to: transform.apply(p), control: transform.apply(c))
        case .close:
            closed = true
        }
    }
    if closed { path.close() }
    var contour = path.contour
    // A closed contour whose last sampled point returns onto the start would
    // double the seam when stroked; drop the duplicate.
    if contour.isClosed, contour.points.count > 1,
       let first = contour.points.first, let last = contour.points.last,
       (first - last).length < 1e-9 {
        contour.points.removeLast()
    }
    return contour.points.count >= 2 ? contour : nil
}

// MARK: - Transform and style parsing

/// Parse a `transform` attribute list into one composed transform.
func parseSVGTransformList(_ text: String) -> SVGTransform {
    var scanner = SVGPathScanner(text)
    var result = SVGTransform.identity
    let names: Set<String> = ["matrix", "translate", "scale", "rotate", "skewX", "skewY"]
    var pending = ""
    var i = text.startIndex

    // Walk `name(args)` groups by hand: names are words, args are the shared
    // number grammar.
    while i < text.endIndex {
        let ch = text[i]
        if ch.isLetter {
            pending.append(ch)
            i = text.index(after: i)
            continue
        }
        if ch == "(" {
            let name = pending
            pending = ""
            guard names.contains(name),
                  let closing = text[i...].firstIndex(of: ")") else { return result }
            let args = String(text[text.index(after: i)..<closing])
            scanner = SVGPathScanner(args)
            var values: [Double] = []
            while let v = scanner.scanNumber() { values.append(v) }
            switch (name, values.count) {
            case ("matrix", 6):
                result = result.concatenating(SVGTransform(a: values[0], b: values[1], c: values[2],
                                                           d: values[3], e: values[4], f: values[5]))
            case ("translate", 1):
                result = result.concatenating(.translate(values[0], 0))
            case ("translate", 2):
                result = result.concatenating(.translate(values[0], values[1]))
            case ("scale", 1):
                result = result.concatenating(.scale(values[0], values[0]))
            case ("scale", 2):
                result = result.concatenating(.scale(values[0], values[1]))
            case ("rotate", 1):
                result = result.concatenating(.rotate(degrees: values[0]))
            case ("rotate", 3):
                result = result.concatenating(.translate(values[1], values[2]))
                result = result.concatenating(.rotate(degrees: values[0]))
                result = result.concatenating(.translate(-values[1], -values[2]))
            case ("skewX", 1):
                result = result.concatenating(.skewX(degrees: values[0]))
            case ("skewY", 1):
                result = result.concatenating(.skewY(degrees: values[0]))
            default:
                break   // wrong arity: skip this group, keep going
            }
            i = text.index(after: closing)
            continue
        }
        pending = ""
        i = text.index(after: i)
    }
    return result
}

/// One parsed paint value: a color, an explicit none, or a reference the
/// importer can't resolve (a gradient or pattern url).
enum SVGPaintValue: Equatable {
    case color(Color)
    case none
    case unresolved
}

/// Parse an SVG color/paint string: `none`, `#rgb`, `#rrggbb` (and their
/// alpha forms), `rgb()`/`rgba()` with numbers or percentages, and the CSS
/// named-color keywords.
func parseSVGPaint(_ raw: String) -> SVGPaintValue? {
    let text = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if text.isEmpty || text == "inherit" { return nil }
    if text == "none" { return SVGPaintValue.none }
    if text == "transparent" { return .color(.clear) }
    if text == "currentcolor" { return .color(.black) }
    if text.hasPrefix("url(") { return .unresolved }

    if text.hasPrefix("#") {
        let hex = String(text.dropFirst())
        func nibble(_ c: Character) -> UInt32? { UInt32(String(c), radix: 16) }
        switch hex.count {
        case 3, 4:
            var channels: [UInt32] = []
            for c in hex {
                guard let n = nibble(c) else { return nil }
                channels.append(n * 17)
            }
            let alpha = channels.count == 4 ? Double(channels[3]) / 255 : 1
            return .color(Color(hex: channels[0] << 16 | channels[1] << 8 | channels[2], alpha: alpha))
        case 6, 8:
            guard let value = UInt32(hex, radix: 16) else { return nil }
            if hex.count == 8 {
                return .color(Color(hex: value >> 8, alpha: Double(value & 0xFF) / 255))
            }
            return .color(Color(hex: value))
        default:
            return nil
        }
    }

    if text.hasPrefix("rgb(") || text.hasPrefix("rgba(") {
        guard let open = text.firstIndex(of: "("), let close = text.lastIndex(of: ")") else { return nil }
        let parts = text[text.index(after: open)..<close]
            .split(whereSeparator: { $0 == "," || $0 == " " || $0 == "/" })
        guard parts.count >= 3 else { return nil }
        func channel(_ s: Substring) -> Double? {
            if s.hasSuffix("%") { return Double(s.dropLast()).map { $0 / 100 } }
            return Double(s).map { $0 / 255 }
        }
        guard let r = channel(parts[0]), let g = channel(parts[1]), let b = channel(parts[2]) else { return nil }
        var alpha = 1.0
        if parts.count >= 4 {
            if parts[3].hasSuffix("%") { alpha = Double(parts[3].dropLast()).map { $0 / 100 } ?? 1 }
            else { alpha = Double(parts[3]) ?? 1 }
        }
        func clamp01(_ v: Double) -> Double { min(1, max(0, v)) }
        return .color(Color(red: clamp01(r), green: clamp01(g), blue: clamp01(b), alpha: clamp01(alpha)))
    }

    if let hex = svgNamedColors[text] {
        return .color(Color(hex: hex))
    }
    return nil
}

/// The CSS `<named-color>` keyword set (spec sRGB values).
let svgNamedColors: [String: UInt32] = [
    "aliceblue": 0xF0F8FF, "antiquewhite": 0xFAEBD7, "aqua": 0x00FFFF,
    "aquamarine": 0x7FFFD4, "azure": 0xF0FFFF, "beige": 0xF5F5DC,
    "bisque": 0xFFE4C4, "black": 0x000000, "blanchedalmond": 0xFFEBCD,
    "blue": 0x0000FF, "blueviolet": 0x8A2BE2, "brown": 0xA52A2A,
    "burlywood": 0xDEB887, "cadetblue": 0x5F9EA0, "chartreuse": 0x7FFF00,
    "chocolate": 0xD2691E, "coral": 0xFF7F50, "cornflowerblue": 0x6495ED,
    "cornsilk": 0xFFF8DC, "crimson": 0xDC143C, "cyan": 0x00FFFF,
    "darkblue": 0x00008B, "darkcyan": 0x008B8B, "darkgoldenrod": 0xB8860B,
    "darkgray": 0xA9A9A9, "darkgreen": 0x006400, "darkgrey": 0xA9A9A9,
    "darkkhaki": 0xBDB76B, "darkmagenta": 0x8B008B, "darkolivegreen": 0x556B2F,
    "darkorange": 0xFF8C00, "darkorchid": 0x9932CC, "darkred": 0x8B0000,
    "darksalmon": 0xE9967A, "darkseagreen": 0x8FBC8F, "darkslateblue": 0x483D8B,
    "darkslategray": 0x2F4F4F, "darkslategrey": 0x2F4F4F, "darkturquoise": 0x00CED1,
    "darkviolet": 0x9400D3, "deeppink": 0xFF1493, "deepskyblue": 0x00BFFF,
    "dimgray": 0x696969, "dimgrey": 0x696969, "dodgerblue": 0x1E90FF,
    "firebrick": 0xB22222, "floralwhite": 0xFFFAF0, "forestgreen": 0x228B22,
    "fuchsia": 0xFF00FF, "gainsboro": 0xDCDCDC, "ghostwhite": 0xF8F8FF,
    "gold": 0xFFD700, "goldenrod": 0xDAA520, "gray": 0x808080,
    "green": 0x008000, "greenyellow": 0xADFF2F, "grey": 0x808080,
    "honeydew": 0xF0FFF0, "hotpink": 0xFF69B4, "indianred": 0xCD5C5C,
    "indigo": 0x4B0082, "ivory": 0xFFFFF0, "khaki": 0xF0E68C,
    "lavender": 0xE6E6FA, "lavenderblush": 0xFFF0F5, "lawngreen": 0x7CFC00,
    "lemonchiffon": 0xFFFACD, "lightblue": 0xADD8E6, "lightcoral": 0xF08080,
    "lightcyan": 0xE0FFFF, "lightgoldenrodyellow": 0xFAFAD2, "lightgray": 0xD3D3D3,
    "lightgreen": 0x90EE90, "lightgrey": 0xD3D3D3, "lightpink": 0xFFB6C1,
    "lightsalmon": 0xFFA07A, "lightseagreen": 0x20B2AA, "lightskyblue": 0x87CEFA,
    "lightslategray": 0x778899, "lightslategrey": 0x778899, "lightsteelblue": 0xB0C4DE,
    "lightyellow": 0xFFFFE0, "lime": 0x00FF00, "limegreen": 0x32CD32,
    "linen": 0xFAF0E6, "magenta": 0xFF00FF, "maroon": 0x800000,
    "mediumaquamarine": 0x66CDAA, "mediumblue": 0x0000CD, "mediumorchid": 0xBA55D3,
    "mediumpurple": 0x9370DB, "mediumseagreen": 0x3CB371, "mediumslateblue": 0x7B68EE,
    "mediumspringgreen": 0x00FA9A, "mediumturquoise": 0x48D1CC, "mediumvioletred": 0xC71585,
    "midnightblue": 0x191970, "mintcream": 0xF5FFFA, "mistyrose": 0xFFE4E1,
    "moccasin": 0xFFE4B5, "navajowhite": 0xFFDEAD, "navy": 0x000080,
    "oldlace": 0xFDF5E6, "olive": 0x808000, "olivedrab": 0x6B8E23,
    "orange": 0xFFA500, "orangered": 0xFF4500, "orchid": 0xDA70D6,
    "palegoldenrod": 0xEEE8AA, "palegreen": 0x98FB98, "paleturquoise": 0xAFEEEE,
    "palevioletred": 0xDB7093, "papayawhip": 0xFFEFD5, "peachpuff": 0xFFDAB9,
    "peru": 0xCD853F, "pink": 0xFFC0CB, "plum": 0xDDA0DD,
    "powderblue": 0xB0E0E6, "purple": 0x800080, "rebeccapurple": 0x663399,
    "red": 0xFF0000, "rosybrown": 0xBC8F8F, "royalblue": 0x4169E1,
    "saddlebrown": 0x8B4513, "salmon": 0xFA8072, "sandybrown": 0xF4A460,
    "seagreen": 0x2E8B57, "seashell": 0xFFF5EE, "sienna": 0xA0522D,
    "silver": 0xC0C0C0, "skyblue": 0x87CEEB, "slateblue": 0x6A5ACD,
    "slategray": 0x708090, "slategrey": 0x708090, "snow": 0xFFFAFA,
    "springgreen": 0x00FF7F, "steelblue": 0x4682B4, "tan": 0xD2B48C,
    "teal": 0x008080, "thistle": 0xD8BFD8, "tomato": 0xFF6347,
    "turquoise": 0x40E0D0, "violet": 0xEE82EE, "wheat": 0xF5DEB3,
    "white": 0xFFFFFF, "whitesmoke": 0xF5F5F5, "yellow": 0xFFFF00,
    "yellowgreen": 0x9ACD32,
]

// MARK: - Document parser

/// The streaming XML walk: a graphics-state stack over the element tree,
/// emitting one `SVG.Element` per leaf shape.
final class SVGDocumentParser: NSObject, XMLParserDelegate {
    /// The inheritable graphics state in force at one tree depth.
    private struct GState {
        var ctm = SVGTransform.identity
        var fill = SVGPaintValue.color(.black)   // the SVG initial fill
        var stroke = SVGPaintValue.none
        var strokeWidth = 1.0
        var fillRule = FillWinding.nonZero       // the SVG initial rule
        var join = StrokeJoin.miter
        var cap = StrokeCap.butt
        var opacity = 1.0                        // accumulated group opacity
        var fillOpacity = 1.0
        var strokeOpacity = 1.0
        var display = true
    }

    private var stack: [GState] = [GState()]
    private var elements: [SVG.Element] = []
    private var viewBox: Rectangle? = nil
    private var sawRoot = false
    /// Non-zero inside a subtree with no drawable geometry (defs, masks,
    /// symbols, text); everything under it is skipped.
    private var skipDepth = 0
    private static let skippedContainers: Set<String> = [
        "defs", "clippath", "mask", "symbol", "pattern", "marker",
        "lineargradient", "radialgradient", "style", "text", "metadata",
        "title", "desc", "filter", "foreignobject", "script",
    ]

    func parse(_ data: Data) -> SVG? {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.shouldProcessNamespaces = false
        guard parser.parse() || !elements.isEmpty else { return nil }
        guard sawRoot else { return nil }
        let bounds = viewBox ?? Self.tightBounds(of: elements) ?? Rectangle(x: 0, y: 0, width: 0, height: 0)
        guard !elements.isEmpty else { return nil }
        return SVG(elements: elements, bounds: bounds)
    }

    private static func tightBounds(of elements: [SVG.Element]) -> Rectangle? {
        var minX = Double.infinity, minY = Double.infinity
        var maxX = -Double.infinity, maxY = -Double.infinity
        for element in elements {
            for contour in element.shape.contours {
                for p in contour.points {
                    minX = min(minX, p.x); minY = min(minY, p.y)
                    maxX = max(maxX, p.x); maxY = max(maxY, p.y)
                }
            }
        }
        guard minX < maxX || minY < maxY else { return nil }
        return Rectangle(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    // MARK: XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String]) {
        let name = elementName.lowercased()
        if skipDepth > 0 || Self.skippedContainers.contains(name) {
            skipDepth += 1
            stack.append(stack.last ?? GState())
            return
        }

        var state = stack.last ?? GState()
        applyAttributes(attributeDict, to: &state)
        stack.append(state)

        switch name {
        case "svg":
            if !sawRoot {
                sawRoot = true
                if let vb = attributeDict["viewBox"] ?? attributeDict["viewbox"] {
                    var scanner = SVGPathScanner(vb)
                    if let x = scanner.scanNumber(), let y = scanner.scanNumber(),
                       let w = scanner.scanNumber(), let h = scanner.scanNumber(),
                       w > 0, h > 0 {
                        viewBox = Rectangle(x: x, y: y, width: w, height: h)
                    }
                }
            }
        case "g":
            break   // state already pushed
        case "path":
            guard let d = attributeDict["d"] else { break }
            let contours = parseSVGPathData(d).compactMap { flattenSVGSubpath($0, transform: state.ctm) }
            emit(contours: contours, state: state, id: attributeDict["id"])
        case "rect":
            emit(subpaths: [rectSubpath(attributeDict)], state: state, id: attributeDict["id"])
        case "circle":
            let cx = length(attributeDict["cx"]) ?? 0
            let cy = length(attributeDict["cy"]) ?? 0
            guard let r = length(attributeDict["r"]), r > 0 else { break }
            emit(subpaths: [ellipseSubpath(cx: cx, cy: cy, rx: r, ry: r)],
                 state: state, id: attributeDict["id"])
        case "ellipse":
            let cx = length(attributeDict["cx"]) ?? 0
            let cy = length(attributeDict["cy"]) ?? 0
            guard let rx = length(attributeDict["rx"]), rx > 0,
                  let ry = length(attributeDict["ry"]), ry > 0 else { break }
            emit(subpaths: [ellipseSubpath(cx: cx, cy: cy, rx: rx, ry: ry)],
                 state: state, id: attributeDict["id"])
        case "line":
            let x1 = length(attributeDict["x1"]) ?? 0, y1 = length(attributeDict["y1"]) ?? 0
            let x2 = length(attributeDict["x2"]) ?? 0, y2 = length(attributeDict["y2"]) ?? 0
            emit(subpaths: [[.move(Vector2(x1, y1)), .line(Vector2(x2, y2))]],
                 state: state, id: attributeDict["id"])
        case "polyline", "polygon":
            guard let list = attributeDict["points"] else { break }
            var scanner = SVGPathScanner(list)
            var points: [Vector2] = []
            while let p = scanner.scanPoint() { points.append(p) }
            guard points.count >= 2 else { break }
            var subpath: [SVGPathCommand] = [.move(points[0])]
            subpath.append(contentsOf: points.dropFirst().map { .line($0) })
            if name == "polygon" { subpath.append(.close) }
            emit(subpaths: [subpath], state: state, id: attributeDict["id"])
        default:
            break   // unknown element: state pushed, children still walk
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        if stack.count > 1 { stack.removeLast() }
        if skipDepth > 0 { skipDepth -= 1 }
    }

    // MARK: Attribute handling

    /// Fold an element's presentation attributes and inline `style` into the
    /// inherited state (the inline style wins, matching CSS precedence).
    private func applyAttributes(_ attributes: [String: String], to state: inout GState) {
        if let t = attributes["transform"] {
            state.ctm = state.ctm.concatenating(parseSVGTransformList(t))
        }
        var properties: [(String, String)] = attributes.map { ($0.key.lowercased(), $0.value) }
        if let style = attributes["style"] {
            for declaration in style.split(separator: ";") {
                let pair = declaration.split(separator: ":", maxSplits: 1)
                guard pair.count == 2 else { continue }
                properties.append((pair[0].trimmingCharacters(in: .whitespaces).lowercased(),
                                   pair[1].trimmingCharacters(in: .whitespaces)))
            }
        }
        for (key, value) in properties {
            switch key {
            case "fill":
                if let paint = parseSVGPaint(value) { state.fill = paint }
            case "stroke":
                if let paint = parseSVGPaint(value) { state.stroke = paint }
            case "stroke-width":
                if let w = length(value) { state.strokeWidth = w }
            case "fill-rule":
                if value == "evenodd" { state.fillRule = .evenOdd }
                else if value == "nonzero" { state.fillRule = .nonZero }
            case "stroke-linejoin":
                switch value {
                case "miter": state.join = .miter
                case "round": state.join = .round
                case "bevel": state.join = .bevel
                default: break
                }
            case "stroke-linecap":
                switch value {
                case "butt": state.cap = .butt
                case "round": state.cap = .round
                case "square": state.cap = .square
                default: break
                }
            case "opacity":
                if let o = Double(value) { state.opacity *= min(1, max(0, o)) }
            case "fill-opacity":
                if let o = Double(value) { state.fillOpacity = min(1, max(0, o)) }
            case "stroke-opacity":
                if let o = Double(value) { state.strokeOpacity = min(1, max(0, o)) }
            case "display":
                if value == "none" { state.display = false }
            case "visibility":
                if value == "hidden" || value == "collapse" { state.display = false }
            default:
                break
            }
        }
    }

    /// A length attribute: the numeric prefix, ignoring a trailing unit.
    private func length(_ text: String?) -> Double? {
        guard let text else { return nil }
        var scanner = SVGPathScanner(text)
        return scanner.scanNumber()
    }

    // MARK: Shape synthesis

    private func rectSubpath(_ attributes: [String: String]) -> [SVGPathCommand] {
        let x = length(attributes["x"]) ?? 0, y = length(attributes["y"]) ?? 0
        guard let w = length(attributes["width"]), w > 0,
              let h = length(attributes["height"]), h > 0 else { return [] }
        var rx = length(attributes["rx"])
        var ry = length(attributes["ry"])
        if rx == nil { rx = ry }
        if ry == nil { ry = rx }
        let radiusX = min(max(rx ?? 0, 0), w / 2)
        let radiusY = min(max(ry ?? 0, 0), h / 2)
        if radiusX <= 0 || radiusY <= 0 {
            return [.move(Vector2(x, y)), .line(Vector2(x + w, y)),
                    .line(Vector2(x + w, y + h)), .line(Vector2(x, y + h)), .close]
        }
        // Rounded: straight runs joined by quarter-ellipse corners.
        let k = 0.5522847498307936   // cubic quarter-circle control distance
        let cx = radiusX * k, cy = radiusY * k
        return [
            .move(Vector2(x + radiusX, y)),
            .line(Vector2(x + w - radiusX, y)),
            .cubic(Vector2(x + w - radiusX + cx, y), Vector2(x + w, y + radiusY - cy), Vector2(x + w, y + radiusY)),
            .line(Vector2(x + w, y + h - radiusY)),
            .cubic(Vector2(x + w, y + h - radiusY + cy), Vector2(x + w - radiusX + cx, y + h), Vector2(x + w - radiusX, y + h)),
            .line(Vector2(x + radiusX, y + h)),
            .cubic(Vector2(x + radiusX - cx, y + h), Vector2(x, y + h - radiusY + cy), Vector2(x, y + h - radiusY)),
            .line(Vector2(x, y + radiusY)),
            .cubic(Vector2(x, y + radiusY - cy), Vector2(x + radiusX - cx, y), Vector2(x + radiusX, y)),
            .close,
        ]
    }

    private func ellipseSubpath(cx: Double, cy: Double, rx: Double, ry: Double) -> [SVGPathCommand] {
        let k = 0.5522847498307936
        let ox = rx * k, oy = ry * k
        return [
            .move(Vector2(cx + rx, cy)),
            .cubic(Vector2(cx + rx, cy + oy), Vector2(cx + ox, cy + ry), Vector2(cx, cy + ry)),
            .cubic(Vector2(cx - ox, cy + ry), Vector2(cx - rx, cy + oy), Vector2(cx - rx, cy)),
            .cubic(Vector2(cx - rx, cy - oy), Vector2(cx - ox, cy - ry), Vector2(cx, cy - ry)),
            .cubic(Vector2(cx + ox, cy - ry), Vector2(cx + rx, cy - oy), Vector2(cx + rx, cy)),
            .close,
        ]
    }

    // MARK: Emission

    private func emit(subpaths: [[SVGPathCommand]], state: GState, id: String?) {
        let contours = subpaths.compactMap { flattenSVGSubpath($0, transform: state.ctm) }
        emit(contours: contours, state: state, id: id)
    }

    private func emit(contours: [Contour], state: GState, id: String?) {
        guard state.display, !contours.isEmpty else { return }
        let hasClosed = contours.contains(where: \.isClosed)

        func resolved(_ paint: SVGPaintValue, opacity: Double) -> Color? {
            switch paint {
            case .none: return nil
            case .unresolved:
                // A gradient/pattern reference: keep the form visible.
                return Color.gray.withAlpha(state.opacity * opacity)
            case .color(let color):
                let alpha = color.alpha * state.opacity * opacity
                return alpha == color.alpha ? color : color.withAlpha(alpha)
            }
        }

        let fill = hasClosed ? resolved(state.fill, opacity: state.fillOpacity) : nil
        let stroke = resolved(state.stroke, opacity: state.strokeOpacity)
        elements.append(SVG.Element(shape: Shape(contours: contours, winding: state.fillRule),
                                    fill: fill,
                                    stroke: stroke,
                                    strokeWidth: state.strokeWidth * state.ctm.lengthScale,
                                    join: state.join,
                                    cap: state.cap,
                                    name: id))
    }
}
