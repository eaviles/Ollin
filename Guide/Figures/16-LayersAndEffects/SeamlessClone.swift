// figure: frame=0 unstable
// Unstable is measured, not assumed: two back-to-back lossless renders of this
// sketch differ at the pixel level on a quiet machine, so the nondeterminism
// is in the render itself, not the JPEG encoder. Worth a real diagnosis one day.
//
// Guide figure (Chapter 16): a seamless clone. The patch on its own, pasted with
// the seam left in, and cloned so the join disappears.
import Ollin

final class SeamlessClone: Sketch {
    override var canvasSize: CanvasSize { .size(880, 386) }

    override func draw() {
        background(Color(hex: 0xF7F5F1))

        let tile = 268.0, gap = 12.0
        let left = (width - tile * 3 - gap * 2) / 2
        let labels = ["the patch", "pasted", "cloned"]

        textFont(.system)
        for index in 0 ..< 3 {
            let x = left + Double(index) * (tile + gap)
            let frame = Rectangle(x: x, y: 20, width: tile, height: tile)

            // A backdrop whose color changes smoothly across the tile, so there is
            // something for the patch to take on.
            let backdrop = renderTarget(width: Int(tile), height: Int(tile))
            withTarget(backdrop) {
                noStroke()
                for row in 0 ..< Int(tile) {
                    let t = Double(row) / (tile - 1)
                    fill(Color(red: 0.24 + t * 0.56, green: 0.32 + t * 0.20,
                               blue: 0.52 - t * 0.22))
                    drawRect(0, Double(row), tile, 2)
                }
            }

            // The patch: a flat slab of stones, the wrong color for anywhere it lands.
            let patch = renderTarget(width: Int(tile), height: Int(tile))
            withTarget(patch) {
                background(Color(white: 0, alpha: 0))
                noStroke()
                fill(Color(hex: 0x6F8A76))
                drawCircle(tile * 0.5, tile * 0.5, tile * 0.33)
                // The stones stay inside the ground disc, so the silhouette is a
                // clean circle. A rim with a sharp notch in it is a rim whose
                // correction has to turn a corner, and the field that answers it
                // spikes there.
                for i in 0 ..< 70 {
                    let a = Double(i) * 2.39996
                    let r = tile * 0.30 * (Double(i) / 70).squareRoot()
                    let p = Vector2(tile * 0.5 + cos(a) * r, tile * 0.5 + sin(a) * r)
                    let reach = tile * 0.33 - (p - Vector2(tile * 0.5, tile * 0.5)).length
                    fill(Color(hue: 0.32, saturation: 0.18,
                               brightness: 0.50 + noise(p.x * 0.03, p.y * 0.03) * 0.13))
                    drawCircle(p.x, p.y, min(9 + noise(Double(i) * 0.4) * 7, max(reach, 0)))
                }
            }

            noStroke()
            fill(Color(white: 0.06))
            drawRect(frame)
            switch index {
            case 0:
                drawImage(patch.image, in: frame)
            case 1:
                drawImage(backdrop.combined(with: patch, .seamlessClone(amount: 0)).image,
                          in: frame)
            default:
                drawImage(backdrop.combined(with: patch, .seamlessClone()).image, in: frame)
            }

            fill(Color(hex: 0x2B2B2B, alpha: 0.62))
            textSize(16)
            textAlign(.center, .top)
            drawText(labels[index], frame.x + frame.width / 2, frame.y + frame.height + 8)
        }
    }
}
