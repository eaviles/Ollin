// figure: frame=0
//
// Guide diagram (Chapter 13): plain random versus blue noise. The same
// number of dots in each panel. Chance clumps and leaves gaps; the
// dart-throwing scatter keeps every dot a respectful distance from every
// other, even but never gridded.
import Ollin

final class ScatterCompare: Sketch {
    override var canvasSize: CanvasSize { .size(880, 480) }

    let ink = Color(hex: 0x2B2B2B)
    let soft = Color(hex: 0x2B2B2B, alpha: 0.12)

    override func draw() {
        background(Color(hex: 0xF7F5F1))
        textSize(17)
        seed(5)

        let left = Rectangle(x: 50, y: 60, width: 370, height: 340)
        let right = Rectangle(x: 470, y: 60, width: 370, height: 340)

        let even = poissonDisk(in: right.inset(by: .all(12)), radius: 26)
        let loose = (0 ..< even.count).map { _ in
            Vector2(random(left.x + 12, left.x + left.width - 12),
                    random(left.y + 12, left.y + left.height - 12))
        }

        panel(left, title: "random(): clumps and gaps")
        noStroke()
        fill(ink)
        drawCircles(loose, radius: 5)

        panel(right, title: "poissonDisk(): even, never gridded")
        noStroke()
        fill(ink)
        drawCircles(even, radius: 5)

        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("the same number of dots, twice", width / 2, 428)
    }

    func panel(_ r: Rectangle, title: String) {
        noFill()
        stroke(soft)
        strokeWeight(2)
        drawRect(r)
        noStroke()
        fill(ink)
        textAlign(.left, .middle)
        drawText(title, r.x + 2, r.y - 20)
    }
}
