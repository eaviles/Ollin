import Foundation
import Ollin

/// The sky outside, drawn from the weather over one city.
///
/// A `Weather` is a `DataFeed` that already knows the address to ask and the
/// shape of the answer, so the sketch reads `cloudCover`, `windSpeed`, and
/// `condition` the way it would read a slider. The city is looked up by name
/// when the weather starts, and the reading carries the place it turned out
/// to be.
///
/// The picture is a view of the southern sky: east on the left, west on the
/// right. The sun is not fetched at all. `Place.sun(at:)` works out where it is
/// from the place and the clock, so the sky is the right color for the hour
/// before the first reading arrives, and the clouds, the rain, and the wind
/// join once it does. Nothing is drawn that is not known: until the reading is
/// in, the caption says the sketch is still asking.
///
/// Data: current conditions from Open-Meteo (CC BY 4.0), read live and not
/// redistributed here.
@main
final class Outside: Sketch {
    override var canvasSize: CanvasSize { .size(1440, 720) }

    private let weather = Weather(in: "Mexico City")

    /// A cloud is a few soft discs around one point, drifting with the wind.
    private struct Cloud {
        var x: Double
        var y: Double
        var size: Double
        var puffs: [(dx: Double, dy: Double, r: Double)]
    }
    private var clouds: [Cloud] = []
    private var drift = 0.0

    /// Where the horizon sits, as a fraction of the height.
    private let horizon = 0.78

    override func setup() {
        weather.start()
        // The cloud shapes are laid out once, spread by two different
        // irrational steps so no two land together and the two axes do not
        // line up, and only how many show depends on the sky.
        clouds = (0..<40).map { i in
            let u = (Double(i) * 0.618034).truncatingRemainder(dividingBy: 1)
            let v = (Double(i) * 0.414214).truncatingRemainder(dividingBy: 1)
            return Cloud(
                x: u * width,
                y: 60 + v * v * height * 0.5,
                size: 26 + (1 - v) * 44,
                puffs: (0..<5).map { p in
                    let a = Double(p) * 1.257 + Double(i)
                    return (cos(a) * 0.9, sin(a) * 0.35 - 0.1, 0.55 + 0.45 * (0.5 + 0.5 * sin(a * 2.3)))
                }
            )
        }
    }

    override func draw() {
        let reading = weather.reading
        let place = reading?.place
        let sun = place?.sun(at: Date())
        let elevation = sun?.elevation ?? 30

        drawSky(elevation: elevation, clouds: reading?.cloudCover ?? 0.5)
        if let sun, let place { drawSun(sun, at: place) }
        if let reading { drawWeather(reading, elevation: elevation) }
        drawGround(elevation: elevation)
        drawCaption(reading)
    }

    // MARK: The sky

    /// The sky's color runs with the sun's height: deep blue at night, a warm
    /// band at the horizon around sunrise and sunset, blue by day. Cloud
    /// flattens all of it toward gray.
    private func drawSky(elevation: Double, clouds: Double) {
        let night = Color(hex: 0x0A1230)
        let dusk = Color(hex: 0xE8874A)
        let dayTop = Color(hex: 0x3E7CC9)
        let dayHorizon = Color(hex: 0xBBD6EE)
        let gray = Color(hex: 0x8C949E)

        // How far into day we are, and how close to the horizon the sun sits.
        let day = map(elevation, -12, 10, 0, 1, clamp: true)
        let glow = 1 - min(1, abs(elevation - 1) / 10)

        noStroke()
        let bands = 120
        for i in 0..<bands {
            let t = Double(i) / Double(bands - 1)          // 0 at the top
            let top = Color.mix(night, dayTop, day)
            let low = Color.mix(night, dayHorizon, day)
            var color = Color.mix(top, low, t * t)
            color = Color.mix(color, dusk, glow * t * t * t * 0.9)
            color = Color.mix(color, Color.mix(gray, night, 1 - day), clouds * 0.7 * (0.4 + 0.6 * t))
            fill(color)
            let y = t * height * horizon
            drawRect(0, y, width, height * horizon / Double(bands) + 1)
        }
    }

    /// East on the left, west on the right, the horizon where the ground starts.
    private func skyPoint(azimuth: Double, elevation: Double) -> Vector2 {
        let x = map(azimuth, 60, 300, 0, width)
        let y = height * horizon - elevation / 90 * height * 0.72
        return Vector2(x, y)
    }

    private func drawSun(_ sun: SunPosition, at place: Place) {
        guard sun.elevation > -8 else { return }
        let at = skyPoint(azimuth: sun.azimuth, elevation: sun.elevation)
        let low = map(sun.elevation, -2, 15, 1, 0, clamp: true)
        let color = Color.mix(Color(hex: 0xFFF4D6), Color(hex: 0xFF9A4A), low)
        noStroke()
        for ring in stride(from: 12, through: 1, by: -1) {
            fill(color.withAlpha(0.018 * Double(13 - ring)))
            drawCircle(center: at, radius: 40 + Double(ring) * 11)
        }
        fill(color)
        drawCircle(center: at, radius: 36)
    }

    // MARK: The weather

    private func drawWeather(_ reading: Weather.Reading, elevation: Double) {
        let day = map(elevation, -12, 10, 0, 1, clamp: true)

        // Wind. The direction is where it blows from, and east is on the
        // left, so a west wind carries the clouds leftward across this view.
        let toward = (reading.windDirection + 180) * .pi / 180
        drift += -sin(toward) * reading.windSpeed * 0.06
        let sway = sin(time * 0.7) * reading.windSpeed * 0.4

        // Clouds: how many show, and how gray they are, follow the cover.
        let showing = Int(Double(clouds.count) * reading.cloudCover)
        let cloudColor = Color.mix(Color(hex: 0x2A3350), Color(hex: 0xF4F6FA), day)
        noStroke()
        for cloud in clouds.prefix(showing) {
            let x = (cloud.x + drift + sway * (cloud.size / 110)).truncatingRemainder(dividingBy: width + 240)
            let cx = x < -120 ? x + width + 240 : x
            for puff in cloud.puffs {
                let r = cloud.size * puff.r
                fill(cloudColor.withAlpha(0.06))
                drawCircle(cx + puff.dx * cloud.size + 6, cloud.y + puff.dy * cloud.size + 6, r * 1.25)
                fill(cloudColor.withAlpha(0.85))
                drawCircle(cx + puff.dx * cloud.size, cloud.y + puff.dy * cloud.size, r)
            }
        }

        // Fog is a veil over everything below the clouds.
        if reading.condition == .fog {
            fill(Color(white: 0.82).withAlpha(0.55 * (0.4 + 0.6 * day)))
            drawRect(0, height * 0.3, width, height * (horizon - 0.3))
        }

        // Rain and snow fall from the cloud line, leaning with the wind.
        guard reading.condition.isPrecipitating || reading.precipitation > 0 else { return }
        let lean = -sin(toward) * min(1, reading.windSpeed / 12) * 0.35
        if reading.condition.isSnowing {
            let flakes = Int(map(reading.snowfall, 0, 20, 60, 400, clamp: true))
            fill(Color(white: 1).withAlpha(0.8))
            for i in 0..<flakes {
                let seed = Double(i) * 0.618034
                let phase = (time * (0.05 + (seed - floor(seed)) * 0.06) + seed).truncatingRemainder(dividingBy: 1)
                let x = ((seed * 7.3) - floor(seed * 7.3)) * width + sin(time + Double(i)) * 14 + phase * lean * 300
                let y = phase * height * horizon
                drawCircle(x, y, 2 + (seed - floor(seed)) * 2.5)
            }
        } else {
            let streaks = Int(map(reading.precipitation, 0, 6, 80, 700, clamp: true))
            stroke(Color(white: 0.9).withAlpha(0.35))
            strokeWeight(1.2)
            let length = 22 + reading.windSpeed * 1.5
            for i in 0..<streaks {
                let seed = Double(i) * 0.618034
                let phase = (time * (0.8 + (seed - floor(seed)) * 0.5) + seed).truncatingRemainder(dividingBy: 1)
                let x = ((seed * 7.3) - floor(seed * 7.3)) * width + phase * lean * 400
                let y = phase * height * horizon
                drawLine(x, y, x + lean * length, y + length)
            }
        }
    }

    // MARK: The ground and the caption

    private func drawGround(elevation: Double) {
        let day = map(elevation, -12, 10, 0, 1, clamp: true)
        noStroke()
        fill(Color.mix(Color(hex: 0x070A16), Color(hex: 0x3B4A3A), day))
        drawRect(0, height * horizon, width, height * (1 - horizon))
        // A low line of roofs, so the horizon reads as a city and not an edge.
        fill(Color.mix(Color(hex: 0x05070F), Color(hex: 0x2A3630), day))
        var x = 0.0
        var i = 0
        while x < width {
            let w = 30 + Double((i * 37) % 70)
            let h = 10 + Double((i * 53) % 46)
            drawRect(x, height * horizon - h, w, h)
            x += w + 4
            i += 1
        }
    }

    private func drawCaption(_ reading: Weather.Reading?) {
        withState {
            noStroke()
            textFont(OutlineFont.systemMedium)
            textAlign(.left, .top)
            textSize(17)
            fill(Color(white: 1).withAlpha(0.85))
            if let reading {
                drawText(headline(reading), 28, 26)
                textSize(13)
                fill(Color(white: 1).withAlpha(0.5))
                drawText(status(), 28, 52)
            } else if let problem = weather.problem {
                drawText("Mexico City", 28, 26)
                textSize(13)
                fill(Color(red: 1, green: 0.55, blue: 0.45))
                drawText("the weather is unhappy: \(problem)", 28, 52)
            } else {
                drawText("Mexico City", 28, 26)
                textSize(13)
                fill(Color(white: 1).withAlpha(0.5))
                drawText("looking up the city, then asking for the sky over it…", 28, 52)
            }
        }
    }

    private func headline(_ reading: Weather.Reading) -> String {
        let degrees = String(format: "%.0f", reading.temperature)
        let wind = String(format: "%.0f", reading.windSpeed)
        let clouds = String(format: "%.0f", reading.cloudCover * 100)
        return "\(reading.name ?? "Mexico City") · \(degrees) °C, \(reading.condition) · wind \(wind) m/s from the \(compass(reading.windDirection)) · clouds \(clouds)%"
    }

    private func status() -> String {
        if let problem = weather.problem { return "the weather is unhappy: \(problem)" }
        guard let since = weather.timeSinceUpdate else { return "waiting" }
        return "read \(Int(since))s ago, checking every \(Int(weather.interval / 60)) min"
    }

    /// A heading in degrees as the point of the compass it is nearest.
    private func compass(_ degrees: Double) -> String {
        let points = ["north", "northeast", "east", "southeast", "south", "southwest", "west", "northwest"]
        let index = Int((degrees / 45).rounded()) % 8
        return points[(index + 8) % 8]
    }
}
