// The names Chapter 24's prose establishes around its fragments.
// See Guide/AUTHORING.md, "The code in the prose".

// The systems the chapter holds. All are built in `setup()`, so the chapter
// declares them optional and so does this.
var sand: Particles!
var mean: Accumulator!
var flow: AttractorFlow!
var life: ParticleLife!
var slime: Physarum!
var swarm: Swarm!
var lenia: ParticleLenia!
var fluid: ParticleFluid!
var blobs: SoftBodies!
var run: Evolution!
var chem: SwarmChemistry!

// The cities the ant colony tours.
let points = [Vector2(120, 160), Vector2(860, 240), Vector2(540, 620), Vector2(200, 900), Vector2(920, 840)]
