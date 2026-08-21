import Ollin

/// A textured 3D mesh: a sphere wearing an image, mapped through its UVs and lit by
/// the material model. The texture here is built in code (a colorful UV grid), so the
/// sketch is self-contained, but any `Image` works: `loadImage(...)` then
/// `mesh.textured(image)`.
///
/// `Mesh.textured(_:)` returns a copy carrying the image as its surface; the built-in
/// `.sphere` and `.plane` generators emit the UVs it maps through. The grid makes the
/// mapping legible: hue runs around the sphere (longitude), brightness checkers, and
/// the dark lines are the UV gridlines, so you can read the poles pinching and the seam
/// where u wraps. Drag to spin.
///
/// The floor shows the other half of texturing: its uvs run to 4 rather than 1, so it
/// asks for four copies of the picture across its width. `wrap: .tile` is what answers
/// that. The default (`.clamp`) would draw one copy and smear its edge pixels over the
/// rest, which is the right answer for a picture mapped once onto a shape and the wrong
/// one for a floor.
@main
final class TexturedMeshExample: Sketch {
    private lazy var grid = Self.uvGrid(128)
    private lazy var globe = Mesh.sphere(radius: 1.5, segments: 64, rings: 32).textured(grid)
    private lazy var floor: Mesh = {
        var plane = Mesh.plane(width: 6, depth: 6)
        plane.uvs = plane.uvs.map { $0 * 4 }      // four tiles across, so the uvs leave 0…1
        return plane.textured(grid, baseColor: Color(white: 0.7), wrap: .tile)
    }()

    override func draw() {
        background(Color(hex: 0x0A0C12))

        cameraShowcase(.turntable(period: .tau / 0.4), target: Vector3(0, 0.2, 0), radius: 6,
                    elevation: 0.5, fieldOfView: .pi / 3.4)

        // The floor wears the same grid, tiled and dimmed by its base color so the
        // globe reads as the subject. A textured mesh still takes the lights, here
        // the auto-lit default rig.
        withState { translate(0, -1.7, 0); drawMesh(floor) }
        withState { rotateY(time * 0.2); drawMesh(globe) }

        drawCaption("TexturedMesh: a UV-mapped image on a sphere, tiled on the floor; drag to spin")
    }

    /// A deterministic UV-test texture: hue by u (longitude), a brightness checker,
    /// and dark gridlines, so the mapping onto the mesh is easy to read.
    private static func uvGrid(_ n: Int) -> Image {
        let img = Image(width: n, height: n)
        let cell = n / 16
        for y in 0..<n {
            for x in 0..<n {
                let onGrid = x % cell == 0 || y % cell == 0
                let checker = ((x / cell) + (y / cell)) % 2 == 0
                if onGrid {
                    img[x, y] = Color(white: 0.12)
                } else {
                    let u = Double(x) / Double(n - 1)
                    img[x, y] = Color(hue: u, saturation: 0.7, brightness: checker ? 0.95 : 0.55)
                }
            }
        }
        return img
    }
}
