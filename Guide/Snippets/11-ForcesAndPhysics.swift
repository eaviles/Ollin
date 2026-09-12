// The names Chapter 11's prose establishes around its fragments.
// See Guide/AUTHORING.md, "The code in the prose".
import OllinPhysics

// The body the force section is pushing on.
var position = Vector2.zero
var velocity = Vector2.zero
let gravity = Vector2(0, 700)
let mass = 2.0
let gust = 40.0

// The 2D world the spring, tower, chain and drag sections all share.
let world = World()
let a = Particle(position: .zero)
let b = Particle(position: Vector2(10, 0))
let brickSize = Vector2(90, 30)
var bricks: [Body] = []
let i = 0
let previous = World().addBody(.circle(radius: 4), at: .zero)
let body = World().addBody(.circle(radius: 4), at: .zero)
let rows: [Color] = [.red, .white]
let hinge = Vector2.zero
var held: Joint?
let cursor = Vector2.zero

// The shape the fracture section breaks, and one of its pieces.
let outline = Shape([Vector2(0, 0), Vector2(100, 0), Vector2(100, 100), Vector2(0, 100)])
let hit = Vector2(50, 50)
let here = Vector2.zero
let piece = Shape([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10), Vector2(0, 10)])
