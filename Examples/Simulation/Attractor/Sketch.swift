import Ollin

/// A strange attractor as moving material rather than a still curve: a million
/// particles all integrating the same velocity field on the GPU, scattered through
/// empty space at the start and pulled onto the shape within a second or two, then
/// streaming along it forever.
///
/// The color is the speed each particle reached, which is what shows the structure:
/// the fast outer sweeps against the slow, crowded core. Press `space` to move to the
/// next system, and drag to look around it.
@main
final class Attractor_Example: Sketch {
    var flow: AttractorFlow!
    var which = 0

    @Param(0.1 ... 4, icon: "speedometer") var pace = 1.0
    @Param(0.3 ... 3, icon: "circle.fill") var dots = 1.0

    let systems: [(String, AttractorSystem)] = [
        ("Lorenz", .lorenz()),
        ("Aizawa", .aizawa()),
        ("Halvorsen", .halvorsen()),
        ("Thomas", .thomas()),
        ("Dadras", .dadras()),
        ("Rössler", .rossler()),
    ]

    override func setup() {
        flow = attractorFlow(count: 1_000_000, systems[which].1)
    }

    override func draw() {
        background(.black)
        // Additive, so where the orbit dwells the particles pile into light and where
        // it hurries they stay a thin haze. That density *is* the attractor's own
        // measure, not a shading choice.
        blendMode(.add)
        toneMap(.aces)

        // The flow measures its own middle and reach from the system it is running, so
        // the camera frames whichever one is up without a table of numbers per system.
        cameraShowcase(.autoOrbit(period: 40), target: flow.center, radius: flow.extent * 3.4)

        flow.speed = pace
        // The flow sizes its own dots against the attractor's reach; this only scales
        // that, so the knob means the same thing on a shape two units across and one
        // that is fifty.
        flow.size = flow.extent / 150 * dots
        updateAttractorFlow(flow)
        drawParticles(flow)

        blendMode(.normal)
        drawCaption("\(systems[which].0) · 1,000,000 particles · "
            + "space changes system, drag to look around")
    }

    override func keyPressed() {
        // Changing the system on the running flow keeps every particle where it is, so
        // one shape visibly reorganizes into the next rather than starting over.
        if key == " " {
            which = (which + 1) % systems.count
            flow.system = systems[which].1
        }
    }
}
