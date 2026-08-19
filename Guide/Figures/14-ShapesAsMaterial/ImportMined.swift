// figure: frame=0
//
// Guide diagram (Chapter 14): the same imported file three ways. A small
// sailboat authored as SVG arrives as ordinary shapes and contours: drawn
// as authored, respaced into even dots, and hatched for a pen.
import Foundation
import Ollin

final class ImportMined: Sketch {
    override var canvasSize: CanvasSize { .size(880, 340) }

    let ink = Color(hex: 0x2B2B2B)
    let faint = Color(hex: 0x2B2B2B, alpha: 0.4)
    let soft = Color(hex: 0x2B2B2B, alpha: 0.12)

    let boat = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 220 170">
      <circle cx="186" cy="30" r="13" fill="none" stroke="#C8553D" stroke-width="3"/>
      <polygon points="104,16 104,102 44,102" fill="#C8553D"/>
      <polygon points="116,30 116,102 170,102" fill="#7A8399"/>
      <rect x="107" y="12" width="4" height="96" fill="#2B2B2B"/>
      <path d="M36 112 L184 112 L162 140 L58 140 Z" fill="#2B2B2B"/>
      <path d="M14 152 Q30 144 46 152 T78 152 T110 152 T142 152 T174 152 T206 152"
            fill="none" stroke="#2B2B2B" stroke-width="2.5" stroke-linecap="round"/>
    </svg>
    """

    override func draw() {
        background(Color(hex: 0xF7F5F1))
        textSize(17)
        guard let art = SVG(data: Data(boat.utf8)) else { return }

        let titles = ["as authored", "as dots", "as hatching"]
        for i in 0 ..< 3 {
            let r = Rectangle(x: 68 + Double(i) * 260, y: 60, width: 230, height: 190)
            noFill()
            stroke(soft)
            strokeWeight(2)
            drawRect(r)

            let fitted = art.fitted(in: r.inset(by: .all(20)))
            switch i {
            case 0:
                drawSVG(fitted)
            case 1:
                noStroke()
                fill(ink)
                for contour in fitted.contours {
                    for point in contour.resampled(spacing: 5).points {
                        drawCircle(center: point, radius: 1.5)
                    }
                }
            default:
                noFill()
                stroke(ink)
                strokeWeight(1.1)
                for (k, shape) in fitted.shapes.enumerated() {
                    let hatch = Hatching(spacing: 4.5, angle: 0.5 + Double(k) * 0.7)
                    for line in hatch.lines(filling: shape) {
                        drawPolyline(line)
                    }
                }
                strokeWeight(1.8)
                for contour in fitted.contours {
                    if contour.isClosed {
                        drawPolygon(contour.points)
                    } else {
                        drawPolyline(contour.points)
                    }
                }
            }

            noStroke()
            fill(faint)
            textAlign(.center, .top)
            drawText(titles[i], r.x + r.width / 2, r.y + r.height + 14)
        }

        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("imported, the picture becomes geometry", width / 2, 288)
    }
}
