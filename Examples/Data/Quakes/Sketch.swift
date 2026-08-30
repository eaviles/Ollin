import Ollin

/// A day of earthquakes, redrawn when the list changes.
///
/// `loadTable` and `loadJSON` read a document once. A `DataFeed` reads one
/// address over and over, so what the sketch draws is what is true now rather
/// than what was true when it started. The request runs on a background queue,
/// so `draw()` never waits for the network: before the first answer there is
/// nothing to draw, and the sketch says so instead of going blank.
///
/// The two readings worth copying are `updates` and `problem`. `updates` counts
/// answers that differed from the one before, so the list is rebuilt only when
/// there is news and the fade can start from that moment; a poll that brought
/// back the same day changes nothing on screen. `problem` is how a feed says
/// the network is down without dropping what it already had, which is why the
/// map keeps drawing the last good list underneath the notice.
///
/// The reading is the point rather than the map. Positions are plotted straight
/// from longitude and latitude onto a rectangle, which is the crudest possible
/// projection and stretches everything near the poles.
///
/// Data: the United States Geological Survey's public hourly earthquake feed,
/// read live and not redistributed here.
@main
final class Quakes: Sketch {
    override var canvasSize: CanvasSize { .size(1440, 720) }

    private let feed = DataFeed(
        "https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/2.5_day.geojson",
        every: 60
    )

    private struct Quake {
        var at: Vector2
        var magnitude: Double
        var depth: Double
    }

    private var quakes: [Quake] = []

    /// Which update the list was built from, so a poll that changed nothing
    /// leaves the drawing alone.
    private var built = 0
    private var builtAt = 0.0

    override func setup() {
        feed.start()
    }

    override func draw() {
        background(Color(hex: 0x0B0E13))
        drawGraticule()

        if feed.updateCount != built { rebuild() }

        guard !quakes.isEmpty else {
            if let problem = feed.problem { return drawStatus(problem, style: .warning) }
            return drawStatus("Waiting for the last day of earthquakes…")
        }

        for quake in quakes { draw(quake) }
        drawLegend()
    }

    // MARK: Reading the answer

    private func rebuild() {
        built = feed.updateCount
        builtAt = time
        quakes = feed.json["features"].array.compactMap { feature in
            let place = feature["geometry"]["coordinates"]
            guard let longitude = place[0].number, let latitude = place[1].number else { return nil }
            return Quake(
                at: canvasPoint(longitude: longitude, latitude: latitude),
                magnitude: feature["properties"]["mag"].number ?? 0,
                depth: place[2].number ?? 0
            )
        }
    }

    /// Longitude and latitude straight onto the canvas rectangle.
    private func canvasPoint(longitude: Double, latitude: Double) -> Vector2 {
        Vector2(map(longitude, -180, 180, 0, width),
                map(latitude, 90, -90, 0, height))
    }

    // MARK: Drawing

    private func draw(_ quake: Quake) {
        // The list fades in together, so an arrival reads as an arrival.
        let entrance = min(1, (time - builtAt) * 1.5)
        let radius = map(quake.magnitude, 2.5, 7, 4, 26, clamp: true)
        let deep = map(quake.depth, 0, 300, 0, 1, clamp: true)
        // Shallow reads warm and deep reads cool, mixed through a perceptual
        // space so the middle of the run does not swing off into green.
        let tint = Color.mix(Color(hex: 0xF2A03C), Color(hex: 0x4C7FE0), deep)

        // A ring that keeps widening reads as something still settling.
        let ripple = (time * 0.4 + quake.at.x * 0.002).truncatingRemainder(dividingBy: 1)
        noFill()
        stroke(tint.withAlpha(entrance * (1 - ripple) * 0.5))
        strokeWeight(1.5)
        drawCircle(center: quake.at, radius: radius * (1 + ripple * 1.2))

        noStroke()
        fill(tint.withAlpha(entrance * 0.28))
        drawCircle(center: quake.at, radius: radius)
        fill(tint.withAlpha(entrance))
        drawCircle(center: quake.at, radius: 2.5)
    }

    private func drawGraticule() {
        noFill()
        stroke(Color(white: 1, alpha: 0.04))
        strokeWeight(1)
        for longitude in stride(from: -180.0, through: 180.0, by: 30) {
            let x = map(longitude, -180, 180, 0, width)
            drawLine(x, 0, x, height)
        }
        for latitude in stride(from: -60.0, through: 60.0, by: 30) {
            let y = map(latitude, 90, -90, 0, height)
            drawLine(0, y, width, y)
        }
        stroke(Color(white: 1, alpha: 0.09))
        drawLine(0, height / 2, width, height / 2)
    }

    private func drawLegend() {
        withState {
            noStroke()
            textFont(OutlineFont.systemMedium)
            textSize(16)
            textAlign(.left, .top)
            fill(Color(white: 0.72))
            drawText("\(quakes.count) earthquakes of magnitude 2.5 and up, last 24 hours", 28, 26)

            textSize(13)
            fill(Color(white: 0.42))
            drawText(status(), 28, 50)
        }
    }

    private func status() -> String {
        if let problem = feed.problem { return "the feed is unhappy: \(problem)" }
        guard let since = feed.timeSinceUpdate else { return "waiting" }
        return "read \(Int(since))s ago, checking every \(Int(feed.interval))s"
    }
}
