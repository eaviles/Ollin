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
// Bool → toggle, a ParamOption enum → menu, Color → color well, Palette → a
// strip of swatches, Ramp → a band with a handle per stop, Easing → a menu of
// the named curves. `group:` names an inspector section, `icon:` gives the row
// an SF Symbol, and `group: .folded("Advanced")` makes a section that starts
// closed behind a disclosure row (open it and it stays open for this sketch).
// Numeric value boxes scrub: drag across one to change it (Option = fine,
// Shift = coarse), or click to type.
//
// Under the live host, the button below the knobs writes the ones you turned
// into the @Param lines here, so a set you like survives the run. Copy the
// file somewhere of your own first if you would rather not edit this one.
//
// A knob can also be set from the command line, on any export path and on the
// window, so one render can differ without editing the file:
//
//   swift run Example-Live-Parameters --export keeper.png --param radius=40 --param paper=#101018

enum RingStyle: String, CaseIterable, ParamOption { case rings, dots, beads }

@main
final class Parameters: Sketch {
    @Param(10...375, icon: "circle.dashed", group: "Rings") var radius = 175.0
    @Param(1...12, icon: "circle.grid.2x2", group: "Rings") var rings = 5
    @Param(style: .segmented, icon: "sparkles", group: "Rings") var style: RingStyle = .rings
    @Param(x: 0...1080, y: 0...1080, style: .pad,
           icon: "arrow.up.and.down.and.arrow.left.and.right",
           group: "Rings") var anchor = Vector2(540, 540)

    @Param(0...4, icon: "speedometer", group: "Motion") var speed = 1.0
    @Param(icon: "wind", group: "Motion") var breathe = true
    // A curve is a value like any other: this one spaces the rings, tight at
    // the ends and open in the middle, or the other way about.
    @Param("Spacing", icon: "chart.line.uptrend.xyaxis", group: "Motion")
    var spacing: Easing = .linear

    @Param(icon: "paintpalette", group: "Look") var paper: Color = .white
    // A color each for the rings, and a gradient the dots read along.
    @Param(count: 2...8, icon: "swatchpalette", group: "Look")
    var inks = Palette(Color(hex: 0x1B1B1B), Color(hex: 0xE4572E), Color(hex: 0x2E86AB))
    @Param(count: 2...6, icon: "circle.lefthalf.filled", group: "Look")
    var fade = Ramp([Color(hex: 0xE4572E), Color(hex: 0x2E86AB)])
    @Param(0.5...12, step: 0.5, icon: "lineweight", group: "Look") var weight = 2.5
    @Param(icon: "character.cursor.ibeam", group: "Look") var caption = "rings"

    // Knobs worth having but not worth a first glance: a `.folded` group
    // starts closed behind its header, and opening it is remembered for this
    // sketch, so it stays how you left it.
    @Param(0...30, icon: "waveform.path", group: .folded("Advanced")) var jitter = 0.0
    @Param(-2...2, step: 0.25, icon: "arrow.clockwise", group: .folded("Advanced")) var orbit = 0.0

    override func draw() {
        background(paper)
        strokeWeight(weight * scale)

        for i in 0..<rings {
            let t = Double(i) / Double(max(rings - 1, 1))
            let phase: Double = time * speed + t * .tau
            let swell: Double = breathe ? sin(phase) * 30 : 0
            let wobble: Double = jitter > 0 ? (noise(t * 4, time * 0.4) * 2 - 1) * jitter : 0
            let r: Double = (radius * (0.25 + spacing(t)) + swell + wobble) * scale

            switch style {
            case .rings:
                noFill()
                stroke(inks[i])
                drawCircle(anchor.x * scale, anchor.y * scale, r)
            case .dots, .beads:
                let count = style == .dots ? 48 : 12
                let dot = (style == .dots ? 2.0 : 6.0) * weight * scale
                fill(fade.color(at: t))
                noStroke()
                for j in 0..<count {
                    let a = Double(j) / Double(count) * .tau + time * (speed * 0.2 + orbit)
                    drawCircle(anchor.x * scale + cos(a) * r, anchor.y * scale + sin(a) * r, dot)
                }
            }
        }

        if !caption.isEmpty { drawCaption(caption) }
    }
}
