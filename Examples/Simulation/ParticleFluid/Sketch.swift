import Ollin

/// A box of water made of particles: a hanging block lets go, splashes, and settles
/// into a pool you can grab with the mouse. Each particle measures how crowded it is,
/// crowding becomes pressure, and pressure pushes neighbors apart; a second short-range
/// pressure keeps particles from clumping and pulls stray drops into beads. The
/// `SpatialHash` finds every particle's neighbors on the GPU, so the whole pool runs in
/// real time.
///
/// Drag to grab the water and fling it. The parameters change the liquid itself: stiffness
/// is how hard it resists squeezing, viscosity how syrupy it moves, bounce how lively
/// the walls are.
@main
final class ParticleFluid_Example: Sketch {
    var fluid: ParticleFluid!

    @Param(60_000 ... 600_000, icon: "gauge.with.needle") var stiffness = 240_000.0
    @Param(0.0 ... 0.4, icon: "drop") var viscosity = 0.12
    @Param(0.0 ... 0.9, icon: "arrow.uturn.down") var bounce = 0.25

    override func setup() {
        fluid = makeParticleFluid(count: 26_000, radius: 12)
    }

    override func draw() {
        fluid.stiffness = stiffness
        fluid.viscosity = viscosity
        fluid.bounce = bounce

        background(Color(white: 0.03))
        if mouseIsPressed { fluid.pull(at: mouse) }
        blendMode(.add)
        updateParticleFluid(fluid)
        drawParticles(fluid)

        blendMode(.normal)
        drawCaption("Particle fluid · 26,000 particles · drag to grab the water")
    }
}
