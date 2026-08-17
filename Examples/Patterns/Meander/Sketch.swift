import Ollin

/// Meandering river: a channel migrates across the plain, its bends deepening
/// and sliding downstream, pinching off into crescent oxbow lakes that fade
/// away. Every thirty steps the channel's position is recorded, and those
/// scars are drawn as colored ribbons under the water, so the picture becomes
/// a map of everywhere the river has ever been.
///
/// The generator is a stateful stepper held across frames: `centerline` is
/// the river now, `oxbows` the lakes it abandoned, `scars` the recorded past.
/// Seeded, so the same seed always runs the same river.
@main
final class MeanderSketch: Sketch {
    private let parchment = Color(hex: 0xF2ECDD)
    private let water = Color(hex: 0x2C4A6E)
    private let waterCore = Color(hex: 0x7FA8C9)
    private let scarInks = [Color(hex: 0xC26D3F), Color(hex: 0x8A9B68),
                            Color(hex: 0xC7A94F), Color(hex: 0x71486E),
                            Color(hex: 0x9A4A4A), Color(hex: 0x3E7C66)]

    // The line starts far off-canvas to the left: bends slide downstream as
    // they grow, so the canvas is a window on the middle of a longer river,
    // with developed meanders flowing in from upstream.
    private let river = Meander.line(from: Vector2(-700, 620),
                                     to: Vector2(1160, 480),
                                     seed: 7, width: 26, recordEvery: 40)

    override func setup() {
        river.oxbowShrink = 0.004   // let the lakes linger
        river.maxScars = 60
    }

    override func draw() {
        river.step(2)
        background(parchment)

        // The scars, oldest first: one ribbon per recorded channel, each
        // keeping its ink for life, fading up toward the present.
        noFill()
        strokeWeight(river.width * 0.7)
        for (index, scar) in river.scars.enumerated() {
            let recency = Double(index + 1) / Double(river.scars.count)
            stroke(scarInks[index % scarInks.count].withAlpha(0.08 + 0.2 * recency))
            drawPolyline(scar)
        }

        // The abandoned lakes: crescents of still water along the old channel.
        stroke(waterCore.withAlpha(0.8))
        strokeWeight(river.width * 0.8)
        for oxbow in river.oxbows {
            drawPolyline(oxbow.points)
        }

        // The river itself: a wide band of water with a lighter core.
        stroke(water)
        strokeWeight(river.width)
        drawPolyline(river.centerline)
        stroke(waterCore.withAlpha(0.45))
        strokeWeight(river.width * 0.4)
        drawPolyline(river.centerline)
    }
}
