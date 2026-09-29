// figure: frame=200
//
// Guide payoff (Chapter 43): the live-coded set's final state, the chain all
// five evaluations built. Drifting oscillator bands folded five ways, melted
// by noise, posterized to a screen-print, set slowly spinning through the
// color wheel. Three of its numbers are parameters, which the set saves as
// cues and calls back; this is the look called back, at the values declared.
// Every value is animated, so the picture never sits still. The file is the
// chapter's listing.
import Ollin

final class Finale: Sketch {
    @Param(3...12) var segments = 5.0
    @Param(0...0.3) var bend = 0.09
    @Param(2...12) var levels = 6.0

    override func draw() {
        drawVisual(
            .oscillator(frequency: 11, speed: 0.6, colorShift: 0.5)
                .kaleidoscope(segments: segments)
                .displaced(by: .noise(scale: 3, speed: 0.25), amount: bend)
                .posterized(levels: levels, gamma: 0.75)
                .rotated(time * 0.03)
                .colorCycled(time * 0.04)
        )
    }
}
