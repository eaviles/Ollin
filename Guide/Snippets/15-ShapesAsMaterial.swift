// The names Chapter 15's prose establishes around its fragments.
// See Guide/AUTHORING.md, "The code in the prose".

// The scatter, the outlines and the paths the chapter keeps editing. `wave` is
// a point list here and `Sketch.wave(_:amplitude:around:)` is a number, so the
// name has to be declared or it resolves to the method.
let dots: [Vector2] = [.zero, Vector2(10, 0), Vector2(0, 10)]
let wave: [Vector2] = [.zero, Vector2(10, 0), Vector2(20, 4)]
let waypoints: [Vector2] = [.zero, Vector2(10, 0), Vector2(20, 4)]
let samplePoints: [Vector2] = [.zero, Vector2(10, 0)]

let outline = Shape([Vector2(0, 0), Vector2(100, 0), Vector2(100, 100)])
let star = Shape([Vector2(0, 0), Vector2(80, 10), Vector2(40, 90)])
let emblem = Shape([Vector2(0, 0), Vector2(60, 0), Vector2(30, 60)])
// `shore` and `wall` are point lists, which is what the optics calls take.
let shore: [Vector2] = [Vector2(0, 0), Vector2(50, 8), Vector2(100, 0)]
let wall: [Vector2] = [Vector2(0, 0), Vector2(100, 0), Vector2(100, 20)]
let lamp = Vector2(30, -40)
let rays: [Ray2] = []
// `route` is a chain of clothoids, which is what carries `length`,
// `point(at:)` and the rest of the driving reads.
let route = clothoidSpline(through: [.zero, Vector2(90, 20), Vector2(180, 0)])
let curve: [Vector2] = [Vector2(0, 0), Vector2(50, 8), Vector2(100, 0)]
let mark = Vector2(10, 10)
let region = Shape([Vector2(0, 0), Vector2(60, 0), Vector2(30, 60)])
let shape = Shape([Vector2(0, 0), Vector2(60, 0), Vector2(30, 60)])
let triangle = Shape([Vector2(0, 0), Vector2(60, 0), Vector2(30, 60)])
let scatter: [Vector2] = [.zero, Vector2(10, 4), Vector2(4, 10)]
let sites: [Vector2] = [.zero, Vector2(10, 4), Vector2(4, 10)]
let points: [Vector2] = [.zero, Vector2(10, 4), Vector2(4, 10)]
let skeleton: [Contour] = []
let x = 0.0
