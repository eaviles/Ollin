// The names Chapter 28's prose establishes around its fragments.
// See Guide/AUTHORING.md, "The code in the prose".
import Foundation
import OllinPhysics

// The world every fragment steps, and a point in it.
let world = World3D()
let p = Vector3(0, 2, 0)

// The windmill and the gear train.
let hubCenter = Vector3(0, 3, 0)
let tower = world.addBody(.box(width: 0.4, height: 2.9, depth: 0.3),
                          at: Vector3(0, 1.45, -0.5), kind: .static)
let cross = world.addBody(.cylinder(height: 0.2, radius: 0.32), at: hubCenter)
let wall = world.addBody(.box(width: 6, height: 4, depth: 0.25), at: .zero, kind: .static)
let smallHub = Vector3(-1.95, 2, 0)
let bigHub = Vector3(0.15, 2, 0)
let small = world.addBody(.cylinder(height: 0.3, radius: 0.7), at: smallHub)
let big = world.addBody(.cylinder(height: 0.3, radius: 1.4), at: bigHub)
let bigHinge = world.connect(wall, big, .revolute(at: bigHub, axis: .unitZ))
let pinionRadius = 0.8
let barCenter = Vector3(0.15, 1.09, 0.45)
let bar = world.addBody(.box(width: 3.6, height: 0.22, depth: 0.22), at: barCenter)

// The contacts, the sensor, and the queries.
struct Knock { var at: Vector3; var strength: Double }
var knocks: [Knock] = []
let ball = world.addBody(.sphere(radius: 0.2), at: p)
let hoopCenter = Vector3(0, 3, 0)
var score = 0
let lamp = Vector3(-4, 5, 0)
let crate = world.addBody(.box(width: 1, height: 1, depth: 1), at: .zero)
var lit = false
let overhead = Vector3(0, 6, 0)
let patrol = Vector3(0, 0, 0)
let blast = Vector3.zero
let muzzle = Vector3(0, 1, -5)
let target = Vector3(0, 1, 5)

// Bodies with a setting of their own.
let balloon = world.addBody(.sphere(radius: 0.4), at: p)
let feather = world.addBody(.box(width: 0.2, height: 0.02, depth: 0.1), at: p)

// The track, the pulley, the mount, and the cable.
let rails = world.addBody(.box(width: 1, height: 0.1, depth: 1), at: .zero, kind: .static)
let cart = world.addBody(.box(width: 0.4, height: 0.3, depth: 0.6), at: p)
let points = [Vector3(-3, 1, 0), Vector3(0, 1, 3), Vector3(3, 1, 0), Vector3(0, 1, -3)]
let tray = world.addBody(.box(width: 0.8, height: 0.1, depth: 0.8), at: Vector3(-1, 1, 0))
let counterweight = world.addBody(.box(width: 0.4, height: 0.4, depth: 0.4), at: Vector3(1, 1, 0))
let trayTop = Vector3(-1, 1.05, 0)
let leftHook = Vector3(-1, 4, 0)
let rightHook = Vector3(1, 4, 0)
let weightTop = Vector3(1, 1.2, 0)
let post = world.addBody(.cylinder(height: 2, radius: 0.1), at: Vector3(0, 1, 0), kind: .static)
let platter = world.addBody(.cylinder(height: 0.1, radius: 1), at: Vector3(0, 2, 0))
let top = Vector3(0, 2, 0)
let pole = world.addBody(.cylinder(height: 4, radius: 0.1), at: Vector3(0, 2, 0), kind: .static)
let kite = world.addBody(.box(width: 1, height: 0.05, depth: 1), at: Vector3(0, 6, 2))
let poleTop = Vector3(0, 4, 0)
let kiteNose = Vector3(0, 6, 1.5)
let mast = Tensegrity.tower(levels: 3, struts: 3, radius: 0.46, levelHeight: 0.95)

// The ground from a landscape, and the saved heap.
let land = Heightfield(columns: 2, rows: 2, values: [0, 0, 0, 0])
let terrain = land
let island = world.addBody(.heightfield(land, width: 14, depth: 14, height: 4.2),
                           at: .zero, kind: .static)
let file = URL(fileURLWithPath: "heap.physics")
func buildTheHeap() {}
let saved = world.snapshot()
