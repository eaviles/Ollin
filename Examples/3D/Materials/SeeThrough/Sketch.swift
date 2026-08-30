import Ollin

/// See-through glass: the scene inside the bottle, on any GPU.
///
/// A transmissive material shows its `environment(_:)` and nothing else, so glass
/// standing in front of a scene comes out empty: the wall behind it, the floor, the
/// other objects, none of them appear in it. `sceneThroughGlass()` fills that in. The
/// renderer draws the frame a second time with every transmissive surface taken out, and
/// each piece of glass reads that picture where its own refracted view ray leaves the
/// body:
///
/// ```swift
/// environment(.studio)                     // something to transmit
/// sceneThroughGlass()                      // and now the scene, too
/// material(.glass(thickness: 1.8))
/// drawSphere(radius: 0.9)
/// ```
///
/// **Hold the space bar** to turn it off and watch the colored wall drop out of the
/// glass, leaving the studio behind. It needs no ray tracing, so it runs anywhere Metal
/// does; where `rayTracedReflections()` runs it steps aside, since a traced walk shows
/// the same scene without a screen read's two limits: only what the camera drew can show
/// through (a lookup that leaves the frame fades back into the environment), and one
/// piece of glass does not appear inside another. The price is the second pass: a frame
/// with glass draws its scene twice.
@main
final class SeeThrough: Sketch {

    override func draw() {
        background(Color(hex: 0x14171d))
        cameraShowcase(.sway(amplitude: 0.2, period: .tau / 0.09),
                       target: Vector3(0, 1.2, 0), radius: 10, elevation: 0.16,
                       fieldOfView: .pi / 4, near: 1, far: 40)
        environment(.studio.intensified(to: 1.1).backgroundBlurred(0.5))
        directionalLight(.white, direction: Vector3(-0.4, -1, -0.25), intensity: 0.7)

        // The whole feature, in one line (hold space to compare).
        if !isKeyDown(" ") { sceneThroughGlass() }

        // A matte floor and a row of colored blocks: the content the glass has to carry.
        withState {
            material(.dielectric(roughness: 0.8))
            fill(Color(hex: 0x3a3f4c))
            translate(0, -0.55, 0)
            drawBox(width: 30, height: 1.0, depth: 18)
        }
        let blocks = [Color(hex: 0xe6533c), Color(hex: 0xf2b134), Color(hex: 0x4fb477),
                      Color(hex: 0x3f7fd6), Color(hex: 0xb35fd1)]
        for (i, c) in blocks.enumerated() {
            withState {
                material(.dielectric(roughness: 0.6))
                fill(c)
                translate((Double(i) - 2) * 1.4, 1.5, -3.0)
                drawBox(width: 1.0, height: 4.0, depth: 0.5)
            }
        }

        // Four bodies, left to right: a thin pane (what stands behind it, undistorted),
        // a solid sphere (the blocks slide as the body bends the view), a frosted solid
        // (the same scene, softened by the mip the roughness picks), and a tinted solid
        // (bottle green deepening with the distance light travels inside).
        let r = 0.9
        let bodies: [(fill: Color, mat: Material)] = [
            (Color(hex: 0xcfe4ff), .glass()),
            (.white, .glass(thickness: r * 2)),
            (.white, .glass(roughness: 0.3, thickness: r * 2)),
            (.white, .glass(thickness: r * 2,
                            attenuationColor: Color(hex: 0x2e8f5b),
                            attenuationDistance: 2.6)),
        ]
        for (i, b) in bodies.enumerated() {
            withState {
                material(b.mat)
                fill(b.fill)
                translate((Double(i) - 1.5) * 2.0, 0.9, 0.8)
                drawSphere(radius: r)
            }
        }

        drawCaption(isKeyDown(" ")
            ? "Refracting the environment only (release space for the scene)"
            : "The scene shows through the glass (hold space to compare)")
    }
}
