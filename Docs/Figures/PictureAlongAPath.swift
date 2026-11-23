// figure: frame=0 probe
//
// Figure for Docs/3D/Sweeps.md: which way round a picture sits on the meshes
// built along a path. One picture, a word written twice under an orange
// top edge, is shown flat and then worn four ways: by a tube swept down its
// path, where it stands upright; by the same tube swept up, where it hangs
// upside down from the path's start; by that tube with its uvs given a half
// turn, upright again; and by a strip handed its lower rail first.
import Ollin

final class PictureAlongAPath: Sketch {
    override var canvasSize: CanvasSize { .size(880, 340) }

    var picture: RenderTarget!
    var sweptDown = Mesh(positions: [], indices: [])
    var sweptUp = Mesh(positions: [], indices: [])
    var turned = Mesh(positions: [], indices: [])
    var banner = Mesh(positions: [], indices: [])

    override func setup() {
        picture = makeRenderTarget(width: 1024, height: 512)

        let section = Profile.ellipse(radiusX: 0.4, radiusY: 0.4, segments: 48)
        let top = Vector3(0, 0.65, 0), bottom = Vector3(0, -0.65, 0)
        sweptDown = .sweep(section, along: Curve3D([top, bottom]))
        sweptUp = .sweep(section, along: Curve3D([bottom, top]))
        turned = sweptUp
        turned.uvs = turned.uvs.map { Vector2(1 - $0.x, 1 - $0.y) }

        let lower = (0...32).map { k -> Vector3 in
            let t = Double(k) / 32
            return Vector3(-0.8 + 1.6 * t, -0.4, 0.1 * sin(2 * .pi * t))
        }
        banner = .strip(between: lower, and: lower.map { $0 + Vector3(0, 0.8, 0) })
    }

    private func drawPicture() {
        withTarget(picture) {
            background(Color(hex: 0xEFE9DC))
            noStroke()
            fill(Color(hex: 0xF29E4C))
            drawRect(0, 0, 1024, 70)                 // the picture's top edge
            fill(Color(hex: 0x1B2230))
            textAlign(.center, .middle)
            textSize(104)
            for half in 0..<2 {
                drawText("OLLIN", 256 + Double(half) * 512, 290)
            }
        }
    }

    override func draw() {
        drawPicture()
        background(Color(hex: 0x0B0C12))

        let unit = 115.0                              // pixels to one world unit
        let centers = [98.0, 290, 440, 590, 765]
        let captions = [("the picture", ""), ("swept down", "upright"), ("swept up", "upside down"),
                        ("swept up, uvs", "a half turn round"), ("a strip,", "lower rail first")]
        let middle = 142.0

        drawImage(picture.image, centers[0] - 78, middle - 39, 156, 78)

        ortho(eye: Vector3(0, 0, 10), target: .zero, up: .unitY, height: height / unit)
        directionalLight(.white, direction: Vector3(-0.3, -0.4, -1), intensity: 0.5)
        ambientLight(Color(white: 0.72))
        for (k, mesh) in [sweptDown, sweptUp, turned, banner].enumerated() {
            withState {
                translate((centers[k + 1] - width / 2) / unit, -(middle - height / 2) / unit, 0)
                fill(.white)
                drawMesh(mesh.textured(picture.image))
            }
        }

        textAlign(.center, .middle)
        textSize(17)
        for (k, caption) in captions.enumerated() {
            fill(Color(white: 0.85))
            drawText(caption.0, centers[k], 262)
            fill(Color(white: 0.6))
            drawText(caption.1, centers[k], 286)
        }
    }
}
