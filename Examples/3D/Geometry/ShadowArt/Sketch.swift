import Ollin

/// One solid, two shadows, and neither shadow looks like the solid.
///
/// A lit point casts a shadow along the light's direction, so a point can only be
/// part of the solid if it lands inside the shadow in *every* direction it is lit
/// from. Keep exactly those points and what is left is the largest solid that
/// could cast them.
///
/// Here the front asks for a ring and the side asks for a lopsided cross. The
/// solid that comes out looks like neither, and turning it shows why: it is the
/// two silhouettes swept through each other and cut where they cross.
///
/// The two shadows it really throws are drawn under it, beside the two it was
/// asked for. They match, because these two are solid in the same rows. That is
/// the catch worth knowing: the front and the side are seen from either end of the
/// same vertical axis, so a row that is empty in one empties it in the other. Hold
/// the mouse to ask for a third shadow from above as well, and watch all three
/// fall short of what was asked, since no solid can throw them all.
@main
final class ShadowArt_Example: Sketch {
    override var loopDuration: Double? { 18 }

    private let resolution = 56
    private var front = Image(width: 96, height: 96, color: .black)
    private var side = Image(width: 96, height: 96, color: .black)
    private var above = Image(width: 96, height: 96, color: .black)
    private var carved: ShadowArt?
    private var solid = Mesh(positions: [], indices: [])
    private var withAbove: ShadowArt?
    private var withAboveMesh = Mesh(positions: [], indices: [])

    override func setup() {
        paint(front) { u, v in
            let r = (u * u + v * v).squareRoot()
            return r < 0.86 && r > 0.42
        }
        paint(side) { u, v in
            (abs(u) < 0.3 && abs(v) < 0.86) || (abs(v - 0.2) < 0.26 && u < 0.7 && u > -0.86)
        }
        paint(above) { u, v in abs(u) + abs(v) < 0.8 }

        carved = shadowArt(fromFront: front, fromSide: side, resolution: resolution)
        solid = carved?.mesh ?? Mesh(positions: [], indices: [])
        withAbove = shadowArt(fromFront: front, fromSide: side, fromAbove: above,
                              resolution: resolution)
        withAboveMesh = withAbove?.mesh ?? Mesh(positions: [], indices: [])
    }

    override func draw() {
        background(Color(hex: 0x06080D))
        let three = mouseIsPressed
        guard let art = three ? withAbove : carved else { return }

        lightingPreset(.studio)
        cameraShowcase(.autoOrbit(period: 18), radius: 4.4, elevation: 0.3,
                       fieldOfView: .pi / 3.6)

        fill(Color(hex: 0xE8C36A))
        specular(0.35)
        shininess(40)
        drawMesh(three ? withAboveMesh : solid)

        // What was asked for, and what is really thrown.
        let sides: [(ShadowArt.Side, Image, String)] = three
            ? [(.front, front, "front"), (.side, side, "side"), (.above, above, "above")]
            : [(.front, front, "front"), (.side, side, "side")]
        let panel = 150.0
        let gap = 28.0
        let total = Double(sides.count) * (panel * 2 + gap) + gap * Double(sides.count - 1)
        var x = (width - total) / 2
        for (which, asked, name) in sides {
            drawPanel(asked, at: Vector2(x, height - panel - 90), size: panel,
                      title: "\(name): asked")
            drawCast(art.shadow(from: which), at: Vector2(x + panel + gap, height - panel - 90),
                     size: panel, title: "\(name): thrown")
            x += panel * 2 + gap * 2
        }

        drawCaption(three
            ? "three shadows: no solid throws them all, so each one comes up short"
            : "two shadows, both thrown exactly; hold the mouse to ask for a third")
    }

    private func drawPanel(_ picture: Image, at corner: Vector2, size: Double, title: String) {
        drawImage(picture, in: Rectangle(x: corner.x, y: corner.y, width: size, height: size),
                  fit: .cover)
        label(title, at: Vector2(corner.x, corner.y + size + 16))
    }

    private func drawCast(_ flags: [Bool], at corner: Vector2, size: Double, title: String) {
        let n = resolution
        let cell = size / Double(n)
        noStroke()
        fill(Color(hex: 0xE8C36A))
        for row in 0 ..< n {
            for column in 0 ..< n where flags[column + row * n] {
                drawRect(Rectangle(x: corner.x + Double(column) * cell,
                                   y: corner.y + Double(row) * cell,
                                   width: cell + 0.5, height: cell + 0.5))
            }
        }
        noFill()
        stroke(Color(white: 0.3))
        strokeWeight(1)
        drawRect(Rectangle(x: corner.x, y: corner.y, width: size, height: size))
        label(title, at: Vector2(corner.x, corner.y + size + 16))
    }

    private func label(_ text: String, at point: Vector2) {
        noStroke()
        fill(Color(white: 0.62))
        textSize(15)
        textAlign(.left, .middle)
        drawText(text, point.x, point.y)
    }

    private func paint(_ picture: Image, _ inside: (Double, Double) -> Bool) {
        for y in 0 ..< picture.height {
            for x in 0 ..< picture.width {
                let u = (Double(x) + 0.5) / Double(picture.width) * 2 - 1
                let v = (Double(y) + 0.5) / Double(picture.height) * 2 - 1
                picture[x, y] = inside(u, v) ? .white : .black
            }
        }
    }
}
