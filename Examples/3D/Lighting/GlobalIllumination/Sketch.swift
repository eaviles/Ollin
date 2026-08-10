import Ollin

/// Global illumination: light that bounces.
///
/// Direct light only ever explains half a picture. In a real room the sun patch on
/// the floor lights the ceiling from below, a colored wall tints everything beside
/// it, and the shadowed side of an object is filled by light arriving second-hand.
/// `globalIllumination()` turns that on: the renderer keeps a grid of light probes
/// over the scene, re-traces them every frame against the actual geometry, and every
/// lit surface adds the bounce light the probes saw, so moving lights and moving
/// shapes keep bouncing correctly.
///
/// This set is built to show it: a room whose only light is one swinging spot. With
/// GI off (press space) everything outside the pool is black. With it on, the pool
/// on the floor becomes the room's real lamp: the ceiling glows from below, the
/// orange and teal walls dye the white statue from either side, and the ball's
/// shadowed back is filled with floor-light. The `intensity` knob is an honest
/// physical 1 by default; art wants what art wants, so it goes higher.
///
/// Needs a ray-tracing GPU (Apple silicon); elsewhere the direct pool is all there is.
@main
final class GlobalIllumination: Sketch {

    override var loopDuration: Double? { 12 }

    @Param(0...4, icon: "sun.max") var intensity = 1.0
    private var bounceOn = true

    override func keyPressed() {
        if key == " " { bounceOn.toggle() }
    }

    override func draw() {
        background(.black)
        cameraShowcase(.sway(amplitude: 0.25, period: 24), target: Vector3(0, 1.9, 0),
                       radius: 9.5, elevation: 0.03, fieldOfView: .pi / 3.2)

        // The one light: a white spot swinging its pool across the floor. Everything
        // else the picture shows is that pool, re-delivered by the walls.
        let swing = sin(time * .tau / 12) * 1.8
        spotLight(.white, at: Vector3(swing * 0.4, 3.8, 0.4),
                  direction: Vector3(swing * 0.12, -1, -0.1),
                  angle: .pi / 3.4, penumbra: 0.5, intensity: 3)
        castShadows()
        if bounceOn { globalIllumination(intensity: intensity) }

        // The room: white floor, ceiling, and back; an orange wall and a teal wall
        // whose whole job is to be seen again on the white things between them.
        withState { fill(Color(white: 0.88)); translate(0, -0.1, 0); drawBox(width: 8.4, height: 0.2, depth: 8.4) }
        withState { fill(Color(white: 0.88)); translate(0, 4.1, 0); drawBox(width: 8.4, height: 0.2, depth: 8.4) }
        withState { fill(Color(white: 0.88)); translate(0, 2, -4.3); drawBox(width: 8.4, height: 4.4, depth: 0.2) }
        withState { fill(Color(hex: 0xd4622a)); translate(-4.3, 2, 0); drawBox(width: 0.2, height: 4.4, depth: 8.4) }
        withState { fill(Color(hex: 0x2a9d9d)); translate(4.3, 2, 0); drawBox(width: 0.2, height: 4.4, depth: 8.4) }

        // A white statue between the colored walls: the block's faces dye orange on
        // one side and teal on the other, which is the whole demonstration.
        withState {
            fill(Color(white: 0.9))
            translate(-1.2, 1.1, 0.4); rotateY(0.42)
            drawBox(width: 1.5, height: 2.2, depth: 1.5)
        }
        withState {
            fill(Color(white: 0.9))
            translate(1.7, 0.75, -0.9)
            drawSphere(radius: 0.75)
        }
        // A glossy porcelain pill in the pool's path. (Not a metal: with no
        // environment a metal has nothing to reflect and reads black; bounce
        // light is diffuse, and porcelain has a diffuse side to catch it.)
        withState {
            fill(Color(white: 0.85)); material(.dielectric(roughness: 0.25))
            translate(0.4, 0.6, 2.0); rotateZ(.pi / 2)
            drawCapsule(radius: 0.35, height: 1.2)
        }

        drawCaption("global illumination \(bounceOn ? "on" : "off"), space toggles")
    }
}
