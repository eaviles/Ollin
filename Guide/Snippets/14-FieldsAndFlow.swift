// The names Chapter 14's prose establishes around its fragments.
// See Guide/AUTHORING.md, "The code in the prose".

// One point on the plate, in its own 0…1 coordinates.
let u = 0.5
let v = 0.5

// The region the contour and stream sections work over.
let frame = Rectangle(x: 0, y: 0, width: 1080, height: 1080)
let terrain: (Vector2) -> Double = { p in p.x * 0.001 }

// The flow field the streamline fragments trace.
let field = FlowField { p in p.x * 0.002 }

// The scattered readings the interpolation section fits a surface through.
let anchors: [Vector2] = [.zero, Vector2(10, 10)]
let inks: [Color] = [.red, .blue]
let samples: [Vector2] = [.zero, Vector2(10, 10)]
let readings: [Double] = [0, 1]
