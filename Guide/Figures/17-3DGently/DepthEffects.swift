// figure: frame=0
//
// Guide diagram (Chapter 17): what a scene's own depth buffer is good for.
// The same block field rendered plainly, then with ambient occlusion
// darkening its crevices, then with depth of field blurring what the camera
// is not focused on. Both effects read the depth layer, not the color.
import Ollin

final class DepthEffects: Sketch {
    override var canvasSize: CanvasSize { .size(880, 380) }

    let paper = Color(hex: 0xF7F5F1)
    let ink = Color(hex: 0x232020)
    let soft = Color(hex: 0x2B2B2B, alpha: 0.12)

    override func draw() {
        background(paper)

        let scene = renderTarget()
        withTarget(scene) { blocks() }

        let panels = (0 ..< 3).map {
            Rectangle(x: 25 + Double($0) * 284, y: 58, width: 262, height: 262)
        }

        drawImage(scene.image, in: panels[0])
        drawImage(scene.combined(with: scene.depth,
                                 .ambientOcclusion(radius: 0.7, intensity: 1.5)).image,
                  in: panels[1])
        drawImage(scene.combined(with: scene.depth,
                                 .defocus(focus: 0.46, range: 0.13, maxBlur: 16)).image,
                  in: panels[2])

        let titles = ["the scene", "+ ambientOcclusion", "+ defocus"]
        for (i, panel) in panels.enumerated() { frame(panel, title: titles[i]) }

        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("the depth layer knows what the color layer cannot",
                 width / 2, 336)
    }

    /// A packed field of blocks: gaps for occlusion to settle into, and a long
    /// run into the distance for the focus to fall off along.
    func blocks() {
        // The block heights come from noise, so the seed has to be pinned or
        // the figure re-renders differently every run.
        noiseSeed(4)
        background(Color(hex: 0x121318))
        camera(.orbiting(target: Vector3(0, 0.4, 0), radius: 9, azimuth: 0.7,
                         elevation: 0.42, fieldOfView: .pi / 4, near: 3, far: 18))
        ambientLight(Color(white: 0.55))
        directionalLight(.white, direction: Vector3(-0.4, -1, -0.3), intensity: 0.7)

        withState {
            fill(Color(white: 0.8))
            translate(0, -0.2, 0)
            drawBox(width: 16, height: 0.4, depth: 16)
        }

        let n = 6
        let cell = 1.1, box = 0.86
        for ix in 0 ..< n {
            for iz in 0 ..< n {
                let fx = Double(ix) - Double(n - 1) / 2
                let fz = Double(iz) - Double(n - 1) / 2
                let h = 0.5 + 1.6 * noise(Double(ix) * 0.6, Double(iz) * 0.6)
                withState {
                    fill(Color(white: 0.78))
                    translate(fx * cell, h / 2, fz * cell)
                    drawBox(width: box, height: h, depth: box)
                }
            }
        }
    }

    func frame(_ r: Rectangle, title: String) {
        noFill()
        stroke(soft)
        strokeWeight(2)
        drawRect(r)
        noStroke()
        fill(ink)
        textSize(16)
        textAlign(.left, .middle)
        drawText(title, r.x, r.y - 18)
    }
}
