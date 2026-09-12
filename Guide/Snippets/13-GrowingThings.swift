// The names Chapter 13's prose establishes around its fragments.
// See Guide/AUTHORING.md, "The code in the prose".

// Each grower the chapter holds while it runs.
let lattice = ShapeGrammar(start: [], rules: [])
let cluster = DiffusionLimitedAggregation(seeds: [.zero], seed: 7)
let bolt = DielectricBreakdown(seeds: [.zero],
                               in: Rectangle(x: 0, y: 0, width: 100, height: 100), seed: 7)
let field = CrackGrowth(width: 128, height: 128, seed: 7)
let river = Meander.line(from: Vector2(0, 10), to: Vector2(100, 10))
let sample = Image(width: 8, height: 8)
