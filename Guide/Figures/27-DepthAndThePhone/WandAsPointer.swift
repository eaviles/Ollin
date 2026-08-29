// figure: frame=0
//
// Guide figure (Chapter 27): the phone held as a pointer. A beam runs out of the
// back of the phone and lands on one of four floating balls, which lights up; the
// others stay dark. The beam stops where it lands, which is the whole idea of
// asking a ray what it hits rather than drawing a line and hoping.
//
// The reading is staged rather than read, the way this chapter's other figures
// stage a depth camera: the same PhoneWand a phone fills in, built by hand from a
// PhoneWandSample so the figure renders anywhere.
import Foundation
import simd
import Ollin
import OllinPhone

final class WandAsPointer: Sketch {
    override var canvasSize: CanvasSize { .size(880, 520) }

    let beamColor = Color(hex: 0x7FE7DC)
    let phoneColor = Color(hex: 0xE8E8EF)
    let ballColor = Color(hex: 0x4D96FF)
    let litColor = Color(hex: 0xFFD93D)

    /// A staged reading. The basis is what ARKit reports for the camera: x across,
    /// y up, and the phone looking along -z, here turned to aim at the middle ball.
    static func staged(at position: SIMD3<Float>, aimedAt target: SIMD3<Float>) -> PhoneWand {
        let forward = simd_normalize(target - position)
        let right = simd_normalize(simd_cross(SIMD3<Float>(0, 1, 0), -forward))
        let up = simd_cross(-forward, right)
        return PhoneWand(PhoneWandSample(
            tracked: true, timestamp: 0,
            transform: simd_float4x4(SIMD4(right, 0), SIMD4(up, 0),
                                     SIMD4(-forward, 0), SIMD4(position, 1)),
            quarterTurnsCW: 0, pressed: true, pressCount: 1,
            hasTouch: true, touch: SIMD2<Float>(0, 0.4)))
    }

    /// Four balls at arm's length, one of them in the way of the beam.
    let balls = [Vector3(-0.5, 1.46, -1.42), Vector3(0.02, 1.3, -1.5),
                 Vector3(0.32, 0.98, -1.52), Vector3(0.44, 1.44, -1.34)]
    let radius = 0.12

    lazy var wand = WandAsPointer.staged(at: SIMD3<Float>(-0.55, 1.05, 0.1),
                                         aimedAt: SIMD3<Float>(0.02, 1.3, -1.55))

    override func draw() {
        background(Color(hex: 0x0D1017))
        // Over the holder's shoulder: the screen and its thumb dot face us, and
        // the beam runs away into the room, which is what the hand actually sees.
        camera(.perspective(eye: Vector3(-0.38, 1.36, 1.31),
                            target: Vector3(-0.22, 1.2, -0.78),
                            fieldOfView: .pi / 5))
        environment(.studio.intensity(1.0).lightingOnly())
        material(.clay)

        // What the beam lands on, and how far away it is. This is the one question
        // a sketch asks the wand.
        var landing: (index: Int, distance: Double)?
        for (i, ball) in balls.enumerated() {
            guard let distance = wand.ray.hit(sphereAt: ball, radius: radius) else { continue }
            if landing == nil || distance < landing!.distance { landing = (i, distance) }
        }

        for (i, ball) in balls.enumerated() {
            withState {
                translate(ball)
                fill(i == landing?.index ? litColor : ballColor)
                drawSphere(radius: radius)
            }
        }

        // The beam, stopping where it lands.
        let end = wand.point(at: landing?.distance ?? 3)
        withState {
            fill(beamColor)
            drawTube([wand.position, end], radius: 0.007, sides: 6)
        }

        // The phone itself, drawn in its own frame so it leans the way it leans.
        withState {
            transform(wand.placement)
            fill(phoneColor)
            drawBox(width: 0.071, height: 0.146, depth: 0.008)
            if let touch = wand.touch {
                withState {
                    translate(touch.x * 0.028, touch.y * 0.055, 0.006)
                    fill(beamColor)
                    drawSphere(radius: 0.009)
                }
            }
        }

        drawCaption("WandAsPointer: the beam leaves the back of the phone and stops at what it hits")
    }
}
