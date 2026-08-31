// figure: frame=0
//
// Guide figure (Chapter 27): one staged reading from the phone's attention
// stream, drawn twice over. The salience query samples as a dot field (bigger,
// brighter dots where the picture pulls the eye), and the two regions the model
// picked out wear confidence-weighted frames, with a bead on the strongest one.
//
// The reading is staged rather than read, the way this chapter's other figures
// stage a depth camera: the same PhoneSaliency a phone fills in, built by hand
// from a PhoneSaliencySample so the figure renders anywhere.
import Foundation
import simd
import Ollin
import OllinPhone

final class AttentionAsHeat: Sketch {
    override var canvasSize: CanvasSize { .size(880, 520) }

    let glowColor = Color(hex: 0xFFC46B)
    let frameColor = Color(hex: 0x7FE0D4)

    static let heatWidth = 44
    static let heatHeight = 26

    /// A staged reading: two soft peaks of attention written into the heat
    /// plane (a strong one on the lamp, a weaker one on the poster), and the two
    /// regions the model would report around them.
    static func stagedReading() -> PhoneSaliency {
        // The wire's heat rows run from the top of the upright picture down, so
        // a peak is placed by turning its lower-left-normalized center over.
        var heat = [UInt8](repeating: 0, count: heatWidth * heatHeight)
        func addPeak(cx: Double, cy: Double, spread: Double, strength: Double) {
            for row in 0..<heatHeight {
                for col in 0..<heatWidth {
                    let x = (Double(col) + 0.5) / Double(heatWidth)
                    let y = 1 - (Double(row) + 0.5) / Double(heatHeight)
                    let d2 = (x - cx) * (x - cx) + (y - cy) * (y - cy)
                    let value = strength * exp(-d2 / (2 * spread * spread))
                    let i = row * heatWidth + col
                    heat[i] = UInt8(min(255, Double(heat[i]) + value * 255))
                }
            }
        }
        addPeak(cx: 0.30, cy: 0.62, spread: 0.09, strength: 1.0)
        addPeak(cx: 0.74, cy: 0.40, spread: 0.07, strength: 0.55)

        return PhoneSaliency(PhoneSaliencySample(
            isTracked: true, timestamp: 0,
            heatWidth: heatWidth, heatHeight: heatHeight, heat: heat,
            regions: [
                PhoneSalientRegionSample(x: 0.18, y: 0.47, width: 0.24, height: 0.30,
                                         confidence: 0.92, hasWorldCenter: true,
                                         worldCenter: SIMD3<Float>(-0.6, 1.4, -1.8)),
                PhoneSalientRegionSample(x: 0.64, y: 0.28, width: 0.20, height: 0.24,
                                         confidence: 0.48),
            ]))
    }

    let reading = stagedReading()

    override func draw() {
        background(Color(hex: 0x0D1017))

        // The stand-in for the camera frame: a letterboxed panel with the two
        // things the staged attention lands on, a bright lamp and a dim poster.
        let rect = Rectangle(fitting: Vector2(4, 3), in: canvasRectangle.inset(by: .all(24)))
        noStroke()
        fill(Color(white: 0.10))
        drawRect(rect, cornerRadius: 14)
        fill(Color(hex: 0xF5E9C9).withAlpha(0.9))
        drawCircle(rect.x + rect.width * 0.30, rect.y + rect.height * 0.38, 34)
        fill(Color(hex: 0x39465E))
        drawRect(Rectangle(x: rect.x + rect.width * 0.66, y: rect.y + rect.height * 0.48,
                           width: rect.width * 0.16, height: rect.height * 0.24),
                 cornerRadius: 6)

        // The salience query as a dot field: one sample per cell, the dot's size
        // and ink following the pull under it. This is the same surface a sketch
        // reads to drive stippling or particles.
        let columns = 52, rows = 30
        for row in 0..<rows {
            for col in 0..<columns {
                let p = Vector2(rect.x + (Double(col) + 0.5) / Double(columns) * rect.width,
                                rect.y + (Double(row) + 0.5) / Double(rows) * rect.height)
                let pull = reading.salience(at: p, in: rect)
                guard pull > 0.02 else { continue }
                fill(glowColor.withAlpha(0.15 + 0.85 * pull))
                drawCircle(p.x, p.y, 1.5 + 6.5 * pull)
            }
        }

        // The regions the model reported, their frames weighted by its trust,
        // and a bead on the strongest one.
        for region in reading.regions {
            noFill()
            stroke(frameColor.withAlpha(0.4 + 0.6 * region.confidence))
            strokeWeight(2 + 3 * region.confidence)
            drawRect(region.bounds(in: rect), cornerRadius: 10)
        }
        if let strongest = reading.strongestRegion {
            let center = strongest.center(in: rect)
            noStroke()
            fill(.white)
            drawCircle(center.x, center.y, 7)
            noFill()
            stroke(glowColor)
            strokeWeight(2)
            drawCircle(center.x, center.y, 14)
        }

        drawCaption("AttentionAsHeat: salience(at:in:) sampled as a dot field, frames on the regions")
    }
}
