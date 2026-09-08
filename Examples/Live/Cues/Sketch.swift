import Foundation
import Ollin

/// Cues: the looks a piece was tuned to, saved and called back. A cue holds
/// every parameter's value at one moment; calling it puts the parameters
/// back there, at once or over a fade. The five in `Sketch.cues.json` beside
/// this file were saved from the inspector's Cues card, and keys **1** to
/// **5** call them from here, **space** the next one, with `fade` seconds to
/// get there. Under the live host the card lists them too, a press calls one,
/// and a new name saves the parameters as they stand. In the performance host
/// a MIDI program change calls a cue by number and `/ollin/cue` by name.
///
/// ```sh
/// swift run OllinLive Examples/Live/Cues/Sketch.swift
/// swift run Example-Live-Cues --export night.png --cue night
/// ```
@main
final class Cues: Sketch {
    @Param("Count", 4 ... 64, icon: "circle.grid.3x3") var count = 12
    @Param("Size", 10 ... 200, icon: "circle") var size = 46.0
    @Param("Hue", 0 ... 1, icon: "paintpalette") var hue = 0.58
    @Param("Spin", -2 ... 2, icon: "arrow.trianglehead.2.clockwise.rotate.90") var spin = 0.25
    @Param("Ground", icon: "rectangle") var ground = Color(red: 0.96, green: 0.95, blue: 0.92)
    @Param("Lit", icon: "sun.max") var lit = false
    @Param("Fade", 0 ... 6, icon: "timer", group: "Cues") var fade = 2.0

    override func setup() {
        // Under a host the sheet beside the file is already installed; on its
        // own the sketch reads the same file from its bundle.
        if cueSheet.cues.isEmpty,
           let path = Bundle.module.path(forResource: "Sketch.cues", ofType: "json") {
            try? loadCues(from: path)
        }
    }

    override func draw() {
        background(ground)
        let c = center
        let ring = min(width, height) * 0.36
        noStroke()
        for i in 0..<count {
            let turn = Double(i) / Double(count)
            let angle = turn * .tau + time * spin
            let breath = 1 + 0.15 * sin(time * 1.3 + turn * .tau * 3)
            let p = c + Vector2(cos(angle), sin(angle)) * ring
            let tone = (hue + turn * 0.18).truncatingRemainder(dividingBy: 1)
            fill(Color(hue: tone, saturation: lit ? 0.9 : 0.55, brightness: lit ? 1 : 0.7, alpha: 0.85))
            drawCircle(center: p, radius: size * breath)
        }
        // The cue in force, small, so a recording shows which look it was.
        if let currentCue {
            fill(lit ? .white : .black)
            textFont(.systemMedium)
            textSize(16)
            drawText(isCueFading ? "→ \(currentCue)" : currentCue, 24, height - 28)
        }
    }

    override func keyPressed() {
        if key == " " {
            nextCue(over: fade)
        } else if let digit = key?.wholeNumberValue, digit >= 1 {
            cue(digit - 1, over: fade)
        }
    }
}
