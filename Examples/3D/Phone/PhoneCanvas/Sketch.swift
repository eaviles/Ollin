import Foundation
import Ollin
import OllinPhone

/// A sketch that runs on the Mac and is played on the phone: draw with a finger
/// and the paint falls the way the phone is tilted.
///
/// Setup: install **Ollin Capture** on an iPhone, launch it, and connect the
/// cable. `device.show(self)` asks the phone for **Sketch** mode, so the phone's
/// screen turns into this canvas by itself. Nothing is built for the phone or
/// installed on it: the Mac draws each frame and sends it down the cable as
/// video. Save the file under the live window and the phone shows the edit in
/// the time the Mac takes to compile it.
///
/// Three inputs arrive from the phone, all through the sketch's own reads. The
/// first finger is the pointer, so `mouseX`, `mouseY`, and `mouseIsPressed` draw
/// here exactly as they would with the sketch installed on the phone, and
/// `pressure` sizes the paint where the glass measures force. Every finger shows
/// as a ring through `device.touches`. The tilt is `device.latestMotion`: gravity
/// in the phone's own frame, laid flat onto the canvas.
@main
final class PhoneCanvas: Sketch {

    let device = PhoneDevice()

    /// A phone held upright: nine across, nineteen and a half down.
    override var canvasSize: CanvasSize { .size(1080, 2340) }

    /// How hard the tilt pulls the paint, in canvas points a second squared at
    /// full tilt.
    @Param(0...5000) var pull = 2400.0

    /// The size of a drop at full pressure, or of every drop on glass that cannot
    /// weigh a press.
    @Param(6...60) var dropSize = 24.0

    /// How much speed a drop keeps when it hits an edge.
    @Param(0...1) var bounce = 0.35

    struct Drop {
        var position: Vector2
        var velocity: Vector2
        var radius: Double
        var color: Color
    }
    var drops: [Drop] = []
    var hue = 0.0

    override func setup() {
        device.show(self)
    }

    override func mousePressed() {
        // Each stroke takes the next color along the wheel.
        hue = (hue + 0.13).truncatingRemainder(dividingBy: 1)
    }

    override func draw() {
        background(Color(hex: 0x0B0D12))

        guard device.isRunning else {
            return drawStatus(device.waitingMessage + "\n\n" +
                              "Open Ollin Capture on an iPhone and connect the cable.\n" +
                              "The phone turns into this canvas by itself.", style: .info)
        }

        if mouseIsPressed {
            let size = pressureIsAvailable ? dropSize * (0.25 + pressure * 0.75) : dropSize
            let jitter = Vector2(random(-3, 3), random(-3, 3))
            drops.append(Drop(position: mouse + jitter, velocity: .zero, radius: size,
                              color: Color(hue: hue, saturation: 0.7, brightness: 1)))
            if drops.count > 1800 { drops.removeFirst(drops.count - 1800) }
        }

        // Gravity in the phone's frame runs x to the right of the screen and y to
        // its top, so it lands on the canvas with y turned over. A phone lying
        // flat has none of it in the plane of the glass, and the paint rests.
        let gravity = device.latestMotion?.gravity ?? Vector3(0, -1, 0)
        let fall = Vector2(gravity.x, -gravity.y) * pull
        let step = min(deltaTime, 1.0 / 30)

        noStroke()
        for index in drops.indices {
            var drop = drops[index]
            drop.velocity = (drop.velocity + fall * step) * 0.995
            drop.position = drop.position + drop.velocity * step
            if drop.position.x < drop.radius || drop.position.x > width - drop.radius {
                drop.position = drop.position.with(x: min(max(drop.position.x, drop.radius),
                                                          width - drop.radius))
                drop.velocity = drop.velocity.with(x: -drop.velocity.x * bounce)
            }
            if drop.position.y < drop.radius || drop.position.y > height - drop.radius {
                drop.position = drop.position.with(y: min(max(drop.position.y, drop.radius),
                                                          height - drop.radius))
                drop.velocity = drop.velocity.with(y: -drop.velocity.y * bounce)
            }
            drops[index] = drop
            fill(drop.color)
            drawCircle(center: drop.position, radius: drop.radius)
        }

        // Every finger on the glass, the pointer's and the rest.
        noFill()
        stroke(Color(hex: 0xF2EBDD).withAlpha(0.8))
        strokeWeight(3)
        for touch in device.touches.down {
            drawCircle(center: touch.point(in: bounds), radius: 70)
        }
    }
}
