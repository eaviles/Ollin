import Ollin

/// Swarm chemistry: every particle carries its own copy of the rule it moves by, and on
/// contact one copy overwrites the other. There is no generation boundary and nothing is
/// being scored. A recipe spreads because the particles holding it keep meeting particles
/// holding something else and winning, which turns out to be enough.
///
/// Six random recipes start out sharing the population equally. Color is the recipe
/// itself (cohesion, alignment and separation as red, green and blue), so a takeover is
/// visible as one color eating the others, and a mutation as a shift in shade rather
/// than a new color. Watch the tally: it usually ends with one line holding almost
/// everything, but which one is not decided in advance.
///
/// `competition` is what "winning" means, and it is the whole character of the run.
/// Turn transmission off and the recipes freeze, leaving the plain mixture of kinds the
/// model started as.
///
/// The six opening recipes are rolled from this sketch's `variation`, so every launch is
/// a different contest. Like Particle Life's matrix, most rolls are unremarkable and a
/// few are alive, and the interesting stretch is while several lines still hold ground:
/// once one has taken everything there is nothing left to decide. Step to another
/// variation for a fresh set.
@main
final class SwarmChemistry_Example: Sketch {
    var chem: SwarmChemistry!
    var tally: [Int] = []

    @Param(icon: "arrow.triangle.2.circlepath") var spreading = true
    @Param(icon: "trophy") var winner = SwarmChemistry.Competition.majority
    @Param(0 ... 1, icon: "sparkles") var mutation = 0.2
    @Param(0.01 ... 0.4, icon: "arrow.up.and.down") var mutationSize = 0.1

    override func setup() {
        chem = swarmChemistry(count: 4000, kinds: 6)
    }

    override func draw() {
        chem.transmits = spreading
        chem.competition = winner
        chem.mutationRate = mutation
        chem.mutationAmount = mutationSize

        // A translucent wipe rather than a hard clear: these particles move a few points
        // a step, so a still frame of dots shows density where the trails show movement.
        background(Color(white: 0.04).withAlpha(0.14))
        updateSwarmChemistry(chem)
        drawParticles(chem)

        // Reading the tally stalls on the GPU, so do it a few times a second, not every
        // frame.
        if frameCount % 20 == 0 { tally = chem.lineageCounts() }
        drawTally()
    }

    /// The scoreboard the model never keeps for itself: how many particles each of the
    /// six opening lines still holds.
    private func drawTally() {
        guard !tally.isEmpty else { return }
        let total = max(tally.reduce(0, +), 1)
        let barWidth = 220.0, barHeight = 14.0, gap = 6.0
        let x = 40.0
        var y = height - 40 - (barHeight + gap) * Double(tally.count)
        textSize(13)
        for (line, held) in tally.enumerated() {
            let share: Double = Double(held) / Double(total)
            let hue: Double = Double(line) / Double(tally.count)
            let labelX: Double = x + barWidth + 8
            let labelY: Double = y + barHeight - 2
            noStroke()
            fill(Color(white: 0.22))
            drawRect(x, y, barWidth, barHeight)
            fill(Color(hue: hue, saturation: 0.6, brightness: 0.95))
            drawRect(x, y, barWidth * share, barHeight)
            fill(Color(white: 0.75))
            drawText(String(held), labelX, labelY)
            y += barHeight + gap
        }
        drawCaption("Swarm chemistry · 4,000 particles, 6 opening recipes · who is left")
    }
}
