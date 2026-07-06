import Foundation
import Ollin

// Parameters: tunable knobs with @Param. Run it under the live host to get
// live controls in the inspector:
//
//   swift run OllinLive Examples/Live/Parameters/Sketch.swift
//
// Standalone (`swift run Example-Live-Parameters`) shows the same knobs in the
// inspector panel: View ▸ Show Inspector (⌘/).
//
// The control follows the property's type: Double → slider, Int → stepper,
// Bool → toggle, a ParamOption enum → menu, Color → color well. `group:` names
// an inspector section, `icon:` gives the row an SF Symbol. Numeric value
// boxes scrub: drag across one to change it (Option = fine, Shift = coarse),
// or click to type.

enum RingStyle: String, CaseIterable, ParamOption { case rings, dots, beads }

@main
final class Parameters: Sketch {
    @Param(10...375, icon: "circle.dashed", group: "Rings") var radius = 175.0
    @Param(1...12, icon: "circle.grid.2x2", group: "Rings") var rings = 5
    @Param(icon: "sparkles", group: "Rings") var style: RingStyle = .rings
    @Param(x: 0...1080, y: 0...1080, icon: "arrow.up.and.down.and.arrow.left.and.right",
           group: "Rings") var anchor = Vector2(540, 540)

    @Param(0...4, icon: "speedometer", group: "Motion") var speed = 1.0
    @Param(icon: "wind", group: "Motion") var breathe = true

    @Param(icon: "paintpalette", group: "Look") var ink: Color = .black
    @Param(0.5...12, step: 0.5, icon: "lineweight", group: "Look") var weight = 2.5
    @Param(icon: "character.cursor.ibeam", group: "Look") var caption = "rings"

    override func draw() {
        background(.white)
        noFill()
        stroke(ink)
        strokeWeight(weight * scale)

        for i in 0..<rings {
            let t = Double(i) / Double(rings)
            let phase: Double = time * speed + t * .tau
            let swell: Double = breathe ? sin(phase) * 30 : 0
            let r: Double = (radius * (0.25 + t) + swell) * scale

            switch style {
            case .rings:
                drawCircle(anchor.x * scale, anchor.y * scale, r)
            case .dots, .beads:
                let count = style == .dots ? 48 : 12
                let dot = (style == .dots ? 2.0 : 6.0) * weight * scale
                fill(ink)
                noStroke()
                for j in 0..<count {
                    let a = Double(j) / Double(count) * .tau + time * speed * 0.2
                    drawCircle(anchor.x * scale + cos(a) * r, anchor.y * scale + sin(a) * r, dot)
                }
                noFill()
                stroke(ink)
            }
        }

        if !caption.isEmpty { drawCaption(caption) }
    }
}
