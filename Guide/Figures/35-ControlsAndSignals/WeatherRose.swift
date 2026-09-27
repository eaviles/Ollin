// figure: frame=0 unstable
//
// Guide payoff (Chapter 35): the weather rose, an instrument for several
// hands. A rose of petals throbs on the network beat and turns once every
// four bars. Its size and how deeply its petals open are parameters bound to
// two MIDI knobs and two OSC faders, with smoothing so a hand glides rather
// than steps. The game controller's left stick moves it, the weather over a
// city blows its trails downwind and picks day or night, and the trackpad
// knocks on every downbeat. With nothing plugged in and nothing on the
// network, it plays as a still rose on a calm afternoon. Unstable because the
// beat runs on the wall clock and the weather is fetched live when the render
// starts, so both read differently on every run.
import Ollin
import OllinController
import OllinHaptics
import OllinLink
import OllinMIDI
import OllinOSC

final class WeatherRose: Sketch {
    @Param(120...460, smoothing: .smoothed) var radius = 320.0
    @Param(0...1, smoothing: .eased(0.3)) var bloom = 0.6
    @Param(3...16) var petals = 7
    @Param var trails = true
    @Param(1...8) var trailCount = 5

    let midi = MIDIInput()
    let osc = OSCReceiver(port: 8000)
    let link = LinkClock(tempo: 96)
    let sky = Weather(in: "Oaxaca")
    var lastBar = -1

    override func setup() {
        try? midi.start()
        try? osc.start()
        link.start()
        sky.start()

        // Three hands on each of the two parameters that matter most: the
        // inspector, a knob, and a fader.
        midi.bind(controlChange: 7, to: $radius)
        midi.bind(controlChange: 8, to: $bloom)
        osc.bind("/radius", to: $radius)
        osc.bind("/bloom", to: $bloom)
        $trailCount.show(when: $trails) { $0 }
    }

    override func draw() {
        // The sky: day or night, and the wind. Until the first reading
        // arrives, a calm afternoon with a light west wind.
        let isDay = sky.isDay ?? true
        let wind = sky.windSpeed ?? 2
        let bearing = (sky.windDirection ?? 270) * .pi / 180
        let downwind = Vector2(-sin(bearing), cos(bearing))
        let ink = isDay ? Color(hex: 0x2B2A33) : Color(hex: 0xF1E6CF)
        background(isDay ? Color(hex: 0xF3EBDD) : Color(hex: 0x10172B))

        // The beat: a throb on every beat, a slow turn every four bars, and a
        // knock under your hand on each downbeat.
        let throb = 1 + 0.1 * link.beat
        let turn = link.progress(over: 16) * .tau / Double(petals)
        if link.bar != lastBar {
            lastBar = link.bar
            playHaptic(.tap(intensity: 0.8, sharpness: 0.6))
        }

        // The left stick moves the rose, and the wind blows its trails.
        let middle = center + controller.leftStick * 180
        if trails {
            noFill()
            strokeWeight(2)
            for k in stride(from: trailCount, through: 1, by: -1) {
                let drift = downwind * (Double(k) * (12 + wind * 6))
                stroke(ink.withAlpha(0.5 / Double(k)))
                drawPolygon(rose(at: middle + drift, radius: radius * throb,
                                 turn: turn - Double(k) * 0.05))
            }
        }
        fill(ink.withAlpha(0.12))
        stroke(ink)
        strokeWeight(3)
        drawPolygon(rose(at: middle, radius: radius * throb, turn: turn))

        // A feed that cannot reach its server says so, and keeps its last reading.
        if let problem = sky.problem {
            noStroke()
            fill(ink)
            textSize(22)
            drawText(problem, 40, height - 40)
        }
    }

    /// A rose with `petals` lobes. `bloom` sets how deep the gaps between them cut.
    func rose(at middle: Vector2, radius: Double, turn: Double) -> [Vector2] {
        (0..<360).map { i in
            let angle = Double(i) / 360 * .tau
            let reach = 1 - bloom * 0.5 * (1 - cos(Double(petals) * (angle - turn)))
            return middle + Vector2(cos(angle), sin(angle)) * (radius * reach)
        }
    }
}
