import Ollin

/// Shapes filled as what they are made of: thick paint that rises along its
/// outline and catches the light, paint spread with a knife, a wash that
/// glazes the grid under it and gouache that covers it, chrome that reflects
/// the grid around it, plain and faceted glass that bend it, and rock, marble,
/// and sand. One picker across the ten media, each set with `fillMedium(_:)`
/// beside `fill`.
///
/// The blobs take their colors from a palette scheme built around one hue
/// (`Palette.scheme`): a single hue from deep to light, a wheel whose near half
/// is vivid and far half dark, the vivid wheel, or a pastel or dark cluster.
/// The swatches along the bottom are the palette itself. Turn the hue to move
/// the whole scheme around the wheel.
///
/// The blobs sway in place, so the light plays across their relief and the
/// glass slides over the grid. Drag a loop to add a blob of your own in the
/// next color; `c` clears what you drew.
@main
final class PaintedFills: Sketch {
    enum Medium: String, CaseIterable, ParamOption {
        case impasto, knife, wash, gouache, chrome, glass, facetedGlass, rock, marble, sand

        var fill: FillMedium {
            switch self {
            case .impasto: .impasto
            case .knife: .knife
            case .wash: .wash
            case .gouache: .gouache
            case .chrome: .chrome
            case .glass: .glass
            case .facetedGlass: .facetedGlass
            case .rock: .rock
            case .marble: .marble
            case .sand: .sand
            }
        }
    }

    enum Scheme: String, CaseIterable, ParamOption {
        case monochrome, vividAndDark, vivid, pastel, dark

        var scheme: Palette.Scheme {
            switch self {
            case .monochrome: .monochrome
            case .vividAndDark: .vividAndDark
            case .vivid: .vivid
            case .pastel: .pastel
            case .dark: .dark
            }
        }
    }

    @Param(icon: "paintbrush") var medium = Medium.impasto
    @Param(icon: "swatchpalette") var scheme = Scheme.vividAndDark
    @Param("Hue", 0 ... 1, icon: "circle.lefthalf.filled") var hue = 0.07

    override var loopDuration: Double? { 12 }

    /// The blobs: each outline in its own coordinates around the origin, where
    /// it stands, and its color's place in the palette.
    var blobs: [(shape: Shape, center: Vector2, slot: Int)] = []
    /// The loop under the pointer while it is dragged.
    var loop: [Vector2] = []

    let paper = Color(red: 0.95, green: 0.93, blue: 0.89)
    let ink = Color(red: 0.16, green: 0.17, blue: 0.22)

    override func setup() {
        let places = [Vector2(300, 300), Vector2(770, 280), Vector2(540, 560),
                      Vector2(280, 760), Vector2(790, 760)]
        for (i, place) in places.enumerated() {
            blobs.append((outline(radius: 150 + Double(i % 2) * 25, seed: Double(i) * 1.7), place, i))
        }
    }

    override func draw() {
        let palette = Palette.scheme(scheme.scheme, key: .mostVivid(hue: hue), count: 5)
        background(paper)
        drawGround()

        // Each blob sways around its own middle, by its own phase.
        let t = loopProgress(over: 12) * .tau
        noStroke()
        fillMedium(medium.fill)
        for (i, blob) in blobs.enumerated() {
            withState {
                translate(blob.center + Vector2(0, 10 * sin(t + Double(i))))
                rotate(0.22 * sin(t + Double(i) * 1.3))
                fill(palette[blob.slot])
                drawShape(blob.shape)
            }
        }
        noFillMedium()

        // The loop being dragged, as a line.
        if mouseIsPressed, let last = loop.last, (mouse - last).length > 6 { loop.append(mouse) }
        if loop.count > 1 {
            noFill()
            stroke(ink)
            strokeWeight(3)
            drawPolyline(loop)
        }

        // The palette, flat, and the caption.
        noStroke()
        for i in 0 ..< palette.count {
            fill(palette[i])
            drawRect(40 + Double(i) * 64, height - 96, 56, 40, cornerRadius: 6)
        }
        fill(ink)
        textSize(20)
        textAlign(.left, .bottom)
        drawText("\(medium.rawValue)  ·  \(scheme.rawValue)  ·  drag a loop to add one  ·  c clears",
                 40, height - 24)
    }

    /// The paper's grid, which the wash glazes, the chrome reflects, and the
    /// glass bends.
    func drawGround() {
        noFillMedium()
        stroke(ink)
        strokeWeight(4)
        for x in stride(from: 27.0, to: width, by: 54) { drawLine(x, 0, x, height) }
        strokeWeight(2)
        for y in stride(from: 27.0, to: height, by: 54) { drawLine(0, y, width, y) }
    }

    /// A rounded blob around the origin, its radius wandering by a few slow waves.
    func outline(radius: Double, seed: Double) -> Shape {
        let points = (0 ..< 180).map { i -> Vector2 in
            let a = Double(i) / 180 * .tau
            let r = radius * (1 + 0.13 * sin(3 * a + seed) + 0.07 * sin(5 * a + 2 * seed) + 0.04 * cos(2 * a - seed))
            return Vector2(cos(a), sin(a)) * r
        }
        return Shape(contours: [Contour(points, closed: true)])
    }

    override func mousePressed() {
        loop = [mouse]
    }

    override func mouseReleased() {
        defer { loop = [] }
        guard loop.count > 8 else { return }
        // The loop, closed and smoothed, around its own middle.
        let middle = loop.reduce(Vector2(0, 0), +) / Double(loop.count)
        let shape = Shape(curveThrough: loop.map { $0 - middle })
        blobs.append((shape, middle, blobs.count % 5))
    }

    override func keyPressed() {
        if key == "c" { blobs.removeLast(max(blobs.count - 5, 0)) }
    }
}
