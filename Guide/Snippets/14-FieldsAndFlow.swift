// The names Chapter 14's prose establishes around its fragments.
// See Guide/AUTHORING.md, "The code in the prose".

// The region the contour and stream sections work over.
let frame = Rectangle(x: 0, y: 0, width: 1080, height: 1080)
let terrain: (Vector2) -> Double = { p in p.x * 0.001 }

// The flow field, and the crowd it carries.
let field = FlowField { p in p.x * 0.002 }
var particles: [Vector2] = []

// The scattered readings the interpolation section fits a surface through.
let anchors: [Vector2] = [.zero, Vector2(10, 10)]
let inks: [Color] = [.red, .blue]
let samples: [Vector2] = [.zero, Vector2(10, 10)]
let readings: [Double] = [0, 1]

// The measurements the fitting section is chasing.
let marks: [Vector2] = []
