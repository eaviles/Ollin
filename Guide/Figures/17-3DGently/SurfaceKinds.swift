// figure: frame=0
//
// Guide figure (Chapter 17): three ways to dress the same mesh. A lit surface,
// the triangle net that surface is made of, and an image wrapped through the
// mesh's texture coordinates. All three are ordinary drawing state, so one
// frame can hold all of them.
import Ollin

final class SurfaceKinds: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    let globe = Mesh.sphere(radius: 0.95, segments: 40, rings: 20)
    lazy var wrapped = globe.textured(Self.checker(128))

    override func draw() {
        background(Color(hex: 0x0B0D12))
        camera(.perspective(eye: Vector3(0, 0.35, 7.4), target: .zero,
                            fieldOfView: .pi / 4.2))
        lightingPreset(.studio)

        // Solid: the lit material path from earlier in the chapter.
        withState {
            translate(-2.5, 0.25, 0)
            fill(Color(hex: 0x2C8C86))
            material(.glossy)
            drawMesh(globe)
            label("solid")
        }

        // Wireframe: the same mesh as its triangle edges.
        withState {
            translate(0, 0.25, 0)
            stroke(Color(hex: 0x9FD8D2))
            strokeWeight(1)
            wireframe()
            drawMesh(globe)
            label("wireframe()")
        }

        // Textured: an image mapped through the mesh's own UVs.
        withState {
            translate(2.5, 0.25, 0)
            fill(.white)
            material(.matte)
            rotateY(-0.5)
            drawMesh(wrapped)
            label("textured(image)")
        }
    }

    private func label(_ text: String) {
        withBillboard(at: Vector3(0, -1.55, 0)) {
            // The wireframe panel leaves a stroke set, which would outline this
            // label and make it read differently from its neighbors.
            noStroke()
            fill(.white)
            textSize(23)
            textAlign(.center, .middle)
            drawText(text, 0, 0)
        }
    }

    /// A two-tone checker with gridlines, so the wrapping (and the pinch at the
    /// poles) is easy to read.
    private static func checker(_ n: Int) -> Image {
        let image = Image(width: n, height: n)
        let cell = n / 12
        for y in 0..<n {
            for x in 0..<n {
                let onLine = x % cell == 0 || y % cell == 0
                let dark = ((x / cell) + (y / cell)) % 2 == 0
                image[x, y] = onLine ? Color(hex: 0x1B2029)
                    : (dark ? Color(hex: 0xE8B24A) : Color(hex: 0xF2E4C8))
            }
        }
        return image
    }
}
