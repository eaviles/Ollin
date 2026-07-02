import Ollin

/// The fluent `Visual` chain surface: an animated image built by chaining a
/// source through warps, color moves, and modulations, the whole expression
/// compiling into a single GPU pass. Sine bands fold into a six-wedge
/// kaleidoscope, an evolving noise field melts the result per pixel, and an
/// animated cellular layer adds as sparkle; every number below can animate
/// (or hang off an `@Param`) without recompiling the shader.
@main
final class VisualSynth_Example: Sketch {
    override func draw() {
        drawVisual(
            .oscillator(frequency: 24, speed: 1.2, colorShift: 0.35)
                .kaleidoscope(6)
                .displaced(by: .noise(scale: 2.5, speed: 0.25), amount: 0.12)
                .rotated(time * 0.05)
                .blended(with: .voronoi(scale: 8, speed: 0.4)
                                    .contrast(1.5)
                                    .tinted(Color(hex: 0x3346FF)),
                         .add, amount: 0.3)
                .saturation(1.3)
        )
    }
}
