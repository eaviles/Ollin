import Ollin

/// A chart with more in it than one screen can show, and a view you can move.
///
/// `viewControl()` hands the view to whoever is watching: drag to pan, scroll to
/// zoom. It leaves a plain transform in force, so everything drawn after it
/// moves together. The HUD is drawn outside a `withState` block, so it stays
/// put at its own size while the chart travels under it.
///
/// The reason to zoom is that the chart is drawn as vectors. The place names are
/// set at four units, which is a smudge at the opening view and perfectly crisp
/// four notches in. Nothing is re-rendered to get there: the glyph outlines are
/// scaled by the same transform as everything else.
///
/// The mouse is remapped into the coordinates on screen, which is why the
/// crosshair sits under the pointer whatever the zoom, and why the nearest place
/// is found by comparing against the pointer directly.
///
/// See Docs/Drawing/Drawing.md.
@main
final class PanAndZoom: Sketch {
    struct Place {
        var at: Vector2
        var name: String
        var big: Bool
    }

    var places: [Place] = []
    var coast: [Vector2] = []

    let land = Color(hex: 0xF3EFE4)
    let ink = Color(hex: 0x1F3038)
    let sea = Color(hex: 0xD3E1E4)
    let mark = Color(hex: 0xB4553B)

    static let syllables = ["mor", "ken", "dal", "vik", "hol", "brae", "ness", "fell",
                            "thwaite", "garth", "wick", "stad", "ford", "mere", "tarn"]

    override func setup() {
        textFont(OutlineFont.system)
        randomSeed(11)
        noiseSeed(11)
        buildCoast()
        buildPlaces()
    }

    override func draw() {
        background(sea)
        withState {
            viewControl()
            drawChart()
        }
        drawHUD()
    }

    // MARK: The chart, drawn in canvas coordinates

    func drawChart() {
        // A tessellated `Shape`, not `drawPolygon`: the coastline is concave, and
        // the polygon path is the convex one.
        noStroke()
        fill(land)
        drawShape(Shape(coast))
        noFill()
        stroke(ink.withAlpha(0.35))
        strokeWeight(1.4 / viewZoom)
        drawPolyline(coast, closed: true)

        stroke(ink.withAlpha(0.10))
        strokeWeight(0.6)
        for k in stride(from: 0.0, through: 1080, by: 60) {
            drawLine(k, 0, k, 1080)
            drawLine(0, k, 1080, k)
        }

        for place in places { draw(place) }
        drawCrosshair()
    }

    func draw(_ place: Place) {
        noStroke()
        fill(place.big ? mark : ink.withAlpha(0.7))
        drawCircle(center: place.at, radius: place.big ? 3.2 : 1.6)
        fill(ink.withAlpha(place.big ? 0.85 : 0.55))
        textSize(place.big ? 6 : 4)
        textAlign(.left, .center)
        drawText(place.name, place.at.x + (place.big ? 6 : 4), place.at.y)
    }

    /// The pointer, in the coordinates the chart is drawn in.
    func drawCrosshair() {
        noFill()
        stroke(mark.withAlpha(0.7))
        strokeWeight(1.2 / viewZoom)
        let reach = 14 / viewZoom
        drawLine(mouseX - reach, mouseY, mouseX + reach, mouseY)
        drawLine(mouseX, mouseY - reach, mouseX, mouseY + reach)
    }

    // MARK: The HUD, drawn at its own size

    func drawHUD() {
        let nearest = places.min { $0.at.distance(to: mouse)
                                 < $1.at.distance(to: mouse) }
        noStroke()
        fill(land.withAlpha(0.94))
        drawRect(0, 0, 1080, 92)
        fill(ink)
        textSize(26)
        textAlign(.left, .center)
        drawText("drag to pan, scroll to zoom", 40, 46)
        fill(ink.withAlpha(0.5))
        textSize(22)
        textAlign(.right, .center)
        let zoom = String(format: "%.2f", viewZoom)
        drawText("\(zoom)x   nearest: \(nearest?.name ?? "—")", 1040, 46)
    }

    // MARK: Building the chart once

    /// A closed coastline from looping noise, so it meets itself.
    func buildCoast() {
        let middle = Vector2(540, 560)
        coast = (0..<420).map { i in
            let lap = Double(i) / 420
            let angle = lap * .tau
            let r = 330 + signedNoise(loop: lap, radius: 1.6) * 150
                        + signedNoise(loop: lap, radius: 4.4) * 46
            return middle + Vector2(cos(angle) * r, sin(angle) * r * 0.86)
        }
    }

    /// Places scattered on the land, a few of them large.
    func buildPlaces() {
        let middle = Vector2(540, 560)
        _ = middle
        while places.count < 150 {
            let p = Vector2(random(60, 1020), random(120, 1040))
            guard onLand(p) else { continue }
            places.append(Place(at: p, name: name(), big: random() < 0.16))
        }
    }

    /// Even-odd against the coastline: cheap, and good enough for scattering.
    func onLand(_ p: Vector2) -> Bool {
        var inside = false
        var j = coast.count - 1
        for i in 0..<coast.count {
            let a = coast[i], b = coast[j]
            if (a.y > p.y) != (b.y > p.y),
               p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x { inside.toggle() }
            j = i
        }
        return inside
    }

    func name() -> String {
        let parts = Int(random(2, 3.99))
        var out = ""
        for _ in 0..<parts { out += randomChoice(PanAndZoom.syllables) ?? "vik" }
        return out.prefix(1).uppercased() + out.dropFirst()
    }
}
