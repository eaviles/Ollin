import Ollin

/// **Rivers**: the drainage of a landscape, worked out rather than drawn.
///
/// Nothing here decides where a river should go. Water on any cell runs to
/// whichever neighbor is steepest downhill, and a cell joins the network once
/// enough ground drains through it. The branching comes out of the ground
/// itself, which is why it looks like branching you have seen.
///
/// The lines thicken by Strahler's order rather than by flow. A headwater is
/// one. Two of the same order meeting make the next one up, and an unequal pair
/// keeps the larger, so the thickness counts how much of the branching upstream
/// is behind a reach.
///
/// Try it: `minFlow` is the smallest catchment you are willing to call a
/// river, in cells. Take it down and a fine tracery fills every crease of the
/// terrain. Take it up and only a few trunks are left. `weathered` runs the
/// rain erosion first, and the network sharpens because the valleys it carved
/// are the ones the water then finds.
@main
final class RiversSketch: Sketch {
    @Param(20 ... 900, icon: "drop") var minFlow = 140.0
    @Param(1 ... 99, icon: "dice") var landSeed = 7.0
    @Param(icon: "cloud.rain") var weathered = true
    @Param(icon: "square.grid.3x3") var showBasins = false

    private let paper = Color(hex: 0x10131A)
    private let chalk = Color(hex: 0xF2ECDD)
    private let water = Color(hex: 0x6FA8DC)
    private let warm = Color(hex: 0xE0724A)

    private var land = Heightfield(columns: 2, rows: 2)
    private var drainage: Drainage?
    private var contours: [Contour] = []
    private var built = ""

    private var map: Rectangle {
        Rectangle(center: Vector2(width / 2, height * 0.47),
                  width: width * 0.86, height: width * 0.86)
    }

    override func draw() {
        background(paper)
        rebuildIfNeeded()
        guard let drainage else { return }

        // The ground as a contour map, so the network reads against the shape
        // it came out of, and the whole picture stays lines a pen could draw.
        noFill()
        stroke(chalk.withAlpha(showBasins ? 0.08 : 0.16))
        strokeWeight(1)
        for line in contours { drawPolyline(line.points, closed: line.isClosed) }

        if showBasins { drawBasins(drainage) }

        noFill()
        strokeCap(.round)
        strokeJoin(.round)
        for river in drainage.rivers(minFlow: minFlow, in: map) {
            guard river.points.count >= 2 else { continue }
            stroke(Color.mix(water, chalk, min(1, Double(river.order - 1) / 4))
                .withAlpha(0.55 + 0.1 * Double(min(river.order, 4))))
            strokeWeight(0.7 + Double(river.order) * 0.9)
            drawPolyline(river.points)
        }

        drawCaption(drainage)
    }

    // MARK: - Building it

    private func rebuildIfNeeded() {
        let key = "\(landSeed.rounded())|\(weathered)"
        guard key != built else { return }
        built = key

        let seed = UInt64(landSeed.rounded())
        var field = Heightfield.diamondSquare(size: 257, roughness: 0.55, seed: seed)
        if weathered {
            field = field.eroded(.hydraulic(drops: 50_000), seed: seed)
                .eroded(.thermal(talus: 0.012, iterations: 30))
        }
        land = field
        drainage = field.drainage()
        let box = map
        contours = isolines(at: (1 ... 13).map { Double($0) / 14 }, in: box, resolution: 220) {
            field.value(u: box.uv(of: $0).x, v: box.uv(of: $0).y)
        }.flatMap { $0 }
    }

    /// Each basin in its own tone, so where one river's ground ends and the
    /// next one's begins can be seen at all.
    private func drawBasins(_ drainage: Drainage) {
        let cell = map.width / Double(drainage.columns)
        noStroke()
        for y in stride(from: 0, to: drainage.rows, by: 2) {
            for x in stride(from: 0, to: drainage.columns, by: 2) {
                let which = drainage.basin(x, y)
                guard which >= 0 else { continue }
                // Hue runs 0 to 1, stepped by the golden ratio so neighboring
                // basins land far apart in color.
                fill(Color(hue: Double(which) * 0.61803, saturation: 0.45,
                           brightness: 0.5, alpha: 0.5))
                let point = drainage.point(x, y, in: map)
                drawRect(corner: point, width: cell * 2, height: cell * 2)
            }
        }
    }

    private func drawCaption(_ drainage: Drainage) {
        let reaches = drainage.rivers(minFlow: minFlow, in: map).count
        let biggest = drainage.flow.max() ?? 0
        textSize(17)
        textAlign(.center)
        fill(chalk.withAlpha(0.55))
        drawText("\(reaches) reaches over \(Int(minFlow)) cells, in \(drainage.outlets.count) basins",
                 width / 2, height * 0.955)
        fill(warm.withAlpha(0.75))
        drawText("the largest river carries \(Int(biggest)) of the \(drainage.columns * drainage.rows)",
                 width / 2, height * 0.925)
    }
}
