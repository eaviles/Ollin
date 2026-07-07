import Ollin

/// Stroke as shape: a drifting brush line becomes a real region. The wavy
/// path is stroked into a closed `Shape` (round caps, round joins), and that
/// region is then inset again and again, so contour bands run inside the
/// ribbon like growth rings in a slab of wood. None of this is stroke
/// rendering: every band is geometry you could hatch, combine, or export.
@main
final class InkRibbon: Sketch {
    override func draw() {
        background(Color(hex: 0xF2EDE3))

        // A slow S-curve that drifts with time.
        let points = (0 ... 60).map { i -> Vector2 in
            let t = Double(i) / 60
            let x = 120 + t * (width - 240)
            let y = height / 2
                + signedNoise(t * 2.1, time * 0.12) * 260
                + sin(t * .pi * 2) * 90
            return Vector2(x, y)
        }

        // The stroke, as a region.
        let ribbon = Contour(points, closed: false)
            .stroked(width: 150, join: .round, cap: .round)

        noStroke()
        fill(Color(hex: 0x2E4057))
        drawShape(ribbon)

        // Inset bands inside it.
        noFill()
        strokeWeight(2.5)
        var band = ribbon
        for i in 1 ... 7 {
            band = band.offset(by: -10, join: .round)
            stroke(Color(hex: 0xF2EDE3).withAlpha(i % 2 == 0 ? 0.9 : 0.45))
            for contour in band.contours {
                drawPolygon(contour.points)
            }
        }
    }
}
