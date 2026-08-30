import Foundation
import simd
import Ollin
import OllinPhone

/// A sketch you reach into with the phone. The capture app tracks the phone's own
/// place in the room and sends it as a pointer, so the beam out of the back of the
/// phone lands on a ball, a press picks it up, and sliding the thumb pushes it
/// away or pulls it in. Let go and it drops where it is.
///
/// The picture is a third-person view on purpose: you see the phone as a small
/// slab with a beam coming out of it, which is the only way to watch yourself
/// point.
///
/// Setup: build + run the Ollin capture app (Apps/OllinPhoneApp) on the iPhone,
/// connect the cable, and choose **Wand**. Stand where you started the mode, since
/// the room's origin is the phone's own starting place, and the balls are laid out
/// in front of it.
@main
final class PhonePointer: Sketch {

    let device = PhoneDevice()

    /// How far the beam runs when it lands on nothing, in meters.
    @Param(0.5...8) var reach = 3.0

    /// How big each ball is, in meters.
    @Param(0.05...0.3) var ballSize = 0.13

    /// How fast a held ball travels along the beam at full thumb, meters a second.
    @Param(0...2) var pushSpeed = 0.8

    /// Where the view stands, as a turn around the room.
    @Param(-.pi ... .pi) var viewAngle = 0.9

    /// The balls, in the room's own meters.
    var balls: [Vector3] = []

    /// Which ball is being carried, and how far out along the beam it rides.
    var held: Int?
    var holdDistance = 1.0

    /// The press count as of the last frame, so a press that came and went between
    /// two draws is still seen.
    var lastPressCount = 0

    let colors = [Color(hex: 0xFF6B6B), Color(hex: 0xFFD93D), Color(hex: 0x6BCB77),
                  Color(hex: 0x4D96FF), Color(hex: 0xB980F0), Color(hex: 0xFF9F45),
                  Color(hex: 0x00C2CB), Color(hex: 0xF67280), Color(hex: 0xC0E218)]

    let beamColor = Color(hex: 0x7FE7DC)
    let phoneColor = Color(hex: 0xE8E8EF)

    override func setup() {
        device.start()
        // An arc standing in front of where the phone starts, at three heights, so
        // aiming asks for a turn of the wrist as well as a turn of the body.
        balls = (0..<9).map { i in
            let across = (Double(i % 3) - 1) * 0.85
            let level = (Double(i / 3) - 1) * 0.55
            return Vector3(across, level, -1.5 - Double(i % 3) * 0.25)
        }
    }

    override func draw() {
        background(Color(white: 0.05))

        guard let wand = device.latestWand else { return drawWaiting() }

        camera(view())
        environment(.studio.intensified(to: 0.9))
        material(.clay)

        carry(with: wand)
        drawRoom()
        drawBalls(pointedAt: aim(of: wand))
        drawWand(wand)
        drawCaption(caption(for: wand))
    }

    // MARK: Pointing, picking, carrying

    /// Which ball the beam lands on, and how far away it is. Nothing while a ball
    /// is being carried, since the beam is then busy holding it.
    private func aim(of wand: PhoneWand) -> (index: Int, distance: Double)? {
        guard wand.isTracked, held == nil else { return nil }
        var best: (index: Int, distance: Double)?
        for (i, ball) in balls.enumerated() {
            guard let distance = wand.ray.hit(sphereAt: ball, radius: ballSize) else { continue }
            if best == nil || distance < best!.distance { best = (i, distance) }
        }
        return best
    }

    /// The whole gesture: a press takes what the beam is on, a held press carries
    /// it and the thumb pushes it, and letting go drops it.
    private func carry(with wand: PhoneWand) {
        // The count says a press happened, which survives a press that landed and
        // left inside one frame. Reading `isPressed` alone would miss that.
        if wand.pressCount > lastPressCount, held == nil, let target = aim(of: wand) {
            held = target.index
            holdDistance = target.distance
        }
        lastPressCount = wand.pressCount

        guard let index = held else { return }
        guard wand.isPressed else {
            held = nil                       // the finger left: the ball stays where it is
            return
        }

        // The thumb rides up and down the pad as a rate, not a place, so a small
        // pad reaches the whole room and letting go leaves the ball where it is.
        if let touch = wand.touch {
            holdDistance += touch.y * pushSpeed * deltaTime
            holdDistance = min(max(holdDistance, ballSize * 2), 8)
        }
        balls[index] = wand.point(at: holdDistance)
    }

    // MARK: The room

    private func drawBalls(pointedAt aim: (index: Int, distance: Double)?) {
        for (i, ball) in balls.enumerated() {
            let lit = i == held || i == aim?.index
            withState {
                translate(ball)
                let color = colors[i % colors.count]
                fill(lit ? color.mixed(with: .white, 0.35) : color)
                drawSphere(radius: ballSize * (lit ? 1.12 : 1))
            }
            // A mark under each ball, so the eye can tell a ball that moved toward
            // the camera from one that only grew.
            withState {
                translate(ball.x, -1.19, ball.z)
                fill(Color(white: 0.16))
                drawCylinder(radius: ballSize * 0.9, height: 0.004)
            }
        }
    }

    private func drawRoom() {
        withState {
            translate(0, -1.2, -1)
            fill(Color(white: 0.11))
            drawBox(width: 8, height: 0.02, depth: 8)
        }
    }

    /// The phone as a small slab, with the beam out of the back of it. The slab is
    /// drawn through `placement`, so it leans the way the real one leans.
    private func drawWand(_ wand: PhoneWand) {
        let landing = held.map { balls[$0] }
            ?? aim(of: wand).map { wand.point(at: $0.distance) }
            ?? wand.point(at: reach)
        withState {
            fill(beamColor.withAlpha(wand.isPressed ? 0.95 : 0.5))
            drawTube([wand.position, landing], radius: wand.isPressed ? 0.008 : 0.004, sides: 6)
        }
        withState {
            transform(wand.placement)
            fill(wand.isTracked ? phoneColor : phoneColor.withAlpha(0.35))
            drawBox(width: 0.071, height: 0.146, depth: 0.008)
            // A dot where the thumb sits, on the face turned toward the holder.
            if let touch = wand.touch {
                withState {
                    translate(touch.x * 0.028, touch.y * 0.055, 0.006)
                    fill(beamColor)
                    drawSphere(radius: 0.008)
                }
            }
        }
    }

    private func view() -> Camera3D {
        let eye = Vector3(sin(viewAngle) * 3.4, 1.3, cos(viewAngle) * 3.4)
        return .perspective(eye: eye, target: Vector3(0, -0.1, -1.2), fieldOfView: .pi / 3)
    }

    // MARK: Words

    private func drawWaiting() {
        let text = device.isStreaming
            ? "Connected. Choose Wand on the phone.\n\n" +
              "Point the back of the phone at the balls,\n" +
              "press the pad to pick one up."
            : device.waitingMessage + "\n\n" +
              "Run the Ollin capture app on the iPhone, choose Wand,\n" +
              "and point the back of the phone at the screen."
        drawStatus(text, style: .info)
    }

    private func caption(for wand: PhoneWand) -> String {
        var parts = ["PhonePointer"]
        parts.append(wand.isTracked ? "tracking" : "finding its place")
        if let index = held {
            parts.append(String(format: "holding ball %d at %.2f m", index + 1, holdDistance))
        } else if let target = aim(of: wand) {
            parts.append(String(format: "on ball %d at %.2f m", target.index + 1, target.distance))
        } else {
            parts.append("pointing at nothing")
        }
        parts.append("\(wand.pressCount) presses")
        return parts.joined(separator: " · ")
    }
}
