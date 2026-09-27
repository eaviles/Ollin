// figure: frame=90 unstable
//
// Guide payoff (Chapter 31): a lamplit room. One pendant lamp swings on its
// cord over a waxed floor between a terracotta wall and a teal one. The light
// bounces off the floor onto the ceiling and carries the walls' colors into
// the room, the floor shows the room in its sheen, and a glass ball on a
// plinth focuses the lamp into a bright spot inside its own shadow, which
// slides as the lamp swings. A red ball rolls around the plinth, declared with
// withMotion so its edges settle and it streaks, and the lamp flares in the
// lens. Frame 90 is a second and a half in, so the ball has a frame behind it
// to streak from. Unstable because the caustic photons land in an order the
// GPU's atomics decide, as in CausticLight.
import Ollin

final class LamplitRoom: Sketch {
    let bulb = Image(width: 1, height: 1, color: Color(hex: 0xFFF1D6))
    let pivot = Vector3(-0.9, 4.0, -0.6)

    override func draw() {
        background(.black)
        var lens = Camera3D(eye: Vector3(0.2, 1.8, 3.8), target: Vector3(0.4, 1.4, -1),
                            projection: .perspective(fieldOfView: .pi / 2.8))
        lens.apertureBlades = 6
        camera(lens)
        toneMap(.aces, exposure: 1.2)

        // The lamp swings on its cord, and its light points down the cord.
        let swing = 0.3 * sin(time * 1.2)
        let down = Vector3(sin(swing), -cos(swing), 0)
        let lamp = pivot + down * 1.1
        spotLight(Color(hex: 0xFFE2B8), at: lamp, direction: down,
                  coneAngle: 2.0, penumbra: 0.6, intensity: 4)

        // What the light does once it lands.
        environment(.studio.intensified(to: 0.12))
        castShadows()
        globalIllumination()
        rayTracedReflections()
        glossyReflections()
        caustics(dispersion: 0.3)

        // What the camera does with it.
        temporalAntialiasing()
        motionBlur()
        lensFlare(amount: 0.5)

        // The room: a waxed floor, a white ceiling and back wall, one
        // terracotta wall and one teal one.
        withState {
            material(.dielectric(roughness: 0.2))
            fill(Color(hex: 0x7A5E48))
            translate(0, -0.1, 0)
            drawBox(width: 8.4, height: 0.2, depth: 8.4)
        }
        fill(Color(white: 0.86))
        withState { translate(0, 4.1, 0); drawBox(width: 8.4, height: 0.2, depth: 8.4) }
        withState { translate(0, 2, -4.3); drawBox(width: 8.4, height: 4.4, depth: 0.2) }
        withState { fill(Color(hex: 0xC8603A)); translate(-4.3, 2, 0); drawBox(width: 0.2, height: 4.4, depth: 8.4) }
        withState { fill(Color(hex: 0x2A8C8C)); translate(4.3, 2, 0); drawBox(width: 0.2, height: 4.4, depth: 8.4) }

        // A glass ball on a white plinth, wide enough that the lamp's light
        // comes to its focus on the plinth's top rather than spreading again
        // on the floor beyond it.
        withState { translate(1.1, 0.25, 0.2); drawBox(width: 1.6, height: 0.5, depth: 0.9) }
        withState {
            material(.glass(thickness: 1.2))
            fill(.white)
            translate(1.0, 1.1, 0.2)
            drawSphere(radius: 0.6)
        }

        // A red ball rolling around the plinth.
        withMotion("ball") {
            withState {
                material(.dielectric(roughness: 0.35))
                fill(Color(hex: 0xC8302C))
                translate(1.0, 0.3, 0.2)
                rotate(time * 1.8, axis: .unitY)
                translate(1.5, 0, 0)
                drawSphere(radius: 0.3)
            }
        }

        // The cord and the bulb. The bulb sits a little up the cord from the
        // light, so it never stands between the light and the room.
        withMotion("lamp") {
            withState {
                fill(Color(white: 0.1))
                translate(pivot)
                rotateZ(swing)
                translate(0, -0.475, 0)
                drawCylinder(radius: 0.012, height: 0.95)
            }
            withState {
                translate(lamp - down * 0.08)
                fill(.white)
                matcap(bulb)
                drawSphere(radius: 0.07)
            }
            matcap(nil)
        }
    }
}
