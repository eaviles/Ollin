import Foundation
import Ollin
import OllinAudio

/// Five ways to drive a sound past where it fits.
///
/// A distortion is arithmetic on the samples as they pass, and each character
/// is a different piece of it. A soft clip rounds the peaks and an overdrive
/// flattens them, one side first. A bit crush rounds the level to a staircase
/// and holds each step. A ring multiplies the sound by a sine, and a squeeze
/// lets one band through and flattens it.
///
/// The dim line is a tone going in and the bright one is that tone coming
/// out, ten milliseconds of each, worked out here with the same arithmetic the
/// effect runs. The drive sweeps up and down by itself, so what more of it
/// means for each one can be watched and heard; switch the sweep off to set
/// the drive by hand.
@main
final class Drive: Sketch {

    enum Kind: String, ParamOption {
        case softClip, overdrive, bitCrush, ring, squeeze

        var character: Distortion.Character {
            switch self {
            case .softClip:  return .softClip
            case .overdrive: return .overdrive
            case .bitCrush:  return .bitCrush
            case .ring:      return .ring
            case .squeeze:   return .squeeze
            }
        }

        var says: String {
            switch self {
            case .softClip:  return "A soft clip rounds the peaks, the same above and below."
            case .overdrive: return "An overdrive flattens the peaks, one side before the other."
            case .bitCrush:  return "A bit crush rounds the level to steps and holds each one."
            case .ring:      return "A ring multiplies the sound by a sine at 300 Hz."
            case .squeeze:   return "A squeeze lets a band at 1,200 Hz through and flattens it."
            }
        }
    }

    @Param(icon: "waveform.path", group: "The distortion") var kind = Kind.softClip
    @Param(-24 ... 20, icon: "dial.high", group: "The distortion") var drive = -6.0
    @Param(icon: "arrow.up.and.down", group: "The distortion") var sweeps = true
    @Param(0 ... 1, icon: "slider.horizontal.3", group: "The distortion") var mix = 1.0

    let synth = Synth(.stab, polyphony: 6)
    let pentatonic = Scale(.minorPentatonic, root: "C3")
    let tempo: Tempo = 96
    var counter = StepCounter(perBeat: 2)
    var built = ""

    override func setup() {
        synth.gain = 0.5
        rebuild()
    }

    /// The drive in use: the parameter, or a slow sweep either side of the
    /// default, in steps of half a decibel so the chain is not rewritten on
    /// every frame.
    private var driven: Double {
        guard sweeps else { return drive }
        return ((-6 + 16 * sin(time * 0.9)) * 2).rounded() / 2
    }

    private var recipe: String { "\(kind)-\(driven)-\(mix)" }

    private func rebuild() {
        synth.effects = [
            .distortion(Distortion(kind.character, drive: driven, mix: mix)),
            .limiter(Limiter()),
        ]
        built = recipe
    }

    override func draw() {
        background(Color(hex: 0x0A0C11))
        if built != recipe { rebuild() }

        for next in counter.steps(upTo: tempo.beats(at: time)) {
            synth.play(pentatonic[[0, 3, 2, 4, 1, 5][next % 6]], velocity: 0.8, for: 0.45)
        }

        drawWaves()
        drawCaption(kind.says, edge: .top)
        drawCaption("The dim line goes in and the bright one comes out. Drive: \(driven >= 0 ? "+" : "")\(String(format: "%.1f", driven)) dB.")
    }

    // MARK: The arithmetic, for the picture

    /// The gain the drive stands for: 1 at the default of -6 dB, doubling
    /// every six decibels.
    private var push: Double { pow(10, (driven + 6) / 20) }

    private func soft(_ x: Double, _ gain: Double) -> Double { tanh(gain * x) / tanh(gain) }

    /// A straight run, a parabola that turns it over, and a flat top.
    private func hard(_ u: Double) -> Double {
        let size = abs(u)
        let shaped = size < 1.0 / 3 ? 2 * size : size < 2.0 / 3 ? (3 - (2 - 3 * size) * (2 - 3 * size)) / 3 : 1
        return u < 0 ? -shaped : shaped
    }

    /// Ten milliseconds of a tone at `level`, and the same tone driven.
    private func waves(level: Double) -> (plain: [Double], driven: [Double]) {
        let rate = 44100.0
        let count = 441
        let hz = kind == .squeeze ? 1200.0 : 220.0
        let plain = (0..<count).map { level * sin(2 * .pi * hz * Double($0) / rate) }
        var driven = [Double](repeating: 0, count: count)
        switch kind {
        case .softClip:
            driven = plain.map { soft($0, 2 * push) }
        case .overdrive:
            let gain = 4 * push, bias = 0.12
            let reach = hard(bias) - hard(bias - gain / 3)
            let shaped = plain.map { (hard(gain * $0 / 3 + bias) - hard(bias)) / reach }
            // The effect takes the standing level out; so does the picture.
            let mean = shaped.reduce(0, +) / Double(count)
            driven = shaped.map { $0 - mean }
        case .bitCrush:
            let step = push / 32
            let hold = max(1, Int((rate / (11025 / push.squareRoot())).rounded()))
            var held = 0.0
            for index in 0..<count {
                if index % hold == 0 { held = step * (plain[index] / step).rounded() }
                driven[index] = held
            }
        case .ring:
            for index in 0..<count {
                driven[index] = min(max(push * plain[index], -1), 1) * sin(2 * .pi * 300 * Double(index) / rate)
            }
        case .squeeze:
            // A tone in the middle of the band passes it, so what is left to
            // see is the flattening.
            driven = plain.map { soft($0, 4 * push) }
        }
        return (plain, driven.indices.map { plain[$0] * (1 - mix) + driven[$0] * mix })
    }

    private func drawWaves() {
        let frame = Rectangle(x: width * 0.1, y: height * 0.26, width: width * 0.8, height: height * 0.48)
        let (plain, driven) = waves(level: 0.8)

        func plotted(_ values: [Double]) -> [Vector2] {
            values.enumerated().map { position, value in
                Vector2(frame.x + frame.width * Double(position) / Double(values.count - 1),
                        frame.y + frame.height * (0.5 - value * 0.42))
            }
        }

        noFill()
        stroke(Color(hex: 0x6FA8DC, alpha: 0.18))
        strokeWeight(1 * scale)
        for line in [-1.0, 0, 1] {
            let y = frame.y + frame.height * (0.5 - line * 0.42)
            drawLine(frame.x, y, frame.x + frame.width, y)
        }

        stroke(Color(hex: 0x6FA8DC, alpha: 0.35))
        strokeWeight(2 * scale)
        drawPolyline(plotted(plain))

        stroke(Color(hex: 0xE8A33D, alpha: 0.95))
        strokeWeight(3 * scale)
        drawPolyline(plotted(driven))
    }
}
