import Ollin
import OllinSamplePhotos

/// One height map, read two ways: parallax occlusion and real displacement.
///
/// A height map is a picture of relief, white at the surface and darker the
/// deeper it is carved. `parallaxMapped(_:scale:)` reads it per pixel: the
/// renderer marches the eye ray through the relief and shifts what every other
/// map shows, so the craters sink convincingly and slide with the view, yet
/// not one vertex has moved. `displaced(by:scale:)` reads the same image as
/// geometry: vertices really move, normals are recomputed, and the relief
/// becomes true of the mesh.
///
/// The silhouette is the tell, and the whole lesson: turn the spheres and
/// watch their outlines. The parallax sphere stays a perfect circle no matter
/// how deep the craters look (shading only, the technique's honest envelope,
/// and the same reason its cast shadow and reflection stay round); the
/// displaced sphere's rim is genuinely cratered. Inside the outline the two
/// read almost alike, which is exactly why parallax is worth having: all of
/// the depth at none of the geometry.
///
/// The map is a photograph. A dry-stone wall carries both maps at once: the
/// picture is the color, and its own light and shade is the relief, which is
/// what a height map is. `depth` drives the parallax relief live.
@main
final class Parallax: Sketch {

    @Param(0...0.12, icon: "arrow.down.to.line") var depth = 0.06

    var parallaxSphere = Mesh(positions: [], normals: [], indices: [])
    var displacedSphere = Mesh(positions: [], normals: [], indices: [])
    var bare = Mesh(positions: [], normals: [], indices: [])

    override func setup() {
        // A photograph of a dry-stone wall carries both maps at once: the
        // picture is the color, and its own light and shade is the relief,
        // which is what a height map is.
        let colorMap = SamplePhoto.stone.load()
        let heightMap = colorMap
        let base = Mesh.sphere(radius: 1, segments: 96, rings: 48)
        parallaxSphere = base.textured(colorMap).parallaxMapped(heightMap, scale: 0.06)
        displacedSphere = base.displaced(by: heightMap, scale: 0.13).textured(colorMap)
        bare = base.textured(colorMap)
    }

    override func draw() {
        background(Color(hex: 0x0E1116))
        cameraShowcase(.sway(amplitude: 0.2, period: 24), target: .zero, radius: 8.6,
                       elevation: 0.12, fieldOfView: .pi / 4)
        environment(.studio.intensified(to: 1.05))
        directionalLight(Color(white: 0.9), direction: Vector3(-0.5, -0.6, -0.6))

        var carved = parallaxSphere
        carved.material?.heightScale = depth

        fill(.white)
        material(.dielectric(roughness: 0.75))
        let xs: [Double] = [-2.4, 0, 2.4]
        for (mesh, x) in zip([carved, displacedSphere, bare], xs) {
            withState {
                translate(x, 0.25, 0)
                drawMesh(mesh)
            }
        }
        material(Material())
        drawLabels(at: xs)
    }

    private func drawLabels(at xs: [Double]) {
        withState {
            textFont(OutlineFont.system)
            textSize(26)
            textAlign(.center)
            noStroke()
            fill(Color(white: 0.55))
            for (name, x) in zip(["parallax", "displaced", "bare"], xs) {
                if let p = project(Vector3(x, -1.45, 0)) {
                    drawText(name, at: p)
                }
            }
        }
    }
}
