import Ollin
import OllinHaptics

/// A plate of ridges you drag across, and feel.
///
/// Three strips, each with its own ridges. Drag the pointer sideways through
/// one and every ridge you cross knocks under your finger. The top strip is
/// dull and far apart, the middle one is in between, and the bottom one is
/// crisp and close together, so the three feelings the hardware offers sit
/// side by side and can be compared in one drag. How fast you drag decides how
/// hard each knock lands.
///
/// Hold the space bar for a hum instead of knocks. Move left and right
/// while you hold it: the hum gets stronger toward the right, and on a
/// trackpad you feel that as a faster train of knocks rather than a harder
/// one, because a trackpad has one strength and many rates.
///
/// Drag with the button held. A trackpad actuates only while a finger is
/// pressing it, so a knock asked for during a plain pointer move is delivered
/// to nobody; the plan along the bottom still shows it was asked for.
///
/// The strip along the bottom draws what was last asked of the hardware, so
/// the eye can check what the hand felt. On a machine that cannot be felt at
/// all the sketch says so and keeps drawing.
@main
final class HapticRidgesExample: Sketch {

    @Param(0 ... 1, icon: "speaker.wave.2") var strength = 1.0
    @Param(icon: "waveform.path") var showPlan = true

    /// One band of the plate: where it sits, how far apart its ridges are, and
    /// how crisp they feel.
    private struct Strip {
        let name: String
        let top: Double
        let height: Double
        let spacing: Double
        let sharpness: Double
        let ink: Color
    }

    private var strips: [Strip] = []
    private var crossed: [Int: Double] = [:]   // ridge index -> how fresh it is
    private var lastPlan: [TrackpadKnock] = []
    private var planAge = 0.0
    private var humming = false

    override var canvasSize: CanvasSize { .square(1080) }

    override func setup() {
        let margin = 120.0
        let band = (Double(height) - margin * 2) / 3
        strips = [
            Strip(name: "far apart, dull", top: margin, height: band,
                  spacing: 90, sharpness: 0.1, ink: Color(hex: 0x2A4D69)),
            Strip(name: "even, in between", top: margin + band, height: band,
                  spacing: 54, sharpness: 0.5, ink: Color(hex: 0x4B86B4)),
            Strip(name: "close, crisp", top: margin + band * 2, height: band,
                  spacing: 26, sharpness: 0.95, ink: Color(hex: 0xADCBE3)),
        ]
    }

    override func draw() {
        hapticStrength(strength)
        background(Color(white: 0.92))
        fade()

        drawPlate()
        respondToTheHand()
        drawPointer()
        drawCaptions()
        if showPlan { drawLastPlan() }
    }

    // MARK: What the hand does

    private func respondToTheHand() {
        // Holding the space bar runs one long hum instead of the ridges, so
        // the two ways of asking for touch are next to each other.
        if isKeyDown(" ") {
            if !humming { startHum() }
            return
        }
        if humming { stopHum() }

        guard let strip = strip(under: mouse.y) else { return }
        guard let ridge = ridgeCrossed(in: strip) else { return }

        // A quick hand hits harder, the way a stick dragged along railings
        // does. Speed is measured in canvas points per frame.
        let speed = (mouse - previousMouse).length
        let force = min(1, 0.35 + speed / 40)
        play(.tap(intensity: force, sharpness: strip.sharpness))
        crossed[ridge] = 1
    }

    private func startHum() {
        humming = true
        // Long enough to hold under the finger, and started again below as it
        // runs out, so the strength can follow the hand.
        play(.hum(0.5, intensity: humStrength, sharpness: 0.2, fadeIn: 0.05))
    }

    private func stopHum() {
        humming = false
        stopHaptics()
    }

    /// How strong the hum is, from where the hand is across the canvas.
    private var humStrength: Double {
        min(1, max(0.05, mouse.x / Double(width)))
    }

    /// Which ridge the hand has just crossed, if any.
    ///
    /// The pointer can move a long way between two frames, so this asks which
    /// ridge lies between where it was and where it is, and takes the nearest
    /// one. Firing every ridge in a fast sweep would ask the hardware for more
    /// knocks than it can give, and the plan would drop them anyway.
    private func ridgeCrossed(in strip: Strip) -> Int? {
        let from = min(previousMouse.x, mouse.x)
        let to = max(previousMouse.x, mouse.x)
        guard to > from else { return nil }
        let first = Int((from / strip.spacing).rounded(.up))
        let last = Int((to / strip.spacing).rounded(.down))
        guard first <= last else { return nil }
        return mouse.x >= previousMouse.x ? first : last
    }

    private func strip(under y: Double) -> Strip? {
        strips.first { y >= $0.top && y < $0.top + $0.height }
    }

    /// Play a pattern, and keep a copy of what the hardware was asked for.
    private func play(_ pattern: HapticPattern) {
        playHaptic(pattern)
        lastPlan = TrackpadPlan.knocks(for: pattern, strength: strength)
        planAge = 0
    }

    // MARK: What the eye sees

    /// Ridges dim after they are crossed, so a sweep leaves a trail.
    private func fade() {
        planAge += deltaTime
        for (ridge, level) in crossed {
            let next = level - deltaTime * 2
            if next <= 0 { crossed[ridge] = nil } else { crossed[ridge] = next }
        }
        if humming, planAge > 0.4 {
            // Ask again before the last one runs out, so the strength can
            // follow the hand while it holds.
            play(.hum(0.5, intensity: humStrength, sharpness: 0.2))
        }
    }

    private func drawPlate() {
        for strip in strips {
            noStroke()
            fill(Color(white: 1))
            drawRect(0, strip.top, Double(width), strip.height - 6)

            var ridge = 0
            var x = 0.0
            while x <= Double(width) {
                let fresh = crossed[ridge] ?? 0
                stroke(strip.ink.withAlpha(0.35 + fresh * 0.65))
                strokeWeight(fresh > 0 ? 5 : 2)
                drawLine(x, strip.top + 14, x, strip.top + strip.height - 20)
                x += strip.spacing
                ridge += 1
            }

            noStroke()
            fill(Color(white: 0.45))
            textSize(17)
            drawText(strip.name, 16, strip.top + strip.height - 4)
        }
    }

    private func drawPointer() {
        // Before any hand has arrived, and in an export, the pointer reads as
        // the top left corner. Show it in the middle instead of half off the
        // edge.
        let at = mouse == .zero ? center : mouse
        noFill()
        stroke(humming ? Color(hex: 0xE07A5F) : Color(white: 0.2))
        strokeWeight(humming ? 4 : 2)
        drawCircle(at.x, at.y, humming ? 26 : 18)
        if humming {
            noStroke()
            fill(Color(hex: 0xE07A5F).withAlpha(humStrength))
            drawCircle(at.x, at.y, 12)
        }
    }

    private func drawCaptions() {
        noStroke()
        fill(Color(white: 0.25))
        textSize(21)
        let heading = switch hapticHardware {
        case .engine: "A haptic engine: patterns arrive as written."
        case .trackpad: "A trackpad: three feelings, one strength, so strength becomes rate."
        case .none: hapticsUnavailableReason ?? "Nothing to feel here."
        }
        drawText(heading, 16, 44)
        fill(Color(white: 0.5))
        textSize(17)
        drawText("Drag sideways through a strip with the button held. Hold the space bar for a hum.", 16, 72)
    }

    /// The knocks the hardware was last asked for, laid out in time.
    private func drawLastPlan() {
        guard !lastPlan.isEmpty else { return }
        let span = max(0.4, lastPlan.last!.time + 0.05)
        let base = Double(height) - 54.0
        noStroke()
        fill(Color(white: 0.9))
        drawRect(16, base - 22, Double(width) - 32, 30)

        for knock in lastPlan {
            let x = 24 + (Double(width) - 48) * (knock.time / span)
            let tall = switch knock.feel {
            case .soft: 8.0
            case .level: 14.0
            case .crisp: 20.0
            }
            stroke(Color(hex: 0x2A4D69))
            strokeWeight(2)
            drawLine(x, base + 4, x, base + 4 - tall)
        }

        noStroke()
        fill(Color(white: 0.45))
        textSize(15)
        drawText("asked of the hardware: \(lastPlan.count) knocks over \(String(format: "%.2f", span)) s",
                 16, base + 30)
    }
}
