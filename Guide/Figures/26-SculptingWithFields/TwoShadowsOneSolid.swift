// figure: frame=0 themed
//
// Guide diagram (Chapter 26): shadow art. The two silhouettes asked for on the
// left, the solid they carve in the middle, and the two shadows it really throws
// on the right.
import Ollin
import OllinDiagram

final class TwoShadowsOneSolid: Sketch {
    override var canvasSize: CanvasSize { .size(880, 460) }

    let accent = Color(hex: 0xE07A5F)

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var soft: Color { theme.ink(0.12) }

    override func draw() {
        background(paper)

        let front = paint(96) { u, v in
            let r = (u * u + v * v).squareRoot()
            return r < 0.86 && r > 0.42
        }
        let side = paint(96) { u, v in
            (abs(u) < 0.3 && abs(v) < 0.86) || (abs(v - 0.2) < 0.26 && u < 0.7 && u > -0.86)
        }
        let art = shadowArt(fromFront: front, fromSide: side, resolution: 48)

        // The solid, drawn small and lit, in the middle.
        let stage = Rectangle(x: 330, y: 60, width: 230, height: 230)
        // The lights and the camera are state, so they are set before the clip
        // rather than inside it.
        lightingPreset(.studio)
        cameraShowcase(.autoOrbit(period: 18), radius: 4.2, elevation: 0.34,
                       fieldOfView: .pi / 3.6)
        fill(Color(hex: 0xC9C2B6))
        specular(0.35)
        shininess(44)
        withClip(stage) {
            drawMesh(art.mesh)
        }

        square(front, at: Rectangle(x: 64, y: 60, width: 105, height: 105), title: "asked: front")
        square(side, at: Rectangle(x: 186, y: 60, width: 105, height: 105), title: "asked: side")
        cast(art.shadow(from: .front), resolution: art.resolution,
             at: Rectangle(x: 600, y: 60, width: 105, height: 105), title: "thrown: front")
        cast(art.shadow(from: .side), resolution: art.resolution,
             at: Rectangle(x: 722, y: 60, width: 105, height: 105), title: "thrown: side")

        frame(stage, title: "the solid they carve")

        fill(ink)
        noStroke()
        textSize(21)
        textAlign(.center, .top)
        drawText("a point survives only where every shadow says solid", width / 2, 340)
        textSize(17)
        fill(Color(hex: darkTheme ? 0x9A958D : 0x6E6A63))
        drawText("two silhouettes come out exactly, as long as they are solid in the same rows",
                 width / 2, 374)
    }

    func square(_ picture: Image, at box: Rectangle, title: String) {
        drawImage(picture, in: box, fit: .cover)
        frame(box, title: title)
    }

    func cast(_ flags: [Bool], resolution: Int, at box: Rectangle, title: String) {
        noStroke()
        fill(Color(white: 0.1))
        drawRect(box)
        fill(accent)
        let cell = box.width / Double(resolution)
        for row in 0 ..< resolution {
            for column in 0 ..< resolution where flags[column + row * resolution] {
                drawRect(Rectangle(x: box.x + Double(column) * cell, y: box.y + Double(row) * cell,
                                   width: cell + 0.5, height: cell + 0.5))
            }
        }
        frame(box, title: title)
    }

    func frame(_ r: Rectangle, title: String) {
        noFill()
        stroke(soft)
        strokeWeight(2)
        drawRect(r)
        noStroke()
        fill(ink)
        textSize(14)
        textAlign(.left, .middle)
        drawText(title, r.x, r.y - 16)
    }

    func paint(_ size: Int, _ inside: (Double, Double) -> Bool) -> Image {
        let picture = Image(width: size, height: size, color: .black)
        for y in 0 ..< size {
            for x in 0 ..< size {
                let u = (Double(x) + 0.5) / Double(size) * 2 - 1
                let v = (Double(y) + 0.5) / Double(size) * 2 - 1
                picture[x, y] = inside(u, v) ? .white : .black
            }
        }
        return picture
    }
}
