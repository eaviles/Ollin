import Foundation
import Ollin
import OllinPhone

/// What a tethered iPhone hears, named: every sound its classifier notices in
/// the room rings out on the canvas as it starts, and the levels of a few
/// familiar ones run along the bottom.
///
/// Setup: install **Ollin Capture** on an iPhone, launch it, tap **Hear** (the
/// switch under the modes; the phone asks for its microphone once), and
/// connect the cable. Any mode can be running beside it. The connection
/// retries on its own, so tapping Hear or plugging in after this sketch is
/// already running just begins the feed.
///
/// A ring is an *event*: a label crossing the threshold from below, so a sound
/// that keeps going rings once and a sound that returns rings again. Each
/// label always rings in its own place, found by hashing its name, so a room
/// with a dog and a kettle settles into a map of its sounds. The bars are
/// *levels*: how sure the phone is right now, whatever the threshold. The
/// threshold itself is a parameter, so the inspector can make the phone more
/// or less credulous while it listens.
@main
final class PhoneSounds: Sketch {

    let device = PhoneDevice()

    /// The confidence a sound must reach before it rings.
    @Param(0...1) var threshold = 0.6

    /// A few everyday sounds whose levels are always shown, whether or not
    /// they ring; the built-in vocabulary spells them this way.
    let watched = ["speech", "music", "clapping", "dog_bark", "knock", "laughter"]

    struct Ring {
        var label: String
        var center: Vector2
        var born: Double
        var strength: Double
    }
    var rings: [Ring] = []

    let ink = Color(hex: 0xF2EBDD)
    let warm = Color(hex: 0xFFB84D)
    let cool = Color(hex: 0x7FE0D4)

    override func setup() {
        device.start()
    }

    override func draw() {
        background(Color(hex: 0x0D1017))
        device.sounds.threshold = threshold

        guard device.isRunning else {
            return drawStatus(device.waitingMessage + "\n\n" +
                              "Open Ollin Capture on an iPhone, tap Hear, and\n" +
                              "connect the cable.", style: .info)
        }
        guard device.sounds.isListening else {
            return drawStatus("Connected. Tap Hear on the phone, and allow the\n" +
                              "microphone when it asks.", style: .info)
        }

        // Every sound that just started becomes a ring in its own place.
        for event in device.sounds.events() {
            rings.append(Ring(label: event.label, center: place(for: event.label),
                              born: time, strength: event.confidence))
        }
        rings.removeAll { time - $0.born > 4 }

        drawRings()
        drawStrongest()
        drawLevels()
        drawCaption("PhoneSounds: \(device.sounds.readingCount) readings · threshold \(String(format: "%.2f", threshold))")
    }

    /// Where a label rings: a point hashed from its name, kept off the edges
    /// and out of the bands the text uses, so the same sound always lands in
    /// the same spot.
    private func place(for label: String) -> Vector2 {
        var h: UInt64 = 1469598103934665603
        for byte in label.utf8 { h = (h ^ UInt64(byte)) &* 1099511628211 }
        let u = Double(h & 0xFFFF) / 65535
        let v = Double((h >> 16) & 0xFFFF) / 65535
        return Vector2(width * (0.15 + 0.7 * u), height * (0.18 + 0.56 * v))
    }

    private func drawRings() {
        withState {
            noFill()
            textFont(OutlineFont.system)
            textAlign(.center)
            for ring in rings {
                let age = time - ring.born
                let fade = max(0, 1 - age / 4)
                let radius = 30 + age * 90 * (0.5 + ring.strength)
                stroke(warm.withAlpha(fade * 0.9))
                strokeWeight(1.5 + 4 * ring.strength * fade)
                drawCircle(center: ring.center, radius: radius)
                fill(ink.withAlpha(fade))
                noStroke()
                textSize(22)
                drawText(ring.label.replacingOccurrences(of: "_", with: " "),
                         at: ring.center + Vector2(0, 8))
                noFill()
            }
        }
    }

    /// The single strongest label right now, whatever the threshold, with how
    /// sure the phone is.
    private func drawStrongest() {
        guard let top = device.sounds.topClassification else { return }
        withState {
            noStroke()
            textFont(OutlineFont.system)
            textAlign(.center)
            fill(ink.withAlpha(0.5))
            textSize(18)
            drawText("hearing", at: Vector2(width * 0.5, 64))
            fill(top.confidence >= threshold ? warm : ink.withAlpha(0.8))
            textSize(44)
            drawText(top.label.replacingOccurrences(of: "_", with: " "),
                     at: Vector2(width * 0.5, 112))
            fill(ink.withAlpha(0.5))
            textSize(18)
            drawText(String(format: "%.0f%%", top.confidence * 100), at: Vector2(width * 0.5, 146))
        }
    }

    /// The watched sounds as bars along the bottom: the level is the height,
    /// the threshold a line across, and a bar that crossed recently glows.
    private func drawLevels() {
        withState {
            textFont(OutlineFont.system)
            textAlign(.center)
            let count = Double(watched.count)
            let slot = (width - 120) / count
            let base = height - 110.0, tall = 140.0
            for (i, label) in watched.enumerated() {
                let x = 60 + slot * (Double(i) + 0.5)
                let level = device.sounds.confidence(of: label)
                let recent = max(0, 1 - device.sounds.timeSinceHearing(label) / 1.5)
                noStroke()
                fill(ink.withAlpha(0.08))
                drawRect(center: Vector2(x, base - tall * 0.5), width: slot * 0.5, height: tall)
                fill(recent > 0 ? warm.withAlpha(0.5 + 0.5 * recent) : cool.withAlpha(0.75))
                drawRect(center: Vector2(x, base - tall * level * 0.5),
                         width: slot * 0.5, height: tall * level)
                stroke(ink.withAlpha(0.5))
                strokeWeight(1)
                drawLine(x - slot * 0.3, base - tall * threshold, x + slot * 0.3, base - tall * threshold)
                noStroke()
                fill(ink.withAlpha(0.7))
                textSize(17)
                drawText(label.replacingOccurrences(of: "_", with: " "), at: Vector2(x, base + 26))
            }
        }
    }
}
