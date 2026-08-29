import Ollin

/// Specular anti-aliasing: highlights on fine shiny detail, held still.
///
/// The scene is a bed of small polished balls under one hard light, seen from
/// far enough away that each ball is a handful of pixels across. Its highlight
/// is then narrower than the pixel it sits in, so the single shading sample per
/// pixel either lands on the speck or misses it, and the bed crawls with
/// sparkle as the camera sways. `specularAntialiasing()` widens the roughness of
/// each pixel by how much its own surface normal turns across it, which turns
/// the missed speck into a slightly broader highlight that stays where it is.
///
/// Turn `ballSize` down to make the problem worse, and `strength` up to answer
/// it harder. The plate at the back is the counterfactual: it is flat, so its
/// normal never turns across a pixel, and the filter leaves it alone whatever
/// the strength.
///
/// Worth knowing while toggling it here: the same frame rendered sixteen samples
/// to a pixel (`--render-scale 4`) sits *between* the two. Off, the bed is too
/// dark because most of its specks are missed; on, it is brighter than the truth
/// because a widened highlight spreads further than the surface really scatters.
/// What the call buys on a bed like this is steadiness rather than accuracy.
@main
final class SpecularAntialias: Sketch {

    @Param(icon: "sparkles", group: "Image")
    var specularAA = true

    /// How far the roughness is widened. 1 is the published pixel filter, and
    /// 2 the conservative form of it, which trades more of the finish for more
    /// calm.
    @Param(0.25...3, icon: "dial.medium", group: "Image")
    var strength = 1.0

    /// Smaller balls put more of the surface under each pixel, which is exactly
    /// what makes the highlight too small to sample. Turn it up and the problem
    /// goes away on its own.
    @Param(0.03...0.25, icon: "circle.grid.3x3", group: "Scene")
    var ballSize = 0.07

    /// The finish the sketch asked for. A polished ball has the narrowest
    /// highlight and the worst crawl.
    @Param(0.04...0.45, icon: "camera.filters", group: "Scene")
    var polish = 0.10

    private let ball = Mesh.sphere(radius: 1, segments: 24, rings: 12)

    override func draw() {
        background(Color(white: 0.03))

        cameraShowcase(.sway(period: 34), target: Vector3(0, 0.1, 0),
                       radius: 12, elevation: 0.34, fieldOfView: .pi / 3.4)

        directionalLight(.white, direction: Vector3(0.35, -0.5, 0.79), intensity: 0.9)
        // Metal has no color of its own without something to reflect, and the
        // environment is a second thing the widening reaches: a rougher pixel
        // reads the environment through a blurrier level of it.
        environment(.studio.intensity(0.35))
        if specularAA { specularAntialiasing(strength: strength) }

        // The bed of balls: 57 by 57 of them over a ten-unit square, each one
        // nudged off the grid so the sparkle does not read as a pattern.
        randomSeed(7)
        var balls: [MeshInstance] = []
        let side = 57
        for row in 0..<side {
            for column in 0..<side {
                let x = -5.0 + 10.0 * Double(column) / Double(side - 1)
                let z = -5.0 + 10.0 * Double(row) / Double(side - 1)
                balls.append(MeshInstance(
                    position: Vector3(x + random(-0.03, 0.03), ballSize,
                                      z + random(-0.03, 0.03)),
                    scale: ballSize * random(0.85, 1.15)))
            }
        }
        fill(Color(white: 0.85))
        material(.metal(roughness: polish))
        drawMesh(ball, instances: balls)

        // The counterfactual: one flat plate of the same metal standing behind
        // the bed. It holds a single normal, so there is no spread to widen by
        // and it renders identically with the filter on or off.
        withState {
            fill(Color(white: 0.8))
            material(.metal(roughness: polish))
            translate(0, 1.5, -5.6)
            drawBox(width: 10.6, height: 3.0, depth: 0.08)
        }

        withState {
            fill(Color(white: 0.16))
            material(.dielectric(roughness: 0.7))
            translate(0, -0.02, 0)
            drawBox(width: 22, height: 0.04, depth: 22)
        }

        let says = specularAA ? "on at strength \(String(format: "%.2f", strength))" : "off"
        drawCaption("specularAntialiasing() \(says) - toggle it in the inspector")
    }
}
