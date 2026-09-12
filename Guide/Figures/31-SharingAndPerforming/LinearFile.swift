// figure: frame=0 themed
//
// Guide figure (Chapter 31): what the linear file carries that the picture
// cannot. The same frame three ways, all read off one layer: as a screen shows
// it, four stops down (where a blown highlight turns out to have a shape), and
// the distance from the eye that rides along as the Z channel.
import Ollin
import OllinDiagram

final class LinearFile: Sketch {
    override var canvasSize: CanvasSize { .size(880, 340) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }

    override func setup() { noLoop() }

    override func draw() {
        background(paper)

        let tile = 268.0, tall = 200.0, gap = 18.0
        let left = (width - tile * 3 - gap * 2) / 2
        let top = 38.0

        // One render of the scene, kept as a layer. Everything below reads this
        // same layer, which is what the file holds.
        let scene = makeRenderTarget(width: Int(tile * 2), height: Int(tall * 2))
        withTarget(scene) { lane() }

        panel(scene.image, at: 0, left: left, top: top, tile: tile, tall: tall,
              title: "as a screen shows it", note: "the highlights are flat white")
        panel(scene.filtered(.exposure(stops: -4)).image, at: 1, left: left, top: top,
              tile: tile, tall: tall,
              title: "four stops down", note: "the light was still in the file")
        panel(scene.depth.image, at: 2, left: left, top: top, tile: tile, tall: tall,
              title: "the Z channel", note: "distance from the eye, far is bright")

        textFont(.system)
        noStroke()
        fill(ink)
        textSize(19)
        textAlign(.center, .top)
        drawText("--export-exr writes the frame before the tone map, so all three survive",
                 width / 2, top + tall + 62)
    }

    /// One panel with its two lines of label.
    private func panel(_ image: Image, at index: Int, left: Double, top: Double,
                       tile: Double, tall: Double, title: String, note: String) {
        let x = left + Double(index) * (tile + 18)
        drawImage(image, in: Rectangle(x: x, y: top, width: tile, height: tall))
        textFont(.system)
        noStroke()
        fill(ink)
        textSize(17)
        textAlign(.center, .top)
        drawText(title, x + tile / 2, top + tall + 12)
        fill(ink.withAlpha(0.6))
        textSize(14)
        drawText(note, x + tile / 2, top + tall + 34)
    }

    /// A lane of glossy spheres under one hard lamp, which is the example this
    /// section points at, drawn small.
    private func lane() {
        background(Color(hex: 0x05070C))
        perspective(eye: Vector3(0, 3.1, 7.4), target: Vector3(0, -0.5, -9),
                    fieldOfView: .pi / 3.2, near: 0.5, far: 40)
        ambientLight(Color(white: 0.06))
        pointLight(Color(hue: 0.09, saturation: 0.22, brightness: 1),
                   at: Vector3(2.6, 2.8, 3.4), intensity: 9)
        pointLight(Color(hue: 0.55, saturation: 0.55, brightness: 1),
                   at: Vector3(-3.8, 1.4, -6), intensity: 5)
        withState {
            translate(0, -0.6, 0)
            fill(Color(white: 0.16))
            specular(0.55)
            specularSharpness(260)
            drawPlane(width: 30, depth: 44)
        }
        for i in 0..<9 {
            let t = Double(i) / 8
            withState {
                translate(i.isMultiple(of: 2) ? -1.9 : 1.9, -0.05 + t * 0.05,
                          2.4 - Double(i) * 2.2)
                fill(Color(hue: 0.02 + t * 0.55, saturation: 0.5, brightness: 0.9))
                specular(0.85)
                specularSharpness(90 + t * 260)
                drawSphere(radius: 0.55)
            }
        }
    }
}
