// The names Chapter 29's prose establishes around its fragments.
// See Guide/AUTHORING.md, "The code in the prose".
import Foundation
import OllinPhysics

// The world, and the character the first step walks.
let world = World3D()
var walker = world.addCharacter(radius: 0.3, height: 1.8, at: Vector3(0, 2, 0))
var stride = 0.0
let lookout = world.addBody(.box(width: 2, height: 0.2, depth: 2),
                            at: Vector3(0, 3, 0), isSensor: true)

// The car, one of its wheels, and the machine on tracks.
var car = try! world.addVehicle(.box(width: 1.8, height: 0.7, depth: 4),
                                at: Vector3(0, 2, 0),
                                wheels: [.wheel(at: Vector3(0.9, -0.15, 1.3))])
let wheel = car.wheels[0]
var crawler = car

// The figure and its ragdoll, then the cloth and what is made from it.
var figure = Scene()
var ragdoll = try! world.addRagdoll(from: figure)
var cloth = try! world.addSoftBody(from: .plane(width: 3, depth: 3, segments: 24))
var ball = cloth
var banner: SoftBody3D? = cloth
let gust = 4.0
let sheet = Mesh.plane(width: 0.8, depth: 1.15, segments: 16)
let bannerMesh = Mesh.plane(width: 5, depth: 2.4, segments: 16)
var cape = cloth
var chain = try! world.addRope(through: [Vector3(0, 0, 0), Vector3(0, -1, 0)])
var raft = cloth
let saved = world.snapshot()
func splash(at point: Vector3, size: Double) {}
let contact = world.contacts[0]
