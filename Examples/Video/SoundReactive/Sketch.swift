import Foundation
import Ollin
import OllinAudio
import OllinVideo

/// The video's own soundtrack drives the visuals: a `Soundtrack` taps the
/// playing clip's audio and runs the full analyzer surface over it, so the
/// spectrum bars and the beat ring react to the sound of the footage they sit
/// on. The bundled clip pairs two Wikimedia Commons works (both CC BY-SA 4.0,
/// full provenance in THIRD-PARTY-NOTICES.md): footage from *Voladores de
/// Papantla México* by José Millán (Jmillan325), 2018
/// (https://commons.wikimedia.org/wiki/File:Voladores_de_Papantla_México.webm)
/// with, as its soundtrack, *El Fandanguito* performed on violin by Cynthia
/// Molina, recorded by Emropa and ClawisJM
/// (https://commons.wikimedia.org/wiki/File:Violín_SonHuasteco_ELFandanguito.ogg).
///
/// The tap hears the soundtrack itself, before volume shaping, so turning
/// `volume` down (even to zero) quiets the room without stilling the
/// visuals. (A hard `isMuted` is the exception: it stops audio processing
/// altogether, and the analysis with it.)
@main
final class SoundReactive: Sketch {
    var player: VideoPlayer?
    var sound: Soundtrack?

    override func setup() {
        noStroke()
        guard let player = try? VideoPlayer(
            resource: "voladores-fandanguito", withExtension: "mp4", in: .module) else { return }
        player.loops = true
        sound = Soundtrack(of: player)
        player.play()
        self.player = player
    }

    override func draw() {
        background(Color(white: 0.06))
        guard let player, let sound else { return }

        drawFrame(player)

        // What the soundtrack is doing, drawn over the footage: log-spaced
        // bands as bars rising from the bottom edge...
        let bands = sound.bands(48)
        let barWidth = width / Double(bands.count)
        fill(Color(hex: 0xFFB703, alpha: 0.8))
        for (i, level) in bands.enumerated() {
            let barHeight = Double(level) * 260 * scale
            drawRect(Double(i) * barWidth + barWidth * 0.15, height - barHeight,
                     barWidth * 0.7, barHeight)
        }

        // ...and a ring that kicks on every beat and rings down.
        let pulse = Double(sound.beat)
        noFill()
        stroke(Color(hex: 0x8ECAE6, alpha: 0.35 + pulse * 0.65))
        strokeWeight((3 + pulse * 14) * scale)
        drawCircle(width - 110 * scale, 110 * scale, (46 + pulse * 26) * scale)
        noStroke()

        drawCaption("Voladores · José Millán / El Fandanguito · Cynthia Molina (CC BY-SA)", edge: .top)
    }
}
