// figure: frame=0
//
// Guide figure (Chapter 9): two readings drawn by one sky. The left panel is
// a mostly clear afternoon and the right a rainy dusk. Both are built by hand
// as a `Weather.Reading` rather than fetched, so the figure needs no network,
// and the sun in each is placed by `Place.sun(at:)` from the reading's own
// place and moment, which is exactly what a live sketch does with the clock.
import Foundation
import Ollin

final class TheWeatherOutside: Sketch {
    override var canvasSize: CanvasSize { .size(880, 430) }

    let place = Place(latitude: 19.4326, longitude: -99.1332)

    /// A moment on 2026-09-06 in Mexico City, given as the local hour.
    func local(_ hour: Int, _ minute: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: -6 * 3600)!
        return calendar.date(from: DateComponents(year: 2026, month: 9, day: 6, hour: hour, minute: minute))!
    }

    var afternoon: Weather.Reading {
        Weather.Reading(place: place, observedAt: local(15, 0), temperature: 24,
                        humidity: 0.4, cloudCover: 0.25, windSpeed: 3, windDirection: 90,
                        condition: .mostlyClear)
    }

    var dusk: Weather.Reading {
        Weather.Reading(place: place, observedAt: local(18, 35), temperature: 15,
                        humidity: 0.9, cloudCover: 0.95, precipitation: 3,
                        windSpeed: 7, windDirection: 250, condition: .rain)
    }

    let paper = Color(hex: 0xF7F3EA)
    let ink = Color(hex: 0x2A2723)
    let quiet = Color(hex: 0x2A2723).withAlpha(0.55)

    override func draw() {
        background(paper)
        textFont(OutlineFont.system)

        let left = Rectangle(x: 24, y: 24, width: 404, height: 296)
        let right = Rectangle(x: 452, y: 24, width: 404, height: 296)
        drawSky(afternoon, in: left)
        drawSky(dusk, in: right)
        caption("15:00, mostly clear, 24 °C, an east wind at 3 m/s", under: left)
        caption("18:35, rain, 15 °C, a west wind at 7 m/s", under: right)

        withState {
            noStroke()
            fill(quiet)
            textSize(13)
            textAlign(.center, .baseline)
            drawText("The same drawing twice. The reading decides the clouds, the rain, and the light; the clock decides where the sun is.",
                     width / 2, 408)
        }
    }

    func caption(_ text: String, under panel: Rectangle) {
        withState {
            noStroke()
            fill(ink)
            textSize(14)
            textAlign(.left, .baseline)
            drawText(text, panel.x, panel.y + panel.height + 28)
        }
    }

    // MARK: One sky

    /// The horizon, as a fraction of the panel's height.
    let horizon = 0.8

    func drawSky(_ reading: Weather.Reading, in panel: Rectangle) {
        let sun = reading.place.sun(at: reading.observedAt)
        let elevation = sun.elevation
        let day = map(elevation, -12, 10, 0, 1, clamp: true)
        let glow = 1 - min(1, abs(elevation - 1) / 10)

        // Clipped to the panel, so a cloud or a streak that runs past the edge
        // stops at the frame rather than on the paper.
        withClip(panel) { withState {
            translate(panel.x, panel.y)
            let w = panel.width, h = panel.height
            noStroke()

            // The sky: night to day by the sun's height, a warm band near the
            // horizon when the sun is low, and gray by the cloud cover.
            let night = Color(hex: 0x0A1230), dusk = Color(hex: 0xE8874A)
            let dayTop = Color(hex: 0x3E7CC9), dayLow = Color(hex: 0xBBD6EE)
            let gray = Color(hex: 0x8C949E)
            let bands = 72
            for i in 0..<bands {
                let t = Double(i) / Double(bands - 1)
                var color = Color.mix(Color.mix(night, dayTop, day), Color.mix(night, dayLow, day), t * t)
                color = Color.mix(color, dusk, glow * t * t * t * 0.9)
                color = Color.mix(color, Color.mix(gray, night, 1 - day), reading.cloudCover * 0.7 * (0.4 + 0.6 * t))
                fill(color)
                drawRect(0, t * h * horizon, w, h * horizon / Double(bands) + 1)
            }

            // The sun, where the azimuth and elevation put it: east on the
            // left, looking south.
            if elevation > -8 {
                let x = map(sun.azimuth, 60, 300, w * 0.1, w * 0.9)
                let y = h * horizon - elevation / 90 * h * 0.62
                let low = map(elevation, -2, 15, 1, 0, clamp: true)
                let color = Color.mix(Color(hex: 0xFFF4D6), Color(hex: 0xFF9A4A), low)
                for ring in stride(from: 8, through: 1, by: -1) {
                    fill(color.withAlpha(0.02 * Double(9 - ring)))
                    drawCircle(x, y, 20 + Double(ring) * 7)
                }
                fill(color)
                drawCircle(x, y, 18)
            }

            // Clouds, as many as the cover says, spread by two different
            // irrational steps so the two axes do not line up.
            let cloudColor = Color.mix(Color(hex: 0x2A3350), Color(hex: 0xF4F6FA), day)
            let count = Int(20 * reading.cloudCover)
            for i in 0..<count {
                let u = (Double(i) * 0.618034).truncatingRemainder(dividingBy: 1)
                let v = (Double(i) * 0.414214).truncatingRemainder(dividingBy: 1)
                let cx = 40 + u * (w - 80)
                let cy = 34 + v * v * h * 0.4
                let size = 14 + (1 - v) * 22
                for p in 0..<5 {
                    let a = Double(p) * 1.257 + Double(i)
                    let r = size * (0.55 + 0.45 * (0.5 + 0.5 * sin(a * 2.3)))
                    fill(cloudColor.withAlpha(0.85))
                    drawCircle(cx + cos(a) * 0.9 * size, cy + (sin(a) * 0.35 - 0.1) * size, r)
                }
            }

            // Rain, leaning the way the wind carries it.
            if reading.condition.isPrecipitating {
                let toward = (reading.windDirection + 180) * .pi / 180
                let lean = -sin(toward) * min(1, reading.windSpeed / 12) * 0.35
                let streaks = Int(map(reading.precipitation, 0, 6, 40, 260, clamp: true))
                stroke(Color(white: 0.9).withAlpha(0.35))
                strokeWeight(1)
                let length = 12 + reading.windSpeed
                for i in 0..<streaks {
                    let seed = Double(i) * 0.618034
                    let phase = (seed * 3.7) - floor(seed * 3.7)
                    let x = 6 + ((seed * 7.3) - floor(seed * 7.3)) * (w - 12 - abs(lean) * length)
                    let y = phase * (h * horizon - length)
                    drawLine(x, y, x + lean * length, y + length)
                }
                noStroke()
            }

            // The ground and a low line of roofs.
            fill(Color.mix(Color(hex: 0x070A16), Color(hex: 0x3B4A3A), day))
            drawRect(0, h * horizon, w, h * (1 - horizon))
            fill(Color.mix(Color(hex: 0x05070F), Color(hex: 0x2A3630), day))
            var x = 0.0
            var i = 0
            while x < w {
                let roof = min(18 + Double((i * 37) % 30), w - x)
                let tall = 6 + Double((i * 53) % 22)
                drawRect(x, h * horizon - tall, roof, tall)
                x += roof + 3
                i += 1
            }
        } }
    }
}
