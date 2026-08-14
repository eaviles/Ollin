#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Simulation](./README.md) → `Physics3D`</sup>

---

## 3D physics

Rigid bodies live inside the 3D scene. Crates stack and topple, balls roll, chains swing, all with real contact response. This is the spatial sibling of the [2D physics world](Physics.md)'s rigid side, and it keeps the same shape. Build a [`World3D`](#world3d) once, add [`Body3D`](#body3d)s, step it each frame, and draw each body from its pose. It lives in the same satellite, so `import OllinPhysics` brings both.

Beside the bodies there are three things that aren't ones.

- A [`Character3D`](#characters) is a walking figure. You steer it from `draw()` rather than push it around with forces.
- A [`Vehicle3D`](#vehicles) is a chassis on sprung wheels you drive.
- A [`SoftBody3D`](#softbodies) is a mesh whose vertices are simulated, so it drapes and squashes.

The solver behind it is [Jolt Physics](https://github.com/jrouwe/JoltPhysics). It is vendored and wrapped the way Box2D backs the 2D side, and nothing of it leaks into the API.

```swift
import Ollin
import OllinPhysics

final class Crates: Sketch {
    let world = World3D()

    override func setup() {
        world.ground = 0                        // a static floor at y = 0
        for level in 0 ..< 6 {
            world.addBody(.box(width: 1, height: 1, depth: 1),
                          at: Vector3(0, 0.5 + Double(level) * 1.05, 0))
        }
    }

    override func draw() {
        background(.black)
        cameraShowcase()
        world.step(dt: deltaTime)
        for body in world.bodies {
            withBody(body) { drawBox(width: 1, height: 1, depth: 1) }
        }
    }
}
```

A leaning tower of crates settles into a stable stack. `withBody(_:)` moves the 3D transform stack to a body's position and orientation, so whatever the block draws rides the body.

Distances are the 3D scene's world units, y-up, matching the camera. The solver thinks in meters. It is happiest with bodies roughly 0.1…10 units across, which is the scale the 3D examples already draw at. `unitsPerMeter` rescales the bridge if your scene is built larger.

### Contents

- [World3D](#world3d) - the simulation, its ground, and the per-frame `step`
- [Body3D](#body3d) - a rigid body: pose, velocity, forces
- [Motion knobs](#motion) - which ways a body may move, its own gravity, checking its path
- [Collider3D](#collider3d) - the shape catalog
- [Compound bodies](#compound) - several shapes fused into one body
- [Terrain and scenery](#terrain) - heightfield ground and `Scene` colliders
- [Joints](#joints) - hinges, ball-and-sockets, rods, welds, sliders
- [Motors, limits, and springs](#motors) - powered hinges and sliders, travel stops, springy ends
- [Tracks, ropes, and freedoms](#morejoints) - a path to ride, a pulley, and the general joint
- [Gears and racks](#links) - one joint driving another
- [Contacts](#contacts) - what hit what this step, and how hard
- [Sensors](#sensors) - regions that detect without colliding
- [Collision groups](#groups) - saying that two kinds of thing never touch
- [Queries](#queries) - rays, shape sweeps, and overlaps: asking the world what is there
- [Characters](#characters) - a walking figure you steer from `draw()`
- [Vehicles](#vehicles) - a chassis on sprung wheels you drive from `draw()`
- [Tracks](#tracks) - the same machine on two bands, turning without steering
- [Ragdolls](#ragdolls) - a skinned figure given weight, limp or powered
- [Soft bodies](#softbodies) - cloth that drapes and closed shapes that squash
- [Ropes](#ropes) - a line of particles on rigid rods, each carrying an orientation
- [Cloth a figure carries](#carriedcloth) - a cape on a skeleton: what is held, what hangs
- [Water](#water) - buoyancy: what floats, how deep it sits, and what carries it
- [Saving and loading](#snapshots) - keeping an arrangement you like, and putting it back
- [Reading physics from a file](#importing) - picking up `UsdPhysics` bodies and joints authored elsewhere
- [Grabbing with the mouse](#grabbing) - ray-picking and dragging bodies through the camera
- [Drawing bodies](#drawing) - `withBody` and matching meshes to colliders

<a name="world3d"></a>

### World3D

```swift
let world = World3D()
world.gravity = Vector3(0, -9.8, 0)   // the default: earth, pulling down y
world.ground = 0                      // optional static floor at a y level
world.bounce = 0.2                    // default restitution (ground + bodies)
world.step(dt: deltaTime)             // once per frame
```

`ground` is a wide static slab whose top face sits at the given level. `nil`, the default, lets bodies fall forever. `step(dt:)` clamps to `maxTimestep`, which is 1/30 s, so a stalled frame can't launch the scene. It runs one collision pass per ~60 Hz of simulated time.

Bodies and joints are managed the way the 2D world manages its own:

```swift
let crate = world.addBody(.box(width: 1, height: 1, depth: 1),
                          at: Vector3(0, 4, 0),
                          kind: .dynamic,        // .static / .kinematic
                          rotated: 0.4, axis: .unitY,
                          density: 1, friction: 0.5, restitution: nil)
world.remove(crate)      // removes its joints too
world.removeAll()
```

`density` is relative, where 1 is the default material and heavier shoves lighter. `friction` runs 0 slick … 1 grippy. `restitution` defaults to the world's `bounce`.

<a name="body3d"></a>

### Body3D

A body's pose is where you read it and drive it:

```swift
body.position                 // Vector3, get/set
body.rotationAngle            // radians about…
body.rotationAxis             // …this unit axis (read them together)
body.setRotation(.pi / 4, axis: .unitZ)

body.velocity                 // units per second, get/set
body.angularVelocity          // radians per second about each axis
body.mass                     // from collider volume × density (0 when static)
body.kind                     // switch .dynamic / .static / .kinematic live
body.friction                 // 0 slick … 1 grippy, get/set
body.restitution              // how much speed survives a bounce, get/set
body.isAwake                  // settled bodies sleep until touched

body.applyForce(Vector3(0, 40, 0))      // steady, accumulated for next step
body.applyImpulse(Vector3(2, 0, 0))     // instantaneous kick
body.applyTorque(Vector3(0, 5, 0))      // spin about each axis
```

`userData` is a free slot for whatever the sketch wants to hang off a body, such as its color or its mesh. `collider` keeps the shape the body was created with, so a drawing loop can match a mesh to it without a parallel array.

<a name="motion"></a>

### Motion knobs

Three things a body can be told about its own motion, each available when it is added and settable live afterward.

```swift
let coin = world.addBody(.cylinder(height: 0.1, radius: 0.4), at: p,
                         freedom: .plane(),        // stays flat
                         gravityScale: 0.4,        // falls lazily
                         checksPath: true)         // never tunnels

coin.freedom = .upright                            // all three are live
coin.gravityScale = -0.2
coin.checksPath = false
```

**`freedom`** is which of the six directions the body may use. Three of them travel along a world axis, and three turn about one. Everything is free by default.

```swift
.all                        // the default
.plane()                    // travels in x and y, turns about z: a flat world
.plane(normal: .unitY)      // travels in x and z, turns about y: a top view
.upright                    // travels any way, turns only about up, never tips
.noTurning                  // slides and is shoved, never spins
.noMoving                   // spins where it is, never travels
[.moveX, .turnZ]            // or spell out whatever fits
```

`.plane()` is the 2.5D lever. A sketch drawn side-on stays flat however hard things hit each other. Everything else about the world carries on in three dimensions, including lighting, shadows, solid drawing, and the whole collider catalog. A locked direction is one the solver gives the body infinite mass along, so **nothing** can move it that way. Not gravity, not a contact, not a joint, not a velocity you set yourself. Only whole world axes can be taken away, so `.plane(normal:)` rounds its normal to the nearest axis. There is no tilted plane. An empty set would leave a body no freedom at all, which the solver cannot express, so it reads as `.all`. To hold a body still, set `kind = .static` instead.

**`gravityScale`** is how hard this one body answers the world's gravity. `1` is as everything else, `0` is weightless, and a negative value makes the body rise.

```swift
balloon.gravityScale = -0.3
feather.gravityScale = 0.15      // falls a sixth as far in the same second
```

**`checksPath`** sweeps the body's shape along its whole path each step instead of only testing where it ends up. It is off by default, and worth turning on for anything small and quick. A fast body can cover more than its own width between two steps. It is then in front of a thin wall at one step and past it at the next, having never touched it.

```swift
let pellet = world.addBody(.sphere(radius: 0.05), at: muzzle, checksPath: true)
pellet.velocity = Vector3(0, 0, 120)
```

It costs nothing while the body is slow. The check only runs once a body covers a good fraction of its own size in a step. An ordinary throw lands on exactly the same spot either way. What it does cost is a little honesty about speed. A body that hits something at pace gives up the rest of its step where it struck. (This is continuous collision detection, under a name that says what it does.) Two neighbours have their own answer to the same problem and need nothing turned on. A `Character3D` already tests its path as it walks, and a `Vehicle3D`'s wheels feel for the road by casting rays. So it is the chassis, `vehicle.body.checksPath`, that would want it if anything did.

<a name="collider3d"></a>

### Collider3D

The local shape of a body, centered on its origin. Position and orientation come from the body.

```swift
.sphere(radius: 0.5)
.box(width: 1, height: 0.6, depth: 0.8)
.capsule(height: 0.8, radius: 0.2)      // straight section + rounded caps, y axis
.cylinder(height: 0.8, radius: 0.3)     // flat caps, y axis
.taperedCapsule(height: 0.8, topRadius: 0.15, bottomRadius: 0.3)   // a club
.taperedCylinder(height: 0.8, topRadius: 0.1, bottomRadius: 0.3)   // a frustum
.cone(height: 0.8, radius: 0.3)         // base down, apex up, matches drawCone
.hull([Vector3])                        // convex hull of at least 4 points
.mesh(mesh)                             // exact triangles; static bodies only
.heightfield(land, width: 14, depth: 14, height: 4)   // terrain; static, see below
.compound([.part(...), .part(...)])     // several shapes as one body, see below
```

The upright shapes all stand along the body's y axis, so rotate the body to orient them. Their `height` matches the matching draw call (`drawCapsule`, `drawCylinder`, `drawCone`), so the mesh call takes the collider's own numbers. The tapered pair slope between two radii. A `taperedCylinder` keeps flat caps, where equal radii make a plain cylinder and a zero top radius is exactly `.cone`. A `taperedCapsule` rounds both ends with caps of different sizes, and both radii must be positive. A `.mesh` collider is for scenery, such as a loaded set piece or an exact sculpted form. It has no volume for mass, so a dynamic body created with one is pinned in place. Moving shapes want `.hull`, a primitive, or a `.compound` of them.

<a name="compound"></a>

### Compound bodies

`.compound` fuses several colliders into one rigid body, such as a hammer, a table, or a windmill's blade cross. Each part is a child collider posed in the body's local space. The body's mass, balance, and inertia come from the whole assembly, so a lopsided tool tumbles the way a lopsided tool should.

```swift
let hammer = world.addBody(.compound([
    .part(.capsule(height: 0.9, radius: 0.06)),          // the handle
    .part(.box(width: 0.3, height: 0.14, depth: 0.14),
          at: Vector3(0, 0.52, 0), density: 8),          // the head, leading the swing
]), at: Vector3(0, 3, 0))
```

`.part(_:at:rotated:axis:density:)` places any collider at a position and rotation inside the body. Everything defaults to "at the origin, unrotated", so a single offset part is also how you shift a shape off its body's origin. A part's `density` is relative and multiplies the body's own, which is what makes the hammer's head heavy against its handle. Parts can nest, a compound inside a compound, and they should be solid shapes. A `.mesh` or `.heightfield` part pins the body in place, the same as using one bare.

Draw a compound the way it was built. `withBody` poses the whole body, then translate and rotate to each part's pose and draw its shape. The [`3D/Physics/Windmill`](../../Examples/3D/Physics/Windmill/) example does exactly that with a small recursive helper.

<a name="terrain"></a>

### Terrain and scenery

`.heightfield` turns a [`Heightfield`](../Generators/Terrain.md) into solid ground, sized exactly like its `mesh(width:depth:height:)`. That is a `width` × `depth` grid centered on the body's origin, with each sample lifted to `height · value`. Collider and drawn mesh trace one surface, so what rolls matches what renders:

```swift
let land = Heightfield.diamondSquare(size: 257, roughness: 0.55, seed: 7)
    .eroded(.hydraulic(), seed: 7)
world.addBody(.heightfield(land, width: 14, depth: 14, height: 4),
              at: .zero, kind: .static)
drawMesh(land.mesh(width: 14, depth: 14, height: 4))   // the same numbers
```

The field is resampled onto a square power-of-two grid for the solver, so any grid shape works. That grid is at least the source resolution, and it is capped at 1024 samples per side. Beyond the field's edges there is nothing, and bodies roll off into the void. Like `.mesh`, a heightfield can only be static.

For scenery that arrives as a file, one call colliders a whole [`Scene`](../3D/Scenes.md):

```swift
let hall = loadScene("hall.usdz")!
world.addStaticColliders(from: hall)
```

It walks the node tree and adds one static mesh body per mesh node. The node's world transform is baked into the triangles, nested groups and authored rotations and scales included. Colliders take each mesh as authored, at rest, so skins and morph targets aren't posed. `friction:` and `restitution:` apply to all of them, and the scene itself keeps drawing through `drawScene(_:)`.

<a name="joints"></a>

### Joints

`connect` links two bodies with a `Joint3D`. Anchors and axes are world coordinates at the moment of connecting.

```swift
world.connect(door, frame, .revolute(at: hingePoint, axis: .unitY))
world.connect(link, next, .ball(at: meetingPoint))
world.connect(a, b, .distance(from: pa, to: pb))          // a rod; stiffness < 1 softens
world.connect(a, b, .weld)                                // rigid at current pose
world.connect(carriage, rail, .prismatic(at: p, axis: .unitX))
```

`.ball` is the 3D-only kind, a ball-and-socket that rotates freely in every direction. It is the joint of hanging chains. A hinge (`.revolute`) allows rotation only about its axis. Cut any joint with `joint.remove()`.

`.swingTwist` is the ball-and-socket with limits, and the joint a body is made of. Give it the bone's direction. The bone may then lean away from where it started by at most `swing` radians in any direction, tracing a cone. It rolls about itself within `twist`:

```swift
world.connect(chest, upperArm,
              .swingTwist(at: shoulder, axis: Vector3(-1, 0, 0),
                          swing: 80 * .pi / 180, twist: -0.6...0.6))
```

A shoulder is a wide cone with a little twist, and a knee is a narrow one. `swing: 0` locks the bone straight, `.pi` frees it entirely. Its `angle` reads how far the joint is currently bent, and `friction` gives it the stiffness of an old hinge. It is what `addRagdoll` hangs every limb on.

Three more kinds do what none of these can.

- [`.path`](#morejoints) threads a body onto a track.
- [`.pulley`](#morejoints) runs a rope over two hooks.
- [`.allowing`](#morejoints) is the general joint written as the freedoms it keeps.

Two more link one joint to another, [gears and a rack and pinion](#links).

<a name="motors"></a>

### Motors, limits, and springs

Hinges and sliders can do more than swing free. Bound their travel, power them, and spring their stops. Together they make doors that close themselves, windmills that turn, and drawers that stop at the end of their rails.

**Limits** ride the joint kind. Both are measured from the pose at the moment of connecting (that pose is 0), so the range must straddle zero:

```swift
// A door that opens 100° one way from where it hangs now:
let door = world.connect(frame, panel,
    .revolute(at: hingePoint, axis: .unitY,
              limits: -0.01 ... (100 * .pi / 180)))    // radians; ±π at most

// A drawer that pulls out 2 units:
let drawer = world.connect(cabinet, tray,
    .prismatic(at: p, axis: .unitZ, limits: -0.01 ... 2))   // world units
```

**Motors** are two calls on the returned `Joint3D`, one per intent:

```swift
mill.drive(at: 2.5)          // constant rate: rad/s (hinge), units/s (slider)
door.drive(to: 0)            // seek a target angle / offset and hold it
door.stopMotor()             // cut power; the joint swings free again
```

`drive(to:)` is a spring servo. `frequency` is how fast it pulls, where 2 is a lazy door closer and 20 a snappy robot servo. `damping` at 1 settles clean, and lower overshoots and bounces. Both forms take `strength`, a cap on the motor's torque in N·m or force in N. The unlimited default just reaches its target. A small value gives the motor something to lose against, like a door closer a rolling ball can barge through:

```swift
door.drive(to: 0, frequency: 1.2, strength: 60)
```

Driving is stateful. Set it once and the motor keeps pulling every step until `stopMotor()` or a new `drive`. Where the joint sits right now reads back as `door.angle` in radians, or `drawer.offset` in world units. Both are 0 at the connect pose.

Two passive knobs finish the set:

```swift
hinge.friction = 80                          // drag torque/force when unpowered
gate.softenLimits(frequency: 3, damping: 0.5)   // springy end stops
```

`friction` is the stiff old hinge. It is a constant resistance the joint's motion must overcome while no motor is powering it. It is also what winds a spinning wheel down after `stopMotor()`. `softenLimits` swaps the hard stops for springs, so a gate thrown against its limit gives a little and bounces back. `frequency` 0 restores the wall. The other joint kinds have no axis to power, so the motor calls on a `.ball`, `.distance`, or `.weld` note once and do nothing. `.distance` has its own spring, the `stiffness` on the case.

A `.swingTwist` joint takes both motor calls too, and one more of its own. A single number about a joint that bends in every direction can only mean the roll about its own axis. So `drive(at:)` and `drive(to:)` run the twist and leave the bend alone. `joint.twist` reads that roll back, where `joint.angle` reads the bend. To point the bone somewhere, say so:

```swift
neck.drive(toward: (bird.position - head.position).normalized, frequency: 6)
neck.stopMotor()                                   // and it hangs again
```

`drive(toward:)` pulls the joint's axis onto a world direction, rolled `twist` radians about itself. It is clamped to the joint's own cone and twist limits, so aim past the cone and it leans as far as it may. Set it each frame to follow something.

<a name="morejoints"></a>

### Tracks, ropes, and freedoms

Three more kinds, each doing something no hinge or slider can.

**`.path` is a track.** Give it a ring of points. The second body is threaded onto the smooth curve through them, free to travel along it and nothing else. The rollercoaster car, the bead on a wire, the camera on a dolly rail:

```swift
let ride = world.connect(rails, cart,
                         .path(through: points, looping: true,
                               alignment: .followsPath))
ride.drive(at: 6)          // world units per second along the track
ride.drive(to: 0.5)        // or seek half way round and hold there
ride.progress              // 0 at the first point, 1 at the last
```

The curve is a spline *through* the points, not a polyline, so a handful of them describes a long track. The body joins it at the point nearest to wherever it already is, so place it on the track before connecting. `alignment` says how much of its turning the track takes over.

- `.free` leaves it tumbling.
- `.rolls` lets it spin only about the direction of travel.
- `.followsPath` banks it into every bend.
- `.fixed` holds the first body's orientation the whole way round.

The track belongs to that first body, so hanging it off a moving one carries the whole ride along. A flat `Contour` becomes a track on the ground in one call:

```swift
world.connect(ground, cart, .path(loop, atHeight: 0.3))   // contour y runs along world z
```

**`.pulley` is a rope over two hooks.** One end is on each body, and the total length is what ties them together, so one side rising is the other falling:

```swift
world.connect(tray, counterweight,
              .pulley(from: trayTop, over: leftHook,
                      and: rightHook, to: weightTop))
```

Read it as written, from the tray, up over the left hook, across to the right one, and down to the weight. `ratio` is how many falls of rope hold the second side. A ratio of 2 is a block and tackle, where that side moves half as far and lifts twice as much. A rope resists being pulled longer but not being let slack, which is what lets both ends drop together. `taut: true` makes it a rigid linkage instead, so lifting one end drives the other down. Both ends must be an ordinary or a static body. The solver reads a kinematic one wrongly, so that case is refused with a note. Move a static end instead.

**`.allowing` is the general joint, written as what it keeps.** Every other kind is a choice out of the six degrees of freedom a body has. When none of them fits, name the freedoms:

```swift
// A post a platter rides: it may rise and it may spin, and nothing else.
world.connect(post, platter,
              .allowing([.moveY, .turnY], at: top, travel: 0...1.4))
```

The freedoms are the same `Freedom3D` set a body's own [motion knobs](#motion) use, in world axes at the moment of connecting. `travel` bounds every direction it may move in, and `rotation` every axis it may turn about. Both are measured from the connect pose, and leaving either out runs it unbounded. `.allowing([])` is a weld, and `.allowing([.turnX, .turnY, .turnZ])` is a `.ball`. A single turn with a range is a hinge, which is a good way to see what the named kinds are made of.

<a name="links"></a>

### Gears and racks

The last two are links between *joints*, not bodies, because what they tie together is the motion those joints allow. Build each part's own joint first, then connect the joints:

```swift
let small = world.connect(frame, pinion, .revolute(at: hub, axis: .unitZ))
let big = world.connect(frame, wheel, .revolute(at: farHub, axis: .unitZ))
world.connect(small, big, .gear(teeth: 20, and: 36))
```

Turning either hinge now turns the other, in the opposite sense and at the ratio asked for. `.gear(ratio:)` says the same thing as a number, how many turns the first makes per turn of the second. It counts teeth and has no sign, so to make a pair turn the same way, flip one hinge's axis.

A rack and pinion ties a hinge to a slider, so turning drives sliding:

```swift
let rack = world.connect(frame, bar, .prismatic(at: p, axis: .unitX))
world.connect(big, rack, .rackAndPinion(travelPerTurn: 2 * .pi * pinionRadius))
```

`travelPerTurn` is how far the bar runs, in world units, for one full turn of the pinion. For a pinion of radius `r` rolling along the bar, that is its own circumference. A negative value runs the bar the other way.

Both links take a hinge as their first joint. The second is a hinge for a gear, or a slider for a rack and pinion, and anything else notes once and does nothing. Each joint's moving part is the body that is not static. When both can move, it is the second body it was connected with. That matches the order every `connect` call is written in, the frame first and the part that turns second. And because the shapes never touch, meshed wheels want to be told not to collide, or their plain cylinders will jam:

```swift
world.ignoreCollisions(between: "gears", and: "gears")
```

<a name="contacts"></a>

### Contacts

Touches are polled, not delivered. Each `step` fills `world.contacts` with everything that started or stopped touching during it, and `draw()` reads the list the way it reads mouse state:

```swift
world.step(dt: deltaTime)
for contact in world.contacts where contact.phase == .began {
    sparks.append(Spark(at: contact.point, size: contact.speed))
}
```

A `Contact3D` carries the pair, `a` and `b`, always in the same order and not "the one that moved". It also carries where they met (`point`), the `normal` pointing from `a` toward `b`, and `speed`, how fast they were closing when they met. `speed` is measured *before* the solver answers the collision, so it reads the force of the impact rather than what survived the bounce. That is what you want for the volume of a clink or the size of a spark. Two helpers save the "which one is mine" dance:

```swift
contact.involves(ball)          // is this ball in it?
contact.other(than: ball)       // what did it hit?
```

Contacts are per body **pair**. A crate resting on a mesh floor touches it along many triangles, and a compound body touches on several of its parts. Either way that is one `began` when it lands and one `ended` when it lifts.

An `ended` contact carries only the pair. By the time the solver notices a touch is over there is nothing left to measure, and the other body may already have been removed. So `point`, `normal`, and `speed` are zero there.

The two sides are typed `any Colliding3D`, not `Body3D`, because either may be a [soft body](#softbodies). A cloth is a real thing in the world that lands on floors and sails into sensors. But there is nothing to push it with and no single pose to read, and the type is what says so. `involves`, `other(than:)`, and `===` all work either way. Reach for the concrete kind when you want to act on it:

```swift
if let crate = contact.other(than: raft) as? Body3D {
    crate.applyImpulse(Vector3(0, 3, 0))    // only a solid takes one
}
```

Each body can be asked directly, out of the same list:

```swift
ball.contacts                   // this step's events involving this ball
ball.entered                    // bodies that started touching it this step
ball.exited                     // bodies that stopped
ball.touching                   // everything it is in contact with right now
ball.isTouching(floor)
```

The floor from `world.ground` is a body too, just not one in `bodies`. Nothing added it, and a drawing loop shouldn't have to skip a 1000-unit slab. It answers to `world.groundBody`, so a landing is recognisable:

```swift
if contact.other(than: ball) === world.groundBody { thud() }
```

`touching` has one thing worth knowing. The solver lets a settled body sleep, and a sleeping body stops reporting contacts. So a stack that has come to rest reads as touching nothing. That is the right answer for events, since nothing is happening, and a surprising one for occupancy. When the question is "what is resting in this region", use a sensor, which stays awake.

<a name="sensors"></a>

### Sensors

A sensor is a region rather than a solid: things pass straight through it, and it reports them.

```swift
let goal = world.addBody(.cylinder(height: 0.5, radius: 1), at: hoopCenter,
                         isSensor: true)

// in draw(), after step:
score += goal.entered.count           // balls that crossed this step
let inside = !goal.touching.isEmpty   // one is crossing right now
```

Sensors push nothing and are pushed by nothing, so a ball falls through one exactly as it would through empty air. A sensor can also share space with solid geometry. The hoop above is a solid rim of beads with a sensor disc filling the ring. The rim is what a ball clatters off, and the sensor is the hole.

A sensor sets its own motion. It is kinematic and never sleeps, whatever `kind` was asked for. So it goes on reporting bodies that have settled and fallen asleep inside it. That is what makes a tray or a pressure plate work:

```swift
let tray = world.addBody(.box(width: 3, height: 0.7, depth: 3),
                         at: Vector3(0, 0.55, 0), isSensor: true)
let load = tray.touching.count        // still right once they doze off
```

Because it never falls, a sensor stays where it is put. Move one by setting its `position`. To make a detector follow something, drive it from that body's pose each frame. Sensors are also invisible to `body(under:in:)` and `grabBody(at:in:)`, so the cursor's ray looks straight through them to the solid scene behind.

Sensors detect *moving* bodies, dynamic and kinematic, and not static scenery or each other. So a trigger volume laid over the ground doesn't spend every step reporting the ground.

<a name="groups"></a>

### Collision groups

Everything in a world collides with everything else. A **collision group** is a name you put things in. The world can then be told that two of those names pass straight through each other.

```swift
let bead = world.addBody(.sphere(radius: 0.2), at: p, group: "beads")
world.ignoreCollisions(between: "beads", and: "glass")
```

That is the whole surface, `group:` wherever a thing is made, and one sentence per rule. The rule is a fact about a pair rather than a direction. So there is no way to say that beads ignore the glass and forget that the glass ignores beads. `allowCollisions(between:and:)` withdraws a rule, and `collides(_:with:)` reads one back.

**Everything starts in `.default`, and naming a group is not itself a rule.** A world nobody has written a rule for behaves exactly like a world with no groups. A group only means something once something has been said about it. That is why a group name is a plain string and needs no declaring.

**A group collides with itself** until told otherwise, so two crates in one group still stack. Saying it twice is how confetti falls through its own drift:

```swift
world.ignoreCollisions(between: "confetti", and: "confetti")
```

**What a rule reaches.** A filtered pair is filtered everywhere the pair could have met.

- It never collides.
- It never reaches [`contacts`](#contacts).
- A [sensor](#sensors) in an ignored group never reports it.
- A [character](#characters) walks through it, including through another character.
- A [vehicle](#vehicles)'s wheels do not feel it under them.

Every kind of thing takes a group:

```swift
world.addBody(…, group: "phantoms")
world.addCharacter(…, group: "phantoms")
world.addVehicle(…, group: "traffic")
world.addRagdoll(from: figure, group: "phantoms")
world.addSoftBody(from: cloth, group: "drapes")
world.addStaticColliders(from: hall, group: "scenery")
```

and each of them can be moved between groups while it runs, through `body.group`, `character.group`, `vehicle.group`, `ragdoll.group`, and `softBody.group`. A rule written after things have already settled on each other still applies. The bodies are woken so the solver looks at the pair again.

A figure's own limbs are kept from fighting each other by a separate mechanism that groups never touch. So two ragdolls in one group still collide with each other exactly as they should.

**Asking as a group.** Every [query](#queries) takes `as:`. It asks the question the way a body of that group would ask it, looking straight through whatever that group passes through:

```swift
world.ignoreCollisions(between: "bullets", and: "glass")

world.raycast(from: muzzle, to: target)                  // stops at the pane
world.raycast(from: muzzle, to: target, as: "bullets")   // goes through it
```

A query with no `as:` is asked in `.default` and sees the whole world.

**The bookkeeping.** A world holds `World3D.maxCollisionGroups` groups, which is 64. Naming more keeps the extras in `.default` rather than quietly aliasing them onto a group already in use. `world.collisionGroups` lists the ones it knows in the order they were named, which is how a misspelled name is found. A typo is a *new* group, and a rule written about it does nothing.

Worked example: `Examples/3D/Physics/Sieve` sorts three colors of bead down one ramp, with the sorting itself being three `ignoreCollisions` calls.

<a name="queries"></a>

### Queries

`contacts` reports what the solver noticed while it stepped. A **query** asks it something it was never asked, between steps. It asks what is along this line, what a shape would run into, or what is inside this region right now. All of them answer immediately, none of them changes anything, and none needs a body built to ask with.

Every answer is a `Hit3D`.

- `body` is what it ran into. It is typed `any Colliding3D`, since it may be a [soft body](#softbodies).
- `point` is where the query touched it.
- `normal` is the outward surface direction there.
- `distance` is how far along the query the touch was, from a ray's start, or how far a swept shape travelled.

**Rays.** `raycast(from:to:)` returns the nearest body along a segment, `raycastAll(from:to:)` every body along it, nearest first.

```swift
// line of sight: the crate is visible when the crate is what the ray found
let visible = world.raycast(from: lamp, to: crate.position)?.body === crate

// a ground probe: how far down the floor is
let drop = world.raycast(from: p, to: p - Vector3(0, 20, 0))?.distance
```

A ray is a segment, not an infinite line, so it reaches exactly as far as `to`. For a direction and a reach, pass `to: p + direction * reach`.

**Sweeps.** `sweep(_:from:to:)` slides a collider along a line without turning it and returns the first thing it runs into (`sweepAll` returns them all). A ray asks what is in the way. A sweep asks whether something *fits*. That is what a clearance probe, a camera that must not end up inside a wall, or a step a character is about to take actually needs.

```swift
// hold 1.5 units above whatever passes below, crates included
let below = world.sweep(.sphere(radius: 0.4), from: overhead,
                        to: overhead - Vector3(0, 12, 0))
let height = (below?.point.y ?? 0) + 1.5
```

`rotated:`/`axis:` turn the probe, which changes what fits (a wide, thin box goes through a narrow gap edge-on and not flat). A sweep that sets off already touching reports `distance` 0. `mesh` and `heightfield` colliders describe scenery rather than a probe, and they cannot be swept or overlapped with. Use a hull, a compound, or a primitive.

**Overlaps.** `bodiesOverlapping(_:at:)` returns the bodies inside a shape placed in the world, in a stable order. There is one entry per body, however many of its parts are inside. `bodiesContaining(_:)` is the same question for a bare point.

```swift
for caught in world.bodiesOverlapping(.sphere(radius: 4), at: blast) {
    guard let body = caught as? Body3D else { continue }   // only a solid takes one
    body.applyImpulse((body.position - blast).normalized * 12)
}
```

A [sensor](#sensors) answers the same question *continuously* from a body that exists in the scene, which is what a pressure plate or a goal wants. An overlap answers it once, anywhere, with a shape that never existed.

**What a query sees.** Solid bodies, static scenery and the `ground` slab included. It also sees the ones the world keeps out of `bodies`, a character's stand-in and a ragdoll's limbs. So a walking figure can be spotted through `character.body`. **Soft bodies** are in there too. A hanging sheet stops a sightline the way a wall does, and the hit names the `SoftBody3D`. One thing is deliberately transparent, a **sensor**, since a detector volume is a region to be inside rather than a surface to hit. Pass `includingSensors: true` to have them reported too. `ignoring:` takes anything to look straight through, which is how something casts from inside itself, or through a curtain:

```swift
let ahead = world.raycast(from: robot.position, to: target,
                          ignoring: [robot])
```

`as:` narrows it the other way, by [collision group](#groups) rather than by naming bodies.

Queries cost nothing but the search. Asking does not step the world, so a per-body sight check every frame is an ordinary thing to write.

<a name="characters"></a>

### Characters

A `Character3D` is a walking figure. It is a capsule that goes where you steer it, climbs steps, and jumps. Walls stop it, and so do slopes too steep to hold it. It is not a rigid body. Nothing tumbles it and nothing knocks it over, which is exactly what you want for something a person drives. That is also why walking is a `draw()` poll rather than a pile of forces.

```swift
let world = World3D()
var walker: Character3D!

override func setup() {
    world.ground = 0
    walker = world.addCharacter(radius: 0.3, height: 1.8, at: Vector3(0, 2, 0))
}

override func draw() {
    var east = 0.0, south = 0.0
    if isKeyDown(.leftArrow)  { east -= 1 }
    if isKeyDown(.rightArrow) { east += 1 }
    if isKeyDown(.upArrow)    { south -= 1 }
    if isKeyDown(.downArrow)  { south += 1 }

    let heading = Vector3(east, 0, south)
    walker.move(heading.length > 0 ? heading.normalized * 3 : .zero)
    if isKeyDown(" ") { walker.jump() }

    world.step(dt: deltaTime)
    withCharacter(walker) { drawCapsule(radius: 0.3, height: 1.2) }
}
```

`step(dt:)` sweeps every character forward along with the bodies, so there is no second update call to remember. `move(_:)` sets the horizontal velocity the character is *trying* to walk at, and holds it until changed. Falling and jumping are the world's business, so the vertical part is ignored. `jump(_:)` is granted only if the character is on the ground on the next step. Calling it every frame while a key is held therefore gives a hop each time it lands, rather than flight.

**Position is the feet.** `walker.position` is the point the capsule stands on, so a figure modeled standing at the origin lands where it should. `withCharacter(_:)` moves the 3D transform stack there and turns it by `facing`, the mirror of `withBody(_:)`.

#### What it can get past

Three settings decide what the geometry does to the character, and each has a visible edge:

| | what it means |
| --- | --- |
| `stepHeight` | The tallest step it walks up without jumping, 0.4 by default. A stair, a kerb, a ledge. Set it to `0` and the same stairs become a wall. |
| `maxSlope` | The steepest slope it can climb, in radians (50° by default). A steeper face still holds it up, but it can't get any further up. |
| `pushStrength` | The hardest it can shove a dynamic body sideways, in newtons (100 by default). At `0` crates become immovable walls to walk around. |

`stepHeight` is the distance the character probes upward, not a hard ceiling. The capsule's rounded foot rides the edge a little first, so a ledge somewhat taller than the setting may still be climbed. Give it a clear margin rather than tuning to the exact centimetre.

Whether a push actually shifts something is a contest between `pushStrength` and what the body weighs. A 4 kg crate on an ordinary floor slides under the default 100 N. A 43 kg one doesn't, because ground friction alone asks for more than that. Make crates light if you want them scattered.

#### Reading it back

| | |
| --- | --- |
| `isOnGround` | Standing on ground it can walk on. The test to gate a jump, or to swap a walk cycle for a falling pose. |
| `groundState` | The full answer. `.onGround`, `.onSteepSlope` (held, but too steep to climb), `.notSupported` (touching something that can't hold it), `.inAir`. |
| `groundNormal` | The surface under its feet, to lean a drawn figure into a slope. |
| `groundBody` | What it is standing on, or `nil` in the air. A moving platform carries the character along with it. |
| `velocity` | What it is *trying* to do. Intent, including the fall and the jump. |
| `actualVelocity` | What the world let it do, measured from the ground actually covered. |

Those last two are the pair worth knowing. Walk into a wall and `velocity` still reads a full walking pace while `actualVelocity` reads nothing. So a walk cycle driven by `actualVelocity` stops its legs when the character stops moving:

```swift
let pace = Vector2(walker.actualVelocity.x, walker.actualVelocity.z).length
stride += pace * deltaTime * 3.4        // legs stall against a wall
```

#### Among the ordinary bodies

A character is swept through the world by hand rather than simulated as a body, so it isn't in the scene by itself. It carries a stand-in that is in the scene, `walker.body`, a kinematic `Body3D` moving inside the capsule. That is what makes the character visible to everything else in this page. Sensors see it walk in, `world.contacts` names it, and `body(under:in:)` can pick it:

```swift
if lookout.isTouching(walker.body) { /* standing on the platform */ }
```

The stand-in is deliberately kept out of `world.bodies`, the same way the ground slab is. A drawing loop over the bodies then doesn't render a capsule where the sketch draws its own figure. Its `position` is the stand-in's center, and `walker.position` reads the feet.

Teleport with `position`, which also re-reads what is underfoot on the spot, and `stop()` clears both the walking velocity and any speed carried from a fall. Characters collide with each other as well as with the scenery.

The worked example is [`3D/Physics/Stroll`](../../Examples/3D/Physics/Stroll/), an eroded island with stairs up to a lookout that lights as you arrive.

<a name="vehicles"></a>

### Vehicles

A `Vehicle3D` is a machine you operate rather than a body you push. It is a chassis carried on sprung wheels, with an engine and a gearbox behind the throttle. You set four numbers each frame and the wheels do the rest, finding their own grip on whatever they are rolling over.

```swift
let world = World3D()
var car: Vehicle3D!

override func setup() {
    world.ground = 0
    car = world.addVehicle(.box(width: 1.8, height: 0.7, depth: 4),
                           at: Vector3(0, 2, 0),
                           wheels: [
                               .wheel(at: Vector3( 0.9, -0.15,  1.3), steers: true),
                               .wheel(at: Vector3(-0.9, -0.15,  1.3), steers: true),
                               .wheel(at: Vector3( 0.9, -0.15, -1.3), driven: true, handBrake: true),
                               .wheel(at: Vector3(-0.9, -0.15, -1.3), driven: true, handBrake: true),
                           ])
}

override func draw() {
    car.throttle = isKeyDown(.upArrow) ? 1 : (isKeyDown(.downArrow) ? -1 : 0)
    car.steering = (isKeyDown(.rightArrow) ? 1 : 0) - (isKeyDown(.leftArrow) ? 1 : 0)
    car.handBrake = isKeyDown(" ") ? 1 : 0

    world.step(dt: deltaTime)

    withBody(car.body) { drawBox(width: 1.8, height: 0.7, depth: 4) }
    for wheel in car.wheels {
        withWheel(wheel) { drawCylinder(radius: wheel.radius, height: wheel.width) }
    }
}
```

`step(dt:)` hands each vehicle's controls to the solver along with everything else, so there is no second update call. **The vehicle drives along the chassis's local +z**, with +y up, so model whatever you draw facing that way. Positive `steering` turns it to its own right.

The chassis is an ordinary `Body3D`. `car.body` collides, takes impulses, reports contacts, and is in `world.bodies` like anything the sketch added. What makes it a vehicle is the constraint on top, which owns the wheels. Its weight is `mass`, 1500 kg by default, rather than the shape's volume. Its center of mass also drops to the height of the wheel mounts, which is what stops a car rolling over the first time it turns hard.

#### The controls

| | |
| --- | --- |
| `throttle` | The gas pedal, `-1…1`. Positive drives forward, negative reverses. |
| `steering` | Where the wheels point, `-1` hard left … `1` hard right. |
| `brake` | The brake pedal, `0…1`. It slows every wheel that has `brakeTorque`. |
| `handBrake` | `0…1`. It locks only the wheels with `handBrakeTorque`, which is what makes the back step out. |

All four hold until changed, so set them every frame. `drive(throttle:steering:brake:)` sets three at once and `coast()` lifts everything off.

Asking for the other direction while the vehicle is still rolling brakes first. It takes the new direction only once it has stopped, which is how a car with an automatic gearbox behaves. Press "back" at speed and you get the brakes. Press it again from a standstill and you reverse.

#### The wheels

A `Wheel3D` says where a wheel is bolted on and what it does. Build them, hand them over, and afterwards the same objects report where each wheel actually ended up:

```swift
let front = Wheel3D.wheel(at: Vector3(0.9, -0.15, 1.3), radius: 0.35, steers: true)
front.suspensionFrequency = 2.2       // a stiffer spring
front.grip = 0.4                      // and a slick tire
```

| | |
| --- | --- |
| `position` | Where the suspension is bolted to the chassis, in its local space. The wheel hangs `suspensionLength` below this. |
| `radius` / `width` | The tire. `width` is also the height of the cylinder you draw for it. |
| `steers` | Whether steering turns it, up to `maxSteerAngle` (30° by default). |
| `driven` | Whether the engine turns it. |
| `suspensionLength` / `suspensionTravel` | How far the wheel hangs with nothing pressing on it, and how much further up it can be pushed before the chassis takes the hit. |
| `suspensionFrequency` / `suspensionDamping` | The spring, in the same hertz-and-ratio pair a joint's `drive(to:frequency:damping:)` takes. Around 1.5 Hz is a road car, 3 and up feels every stone. |
| `brakeTorque` / `handBrakeTorque` | How hard each brake bites on this wheel, in newton-metres. Leave `handBrakeTorque` at zero on the front pair. |
| `grip` | Scales the tire's own friction, where `1` is normal and lower is slick. The ground's friction combines with it, so slippery ground still slides a grippy tire. |
| `casterAngle` | How far the fork is raked back. A car leaves it at `0`, and a two-wheeler needs a real rake (see below). |

**Wheels level with each other along the vehicle share an axle**, worked out from where they sit rather than the order you listed them. An axle with any driven wheel is turned by the engine, so marking one of a pair marks its pair. A lone wheel, as a two-wheeler's are, is an axle by itself. Each full pair is also tied by an anti-roll bar, which is what keeps the vehicle flat through a corner. That bar is `antiRollStiffness`, 1000 N/m by default, and `0` unties them.

Everything on a wheel can be changed while the vehicle drives, so a slider on the springs or the grip is felt on the next step. `driven` is the gearbox rather than the wheel, so it is the one that costs something. Changing it rebuilds the drive on the next step and re-gears it against whatever is now driven. Set the whole list, then step, then read the flags back to see what the drivetrain settled on:

```swift
for wheel in car.wheels { wheel.driven = wheel.position.z > 0 }   // front drive
world.step(dt: deltaTime)
```

#### The engine

Two numbers stand in for the whole drivetrain:

- **`engineTorque`** (500 N·m by default) is how hard the engine pulls. More of it spins the wheels sooner rather than accelerating harder, since grip is the ceiling, not power.
- **`topSpeed`** (30 units/s) is the gearing. Top gear at the engine's redline turns the driven wheels this fast. So it is a ceiling the vehicle approaches on a flat straight, rather than a promise. Winding it down gears the vehicle for pull instead of pace.

Both can be changed while driving. The gearbox shifts itself. `gear` reads which one it picked, `-1` reverse, `0` neutral, `1` first, and up. `rpm` reads how fast the engine is turning, which is what to drive an engine sound from.

#### Reading it back

| | |
| --- | --- |
| `speed` | How fast it is travelling along its own forward axis. Negative in reverse. |
| `forward` / `up` | The chassis's axes in world space. A chase camera wants `forward`, and `up` tips as the vehicle leans. |
| `isOnGround` | Whether any wheel is touching. `false` means nothing the driver does will change anything. |
| `wheel.center` | Where the wheel is now, suspension travel included. |
| `wheel.spin` / `wheel.steerAngle` | How far it has rolled and how far it is turned. |
| `wheel.isOnGround` / `wheel.groundBody` / `wheel.groundNormal` | What that tire is on. |
| `wheel.suspensionCompression` | `0` fully extended … `1` bottomed out. Watch a car squat under power and dive under braking. |
| `wheel.slip` / `wheel.slideAngle` | How much the tire is sliding along itself and across itself. Color a wheel by `slip` and a spinning one lights up. |

`withWheel(_:)` moves the 3D transform stack to a wheel's pose, steering and spin included, the way `withBody(_:)` does for a body. A tire modeled as a cylinder along +y lands right.

Two more knobs sit on the vehicle. `maxTilt` caps how far the chassis may lean from upright. It is `nil` by default, so the chassis rolls over like anything else, and around `.pi / 3` keeps a car on its wheels over rough ground. `wheelContact` picks how the wheels find the ground.

- `.cylinder`, the default, sweeps the tire's real footprint and is the steadiest over terrain.
- `.sphere` rounds off edges.
- `.ray` is a single cheap ray that can drop a narrow wheel into a gap it should have ridden over.

#### Two wheels

A two-wheeler is the same call with `balances: true`, which adds the controller that holds it up and leans it into turns. It needs one thing a car doesn't, a real `casterAngle` on the front wheel. The trail that comes with a raked fork is what lets it hold a line instead of flopping over at the first correction.

```swift
let front = Wheel3D.wheel(at: Vector3(0, -0.27, 0.75), radius: 0.31,
                          width: 0.05, steers: true)
front.casterAngle = 30 * .pi / 180
let back = Wheel3D.wheel(at: Vector3(0, -0.27, -0.75), radius: 0.31,
                         width: 0.05, driven: true)
let bike = world.addVehicle(.box(width: 0.4, height: 0.6, depth: 0.8),
                            at: Vector3(0, 1, 0), wheels: [front, back],
                            mass: 240, engineTorque: 150, topSpeed: 30,
                            centerOfMass: Vector3(0, -0.3, 0), balances: true)
```

Running dead straight, even an unbalanced two-wheeler stays up, because nothing tips it. The balancing shows the moment something does. Start it leaned over and it stands back up, and it leans into a corner rather than falling out of it.

The worked example is [`3D/Physics/Joyride`](../../Examples/3D/Physics/Joyride/), a car you drive over an eroded island, with the springs and the grip on live sliders.

<a name="tracks"></a>

### Tracks

`tracked: true` builds the same machine on two tracks. The wheels become road wheels, split into a left and a right band by **which side of the hull they sit on**. The three controls mean what they always did:

```swift
var wheels: [Wheel3D] = []
for side in [1.3, -1.3] {                       // +x is its left, -x its right
    for i in 0 ..< 5 {
        wheels.append(.wheel(at: Vector3(side, -0.28, -1.8 + Double(i) * 0.9),
                             radius: 0.44, width: 0.6))
    }
}
let crawler = world.addVehicle(.box(width: 2, height: 0.9, depth: 5.2),
                               at: Vector3(0, 1.2, 0), wheels: wheels,
                               mass: 4200, topSpeed: 9, tracked: true)!
```

Steering is the one that reaches the ground differently, because a track has nothing to turn. The number sets how much slower the inside band runs. Half lock stops it, so the machine turns about its own inside track. **Full lock runs it backwards, which spins the machine where it stands.** It needs throttle to do any of that, the way a real one does. The bands are turned by the engine, so with the engine idle there is nothing to run one against the other.

```swift
crawler.throttle = 1
crawler.steering = 1        // turn on the spot
```

`trackSpeed(.left)` and `trackSpeed(.right)` read how fast each band is running over the ground, in world units per second. They are equal in a straight line, differ through a turn, and run opposite ways in a pivot. So they are what to scroll a drawn track by. `wheels(on:)` gives one band's road wheels, front of the machine first, which is what a drawing loop walks to lay a track around them.

Most of a wheel means the same thing on a band. These do not:

| | |
| --- | --- |
| `driven` | Marks the **sprocket** its band is turned at, rather than one of a driven pair. With none marked, each band takes its rearmost wheel. |
| `brakeTorque` | Adds up over a band, so the whole band's brake is the sum of its wheels'. There is no separate hand brake, so `handBrake` pulls the same one. |
| `grip` | Scales a flat pair of friction coefficients rather than a tire's slip curves. This is why a track keeps pulling while it slides, and what lets one climb a bank that would leave a wheel spinning. |
| `steers` / `maxSteerAngle` / `casterAngle` | Inert. A road wheel never turns, and `steerAngle` always reads zero. |
| `slip` / `slideAngle` | Always zero. A road wheel only ever turns as fast as the band it rides, so it has no slip of its own to report. |

Everything else, the suspension especially, works exactly as it does on a wheel. A tracked machine takes `maxTilt`, `wheelContact`, `engineTorque`, and `topSpeed` unchanged. It cannot also `balance`, since a machine on tracks does not lean.

The worked example is [`3D/Physics/Crawler`](../../Examples/3D/Physics/Crawler/), a crawler working a quarry, with its bands drawn as links that scroll at the speed the solver reports.

<a name="ragdolls"></a>

### Ragdolls

A `Ragdoll3D` gives a skinned figure weight. Hand `addRagdoll(from:)` a loaded `Scene` that has a skin. It reads the skeleton, builds one rigid body per joint, and sizes each one from the part of the mesh that joint actually moves. Stepping the world then answers a question the animation cannot. Where do the limbs end up when the world has a say?

```swift
var figure: Scene!
var ragdoll: Ragdoll3D!

override func setup() {
    figure = loadScene("figure.gltf")!
    world.ground = 0
    ragdoll = world.addRagdoll(from: figure, at: Vector3(0, 3, 0))
}

override func draw() {
    world.step(dt: deltaTime)
    figure.apply(ragdoll)     // the pose the solver just found
    drawScene(figure)
}
```

`scene.apply(ragdoll)` is `apply(_:at:)` run backwards. Instead of a keyframe track posing the joints, the simulated bodies do. It is exact, because each limb's body stands *at* its joint rather than in the middle of the bone, so writing the pose back has nothing to undo. Everything downstream works as it always did, including skinning, morph targets, per-material parts, materials, shadows, and export.

The figure simulates in world space. So draw the scene without a transform of your own, if you want it to land where the bodies are.

**What the fit finds.** The shape of each limb comes from the mesh, not from bone lengths. The vertices a joint pulls hardest on are gathered in that joint's own frame, and a capsule is fitted along the direction they spread. A torso comes out thick and a forearm thin even though the two bones are a similar length. `ragdoll.limbs` reports what it found: `name`, `body`, `parent`, `collider`, and where the shape sits inside the body. `withLimb(_:)` poses the transform stack onto a limb's fitted shape, so you can draw the capsules beside the skin:

```swift
for limb in ragdoll.limbs {
    withLimb(limb) {
        if case .capsule(let height, let radius) = limb.collider {
            drawCapsule(radius: radius, height: height)
        }
    }
}
```

**Limp or powered.** Left alone, the joints have limits and nothing else. This is the figure that falls downstairs. `drive(toward:)` gives it back some will, growing a motor on every joint that pulls toward the pose a scene is currently holding:

```swift
target.apply(walk, at: time)          // where the animation wants the limbs
ragdoll.drive(toward: target, strength: effort)
world.step(dt: deltaTime)
figure.apply(ragdoll)                 // where they actually ended up
```

Keep the target scene and the drawn scene apart. A `Scene` is a value type, so a second copy is one assignment. A figure driven toward the scene it was just posed from has nowhere to pull. The pose it is chasing has to be re-established each frame.

`strength` is the most torque a joint may use, in newton-metres, and it is the expressive knob. High, and the figure will not be moved. Low, and heavy limbs sag out of the pose, which is how a figure reads as tired rather than switched off. `goLimp()` cuts the power. `pose(from:)` puts every limb back where a scene has it, which is how a figure is stood up again.

Nothing drives the root, so a powered figure still falls as a whole. The motors hold its *shape*, not its place. To keep one on its feet, make the root limb kinematic with `ragdoll.limbs[0].body.kind = .kinematic`, and it hangs from its hips like a puppet. Setting `ragdoll.kind = .kinematic` instead makes the whole figure follow the driven pose exactly, shoving whatever is in its way.

**Limits and joints.** Every joint is a `.swingTwist`, opened at the `swing` and `twist` the call was given and retunable one at a time while the figure hangs:

```swift
world.addRagdoll(from: figure, swing: 50 * .pi / 180, twist: -0.3...0.3)
ragdoll.limit("forearmL", swing: 10 * .pi / 180)     // an elbow, not a shoulder
```

A dense rig, a hand with twenty finger bones, does not need twenty bodies. Name the joints that should get one. The rest ride the nearest limb above them rigidly, keeping their pose and their share of the flesh:

```swift
world.addRagdoll(from: figure,
                 joints: ["hips", "spine", "chest", "head",
                          "armL", "forearmL", "armR", "forearmR",
                          "legL", "shinL", "legR", "shinR"])
```

**Among the other bodies.** A ragdoll's limbs are ordinary bodies. They collide, they turn up in `world.contacts`, and they can be picked and dragged with `grabBody(at:in:)`. They are kept out of `world.bodies`, since a sketch draws the figure's mesh rather than the capsules under it. `ragdoll.bodies` is the list. Each figure gets its own collision group, so a limb never fights the one it hangs off, while two figures collide normally. A thigh sits inside the pelvis, and the two simply ignore each other. `applyImpulse(_:)` shoves the whole figure at once, and `world.remove(ragdoll)` takes it and its limbs away together.

The worked example is [`3D/Physics/Ragdoll`](../../Examples/3D/Physics/Ragdoll/), a figure that stands and waves while its joints are powered, collapses when they are not, and can be dragged around by an arm either way.

<a name="softbodies"></a>

### Soft bodies

Everything above moves as one rigid piece. A **`SoftBody3D`** does not. Its state lives in its vertices, which are simulated particles held together by springs. So it drapes, folds, and squashes instead of turning up somewhere else with the same shape. Cloth and a beach ball are the two ends of the same idea.

Build one from any `Mesh`:

```swift
let cloth = world.addSoftBody(from: .plane(width: 3, depth: 3, segments: 24),
                              at: Vector3(0, 3, 0),
                              pinned: { $0.z < -1.4 })   // hung from one edge

// each frame:
world.step(dt: deltaTime)
fill(.crimson)
drawSoftBody(cloth)
```

`drawSoftBody(_:)` draws `softBody.mesh`, which is the source mesh with the simulation's positions and freshly derived normals. Everything else the mesh carried rides through untouched, so a textured sheet stays textured while it moves. Every renderer feature applies exactly as it does to any other mesh, materials, shadows, reflections, and export included.

**Coincident vertices merge into shared particles.** Ollin's mesh generators are flat shaded. Every triangle carries its own copies of its corners, so a generator mesh's triangles share no vertex index at all. `addSoftBody` welds by position first, so a `Mesh.box` becomes eight particles rather than twenty-four loose ones. `particleCount` reports what the simulation actually runs on. `positions` still comes back one per *source* vertex, in the source mesh's order.

**Pinning is how a cloth is hung.** The `pinned:` closure is handed each vertex of the mesh, in the mesh's own local space, and returns whether that particle is held in place. Pins can also be moved afterwards:

```swift
cloth.pin(index)          // hold this vertex where it is
cloth.unpin(index)        // hand it back to the simulation
cloth.isPinned(index)
cloth.move(index, to: point)   // carry it to a world point over this frame
```

`move(_:to:)` pins the particle if it was free and drives it there by velocity, so the sheet hanging off it is dragged along rather than snapped. `nearestVertex(to:)` finds the one nearest a world point.

**The knobs.** All of them are scale-free: the same number means the same thing on a handkerchief and on a marquee.

| | |
|---|---|
| `mass` | the whole body's weight in kilograms, split evenly between the particles |
| `stiffness` | resistance to *stretching*, `0` slack to `1` inextensible (the default) |
| `bend` | resistance to *folding*, `0` limp like fabric (the default) to `1` stiff like card |
| `pressure` | the gas inside a closed surface, in gravities of outward push |
| `damping` | how quickly particle motion bleeds away |
| `friction`, `bounce` | the surface against what it lands on |
| `iterations` | solver passes per step, and more is stiffer and steadier |
| `vertexRadius` | how far a particle's own body reaches past its position |

`stiffness` and `bend` are separate because they are separate. A bedsheet barely stretches at all and folds freely, which is `stiffness: 1, bend: 0`. `pressure` needs a closed surface to fill, so it does nothing on a sheet. `isClosed` reports which you have, and setting it on an open one notes once and is ignored. A `pressure` of `1` just holds the body's own weight up, and `2` to `4` reads as a firm ball that still dents. `pressure`, `iterations`, and `vertexRadius` are all live, so a ball can deflate while you watch.

**A pressurised shape with corners needs `bend`.** Gas pushes on every face at once, and nothing in a limp surface holds an authored angle. So a soft cube at `bend: 0` inflates into a pillow. Measured on a 1-unit cube, `pressure` alone leaves it holding a fifth more volume than it was built with, and the higher the pressure the rounder it gets. `bend: 1` brings it back to within a few percent of the shape you handed over. Round shapes do not show this, because round is what pressure is already trying to make. So use `bend: 0` for anything meant to read as a bag or a balloon, and `bend` up near `1` for anything meant to keep its own flat faces.

**Pushing one about.** Impulses, joints, and grabs do not apply to a soft body, because there is no single pose or velocity for them to act on. What works is `applyForce(_:)`, spread evenly over the particles, which is how wind is applied:

```swift
banner.applyForce(Vector3(0, 0, gust))
```

**Taking hold of one** is the soft-body twin of `grabBody`/`dragGrab`, and it works by pinning the particle under the cursor rather than adding a joint:

```swift
var grip: SoftGrip?

override func mousePressed() {
    grip = grabSoftBody(at: Vector2(mouseX, mouseY), in: world)
}
override func mouseReleased() {
    if let grip { releaseSoftGrab(grip) }
    grip = nil
}
// in draw(), before world.step:
if let grip { dragSoftGrab(grip, to: Vector2(mouseX, mouseY)) }
```

**A soft body is part of the world**, not a thing draped over it, so the rest of this page applies to one:

- **It turns up in `world.contacts`.** A cloth landing on a crate reports a `began` with a point and an approach speed, and an `ended` when it comes off, exactly like anything else. `cloth.touching`, `.contacts`, `.entered`, and `.exited` read the same lists a body's do, and a sensor sees a cloth sail into it. Two details are its own. A soft body has no one velocity at the moment its first particle lands, so `speed` is the speed the whole surface arrived at. And where a settled *pile of crates* drops its touches when it falls asleep, a settled cloth **keeps** its list. The solver stops asking a sleeping soft body who it is against, which is not the same as it having let go.
- **It floats.** [Water](#water) pushes each of its particles up on its own, and each particle rides the surface directly above it. A raft therefore follows the shape of a swell rather than one plane through its middle. What decides how high it rides is `density`, relative to the water's the same way a collider's is. A *closed* surface works its own out from the mass and the volume it holds, so a beach ball just floats. A sheet holds no volume to work one out from, so it starts as heavy as water, lying awash, and one line makes it a raft:

  ```swift
  raft.density = 0.3        // rides high; above 1 it sinks
  ```

  A sheet's area for its weight is enormous, which is exactly what drag measures. So a cloth heavier than water sinks slowly, and a floating one is carried along by a current rather than left behind by it.
- **A query can find it.** `raycast`, `sweep`, and the overlap calls all see soft bodies, so a hanging sheet blocks a sightline and a `Hit3D` may name a `SoftBody3D`. To look through one, name it in `ignoring:` or put it in a collision group the query does not ask as.

**What a soft body still cannot do.** The solver collides them with the rigid bodies around them, but not with each other and not with themselves. So a sheet folded double will pass through its own layers, which reads as a flicker where the two lie together. Impulses, joints, and grabs do not reach one, and `body(under:in:)` answers only for solids. Use `grabSoftBody(at:in:)` there. Tearing is not offered either. A real tear has to split a shared vertex in two and rebuild the surface, which the solver has no way to do while it runs.

**A soft body is a surface, not a filled solid**, and `pressure` is how it reads as full. There is no separate "jelly" model holding the space inside it, and that is a measured choice rather than a missing feature. A pressurised body already holds a weight without squashing, comes back from a dent perfectly, and costs nothing extra. Filling one with tetrahedra costs half again as many particles, and it comes back from a hard squash permanently out of shape. The reasoning and the numbers are in [`ARCHITECTURE.md`](../../ARCHITECTURE.md).

The worked examples are [`3D/Physics/Drape`](../../Examples/3D/Physics/Drape/) and [`3D/Physics/Raft`](../../Examples/3D/Physics/Raft/). Drape has a banner pegged to a washing line that flaps in a gusting wind, a sheet thrown over a crate, and a beach ball you can let the air out of. Raft has a cloth raft riding a swell with cargo on it, a sounding line that stops at her deck, and a harbour gate that reports her sailing through.

<a name="ropes"></a>

### Ropes

A soft body's shape is usually a surface. A rope's is a *curve*, and the difference runs deeper than one dimension. A rope is built from **rigid rods** rather than springs, and every rod holds an orientation of its own. That is what lets geometry ride it.

Build one from a polyline. Anything that makes points makes a rope, so hand it hand-placed points, a sampled `Path`, a `Contour`, a `randomWalk`, or a ridge off a `Heightfield`:

```swift
let rope = world.addRope(through: (0 ..< 40).map { Vector3(0, -Double($0) * 0.1, 0) },
                         at: Vector3(0, 3, 0),
                         thickness: 0.04,
                         pinned: { $0.y > -0.001 })       // hung from the top

// each frame:
world.step(dt: deltaTime)
drawSoftBody(rope)                                        // a tube along the rope
```

The points are the particles one for one, so `pin(_:)`, `move(_:to:)`, `positions`, and `nearestVertex(to:)` all speak in indices into the polyline you handed over. `drawSoftBody(_:)` sweeps a tube of `thickness` along it, which is also how far the rope stands off whatever it lies on.

**Two knobs shape it**, both scale-free. One setting means the same thing on a twig and on a mooring line.

- **`stiffness`** is how much it resists being *stretched*. `1` is a steel cable, measured on a rope hung under its own weight at about 1% longer than its rest length. `0.5` lets it stretch by nearly a third, and by `0.2` it has doubled, which is a bungee.
- **`bend`** is how much it resists being *bent and twisted*, and it is the one that decides what the rope is. `0` is limp rope. Around `0.5` a cantilevered length droops about a third of its own length, which reads as heavy cable. Near `1` it holds itself out like a stem or a branch.

A long, finely divided rope is the case where `iterations` matters. Stiffness propagates one rod per solver pass, so forty particles over six units needs about twenty passes before `bend: 1` is really rigid. Twenty particles is stiff at the default five.

`maxStretch:` works here exactly as it does on cloth, and is worth having on anything hung. It caps how far the rope may get from what holds it, measured along its own length, so a heavy rope stops creeping longer under load.

```swift
let chain = world.addRope(through: links, at: Vector3(0, 3, 0),
                          mass: 4, bend: 0.06,
                          pinned: { $0.y > -0.001 },
                          maxStretch: 1)                  // does not stretch at all
```

<a name="segments"></a>

#### Riding a rope

`rope.segments` is the rope read as rods rather than points. Each `RopeSegment` carries its `start` and `end`, its `center`, `direction`, and `length`. It also carries a `rotation`, held by the rod itself, which turns as the rope bends *and twists*. A chain of springs could never give you that.

`withSegment(_:)` stands the transform stack in the middle of a segment with **+y running along the rope**. That is the axis Ollin's cylinders, capsules, and cones stand on. A primitive drawn inside the block lies along the rope with no turning of its own. It is `withBody(_:)`'s twin:

```swift
for segment in vine.segments where segment.index % 3 == 1 {
    withSegment(segment) {
        translate(0.11, 0, 0)
        drawSphere(radius: 0.06)          // a leaf, carried and twisted by the stem
    }
}
```

The clearest use is a chain, where every other link is turned a quarter turn about the rope's own axis. That turn is only expressible because each rod knows how it is rolled:

```swift
for segment in chain.segments {
    withSegment(segment) {
        rotate(.pi / 2, axis: Vector3(1, 0, 0))       // lay the ring across the rope
        if segment.index.isMultiple(of: 2) {
            rotate(.pi / 2, axis: Vector3(0, 0, 1))   // roll every other link
        }
        drawTorus(radius: segment.length * 0.62, tube: 0.026)
    }
}
```

The tube `drawSoftBody(_:)` sweeps uses a twist-free frame of its own, so a rope wound up looks the same as one that is not. The twist lives in `segments`, which is where anything riding the rope should read it.

**What a rope shares with the rest of the tier.** It collides with the rigid bodies around it, turns up in `world.contacts` and in `touching`, and floats according to its `density`. It takes `applyForce(_:)` for wind, belongs to a collision group, sleeps when it settles, and is saved and restored by [`snapshot()`](#snapshots). Unlike a surface it needs no `assetName` to be saved. A rope's whole rest shape is a handful of points, so it carries itself.

**What it cannot do.** A rope does not collide with itself, so a coil passes through its own turns. It does not collide with another rope or cloth either, the same envelope as the rest of the tier. More particular to a rope, the shape a query asks about is built from a body's *faces*, and a rope has none. So `raycast`, `sweep`, and `bodiesOverlapping` all look straight through one. `grabSoftBody(at:in:)` still finds it, by taking the nearest particle to the line of sight. And a rope is one strand. There is no branching form, so a plant with several stems is several ropes.

**Hair and fur are ropes.** There is no separate hair simulation, and a rope is what to reach for instead. It is the same Cosserat rod maths a hair solver uses, and its knobs reach hair scale. A cantilever of 8 points spaced 25 mm apart droops about a quarter of its span at `bend: 0.5`, and about four fifths of it at `bend: 0.05`. Below roughly 10 mm of spacing `bend` stops making much difference, which is the practical floor. The cost to plan around is the count. Each rope is its own body, and `World3D(maxBodies:)` defaults to 4,096, so a few thousand strands is the working range. Measured on an M2, 2,000 strands of 8 points step in about 3.3 ms, and 4,000 in about 8.6 ms. Past that, simulate a sparse set of strands and draw several interpolated around each one, which is how hair is usually drawn anyway.

<a name="carriedcloth"></a>

### Cloth a figure carries

`pinned:` holds part of a surface still. A cape needs the other thing: part of it held to a figure that is *moving*, and the rest left to hang off that and swing. Say which joint of a skinned scene's skeleton carries each part of the cloth, and hand the simulation this frame's pose:

```swift
cape = world.addSoftBody(from: sheet, at: Vector3(0, 0.85, -0.13),
                         rotation: .pi / 2, axis: Vector3(1, 0, 0),
                         mass: 1.2, stiffness: 0.92,
                         pinned: { $0.z < -0.58 },        // clasped at the neck
                         skinnedTo: figure,
                         carriedBy: { _ in "chest" })

// each frame, after the figure is posed and before the world steps:
figure.apply(ragdoll)
cape.follow(figure)
world.step(dt: deltaTime)
```

**The pose the figure is standing in when you build the cloth is the bind pose.** Nothing has to be authored in a modelling tool, and no weights have to be painted. Hang the cloth where it belongs, name the joints, and every later pose is read as the motion since. `carriedBy:` is given a vertex in the mesh's own space, the same space `pinned:` reads. It answers with a joint's name, or `nil` for a part that is ordinary cloth. A name the skeleton does not have is skipped with a note. A typo therefore leaves that part hanging free, rather than silently doing something else.

**`pinned:` means held by whatever holds it.** A pinned vertex a joint carries is held to the *figure*. One no joint carries is held to the *world*, which is what it has always meant. So the same closure clasps a cape at the neck and pegs a banner to a line.

Three more numbers shape what the rest of it may do, and all three are **lengths in world units**, not ratios to be calibrated:

- **`sway:`** is how far a vertex may travel from where the skeleton puts it, given the same way `pinned:` is. `0` holds it exactly there, and `.infinity`, the default, leaves it free to swing. A leash of `0.05` really does hold every particle within 5 cm of its skinned position. Grading it, tight at the shoulders and loose at the hem, is how a mantle is told apart from a cloak. **Watch the sign** if you compute one, since a negative value clamps to `0` and hard-skins that part into a board.
- **`backStop:`** is how far *behind* the carried surface a particle may be pushed before it is held back out. It keeps a cape out of the back it hangs on without waiting for a collision. `0.04` is a few centimetres of clearance.
- **`maxStretch:`** caps how far any particle may get from what holds it, as a multiple of the distance measured *along the cloth*. `1` is inextensible, `1.05` allows 5%, and `nil`, the default, leaves the springs to it. This one is worth knowing about even for cloth no skeleton carries. A heavy sheet hung from one edge stretches under its own weight however stiff you make it, and a cap fixes it for almost nothing. Measured on a 2-unit sheet weighing 8 kg, the springs alone let it hang 6% long. `maxStretch: 1` hangs it at exactly its own length.

Two knobs work while it runs. **`swayScale`** multiplies every leash at once, so one slider lets a whole cape out. **`followsSkin`** turns the leashes off entirely, leaving only the parts held exactly on the skin still following. That is the way to let a cape go loose without rebuilding it.

**`follow(_:)` before `step(dt:)`, once a frame.** The solver eases the cloth from the previous pose to this one across the step. A second call in the same frame loses that, and a call after the step leaves the cloth a frame behind. **`snap(to:)`** is the other one. It puts every carried particle exactly where the skeleton says and stops it dead. That is what a figure that was *stood* somewhere rather than *moved* there needs, so the cloth arrives with it instead of being dragged across the room.

A carried cape is otherwise an ordinary soft body. It collides with the rigid world, floats, turns up in `world.contacts`, can be grabbed, and rides in a snapshot. A snapshot writes down what the closures decided, since it cannot carry the closures. Its own gap is the one every soft body has. **It does not collide with itself**, so a cape passes through its own folds and through any other cloth on the same figure.

The worked example is [`3D/Physics/Cape`](../../Examples/3D/Physics/Cape/), a figure striding with a cape clasped at the neck, which collapses with it when the figure goes limp.

<a name="water"></a>

### Water

A world can have water the same way it has ground. It is one property, and nothing opts in.

```swift
world.water = Water(level: 0)
```

Everything already in the world starts floating. What floats and what does not comes from the `density` each body was built with, measured against the water's. So it is a number you were already setting:

```swift
world.addBody(.box(width: 1, height: 1, depth: 1), at: Vector3(0, 4, 0),
              density: 0.3)   // a cork: rides with a third of it under
world.addBody(.box(width: 1, height: 1, depth: 1), at: Vector3(2, 4, 0),
              density: 3)     // a stone: goes to the bottom
```

The waterline is not something you tune. A body of density `d` settles with fraction `d` of itself submerged, because that is the volume it has to displace to hold its own weight up. A barrel at `0.5` floats half under, and one at `0.8` rides low with a fifth of it dry. `Water.density` is the same relative scale bodies use, where `1` is water. Raising it to `1.3` for brine floats every one of them higher without touching the bodies.

**The knobs.**

| | |
|---|---|
| `level` | the height of the still surface. Animate it for a tide, and bodies asleep at the old level wake and follow. |
| `density` | how heavy the water is, `1` being water and the default body material. |
| `linearDrag` | how hard it resists a body dragged through it. This is what makes something dropped in settle rather than bob for ages. |
| `angularDrag` | the same for turning, which is what stops a long shape rocking too long after it lands. |
| `flow` | a current, in units per second, that carries everything afloat along. |
| `waves` | a rolling swell, or `nil` for a flat calm. |

Drag is worth a moment because it is the difference between water and a trampoline. With `linearDrag: 0`, a crate dropped in oscillates about its waterline and never stops. The default `0.5` reads like water. It dips, comes back up, and settles within a second or two.

**A swell.** `Water.Waves` gives the surface a shape, and it carries whatever is riding it:

```swift
world.water = Water(level: 0, waves: Water.Waves(amplitude: 0.25,
                                                 wavelength: 8, speed: 1.5))
```

The same surface is available to draw, which is the point of `waterMesh`. It hands back the very surface the bodies are floating on, so the swell you see and the swell they ride cannot drift apart.

```swift
if let surface = world.waterMesh(extent: 40) {
    fill(Color(hex: 0x2C7C96))
    material(.dielectric(roughness: 0.3))
    drawMesh(surface)
}
```

`waterHeight(at:)` asks the same question for a single point, for sitting something exactly on the waterline. Both read the surface as it stands this frame. `world.waterPhase` is the clock behind it, if a shader needs to move in step.

**Riding higher than it should.** `Body3D.buoyancy` multiplies what the water would otherwise do to one body. `1` is what its density says, `2` floats it as though it were half as heavy, and `0` sinks it whatever it is made of. Reach for `density` first, and keep this for the one crate that has to bob higher than the rest.

**Cloth floats too.** A [soft body](#softbodies) is floated particle by particle, since it has neither the one mass nor the one shape the rigid path works from. Each particle rides the surface directly above it rather than a plane through the body's middle, so a raft follows the swell instead of being curled by it. Its own `density` decides how high it rides. A closed surface derives one from mass and volume, so a beach ball just floats. A sheet holds no volume to derive one from and starts at `1`, so `raft.density = 0.3` is what makes a sail into a raft. Drag bites much harder on cloth than on a crate, because a sheet's area for its weight is enormous. A heavy one sinks slowly, and a floating one is carried by a current rather than left behind by it.

**What the water leaves alone.** Sensors, static and kinematic bodies, and a character's capsule are not floated. A detector volume and a walking figure go where the sketch puts them, not where the water would. The water itself is an ocean rather than a pool. Everything below `level` is water, out to the horizon, so a container of water needs its own walls built from static bodies, which is all a harbour is.

One thing worth knowing about sleeping. A floating body settles at its waterline and then goes to sleep, which is what you want. It stops costing anything and holds its level exactly. If you move the water afterwards, by changing the level or any other setting, everything afloat is woken so it can follow. A swell wakes only what it actually washes over, which is why a stone that has sunk to the bottom stays asleep under a rolling sea.

The worked examples are [`3D/Physics/Flotsam`](../../Examples/3D/Physics/Flotsam/) and [`3D/Physics/Raft`](../../Examples/3D/Physics/Raft/). Flotsam has crates from cork to nearly waterlogged riding a swell at their own depths, a stone anchor on the bottom, and a current carrying the lot past. Raft is the same idea where the thing afloat is a cloth. Drag either about.

<a name="snapshots"></a>

### Saving and loading

Some arrangements are worth keeping. Think of a heap of stones that took four hundred steps to settle, a stack knocked into a shape you liked, or a scene you spent a minute nudging into place by hand. None of it can be written down as code, and running the simulation again does not give it back. `snapshot()` captures the whole world as it stands, and `restore(_:)` puts it back:

```swift
let settled = world.snapshot()      // after the pile has come to rest
// …knock it over, rummage through it…
world.restore(settled)              // exactly the pile you had
```

A `PhysicsSnapshot` is a value you can hold, hand around, and write to a file:

```swift
try world.save(to: url)             // = try world.snapshot().write(to: url)
world.load(contentsOf: url)         // false, and the world is untouched, if it can't be read
```

which is how a settled arrangement becomes an asset the sketch opens with:

```swift
override func setup() {
    world.ground = 0
    if !world.load(contentsOf: file) {
        buildAndSettleTheHeap()
        try? world.save(to: file)
    }
}
```

The snapshot's own `bodyCount` and `jointCount` say what is in it before anything is restored. `PhysicsSnapshot(data:)`, `init(contentsOf:)`, and `init(resource:in:)` read one back. Anything that is not a snapshot is refused rather than half-read, and a snapshot that stops short leaves the world that is already standing alone.

**Restoring is exact.** A restored body is in the same pose, moving at the same speed, and spinning the same way. If it had settled it is still asleep, so a saved heap does not shudder back into shape on the way in. A world stepped on from a restore lands exactly where the one that was never interrupted does. It goes through the ordinary `addBody` and `connect` calls, so a restored world is one you could have built by hand. A joint also keeps the zero it was made at, so a door saved standing half open is still half open, and still stops where it used to.

**What comes back.**

- Every rigid `Body3D` with its collider, pose, velocity, and every knob `addBody` takes: kind, sensor, density, friction, restitution, freedom, gravity scale, path checking, group, and buoyancy.
- Every `Joint3D` between them, gears and racks included.
- The collision-group table with its rules.
- The world's `gravity`, `ground`, `bounce`, `maxTimestep`, `unitsPerMeter`, and `water`.

The tiers above a loose body come back too, since none of them holds anything heavier than the shapes a body already writes down:

- **Characters** come back mid-stride, with the capsule, every knob `addCharacter` takes, where the figure stands, which way it faces, and the velocity it was moving at.
- **Vehicles** come back drivable, and under power. That is the chassis and its collider, every wheel with everything it was tuned to, the gearing, and the live drivetrain. The engine is turning at the speed it was turning, in the gear the box had picked, with the wheels already spinning. Without that last part a restored machine has to pull away from rest, which a moving one notices.
- **Ragdolls** come back as the fitting they were built from, a shape per limb, the tree they hang in, how far each joint may bend, and where every limb had got to. The skinned `Scene` is *not* in the file, and does not need to be. It is the sketch's own asset, still loaded, and `scene.apply(ragdoll)` writes the restored pose onto it exactly as before. So a figure comes back even in a run that has not read the file it was fitted from.

```swift
world.restore(saved)
// the objects are new ones, so take them from the world again
truck = world.vehicles.first
walker = world.characters.first
figure = world.ragdolls.first
```

**What it costs.** A snapshot is self-contained, which is what makes it a file you can commit beside a sketch, and it holds geometry the same way. A `.mesh` or `.heightfield` collider is written out whole, so a world that colliders a loaded set piece carries that set piece inside every snapshot of it. The bytes are packed, which costs nothing and is why a settled arrangement is small. A heap of sixty primitives is about a kilobyte. A world carrying a heightfield and two loaded meshes runs to about a megabyte, roughly half the scenery's own weight. A damaged or half-written file is refused rather than half-read. When that size matters, name the scenery instead of holding it, below.

**What does not.** A grab is a hand on a body rather than part of the world, and contacts are worked out again by the next `step(dt:)`, so neither is saved. Motors are not saved either. `drive(at:)` and friends are things a sketch says, usually every frame, so say them again. A soft body is nothing but its mesh, so it is saved only when it has been given a name to write down in place of one.

**The bodies are new objects.** `restore(_:)` empties the world first, so any `Body3D` or `Joint3D` you were holding is gone. Take them from `world.bodies` and `world.joints` again. They come back in the order they were saved in, so an index still names the same body. Each one still knows its own `collider`, which is usually all a drawing loop needs.

This is also the honest answer to determinism. Simulating is reproducible within one build, but the solver runs in floating point. A toolchain that moves one last bit moves the last bounce, which a toppling stack magnifies into a different heap. A saved arrangement has nothing left to compute, so it comes back the same anywhere. Continuing from a restore is exact for the pose and the motion. The solver's in-flight contact bookkeeping is not carried, so a scene captured mid-collision may drift where a settled one cannot. That covers a vehicle's wheels too, since what a wheel is rolling on is worked out afresh each step. A machine saved parked comes back parked and stays exactly where it was put. One saved at full throttle carries on from the same speed in the same gear and then wanders, the way a stack of crates saved mid-collapse does.

<a name="naming-geometry"></a>

#### Naming geometry rather than holding it

Almost everything in a world is small. A box is three numbers, a joint is a point and an axis. Two things are not. A `.mesh` or `.heightfield` collider carries every vertex of whatever it was cut from, and a soft body carries the whole mesh it was built out of. Give either a name and the snapshot writes the name down instead:

```swift
let island = world.addBody(.heightfield(terrain, width: 60, depth: 60, height: 8),
                           at: .zero, kind: .static)
island.assetName = "island"

let banner = world.addSoftBody(from: sheet, at: Vector3(0, 3, 0))
banner?.assetName = "banner"
```

and say what the names mean when the world comes back:

```swift
world.restore(saved) { name in
    switch name {
    case "island": return .heightfield(terrain)
    case "banner": return .mesh(sheet)
    default:       return nil
    }
}
```

`load(contentsOf:resolving:)` takes the same closure. `PhysicsAsset` is the two things worth naming, `.mesh(_:)` and `.heightfield(_:)`. `snapshot.assetNames` lists what a snapshot will ask for, so a sketch can check a file before restoring it. How a heightfield is sized in the world, its width, depth, and height, travels in the snapshot, since that is three numbers rather than geometry. Only the samples are named.

Measured on a world with a 65² terrain, a five-thousand-vertex mesh, and twenty crates, that is **105 KB holding it all, and 1.1 KB naming it.** On a smaller scene the difference is smaller. The default stays holding everything, because that is what makes a file you can commit beside a sketch and open anywhere.

Three things are worth knowing:

- **A name that resolves to nothing costs that one body, not the restore.** The rest of the world comes back and a note names what was missing. A resolver you have not finished writing yet therefore gives you a yard with no ground, rather than nothing at all.
- **A soft body needs a name to be saved at all**, since there is nothing else to it. An unnamed one is left out with a note.
- **A name that now resolves to *different* geometry is still restored, and said out loud.** The saved poses are the best answer there is, but a pose saved against one shape rarely fits another. What notices is a fingerprint of the geometry stored beside the name, so a re-exported mesh or a terrain regrown from another seed is caught.

The worked examples are [`3D/Physics/Cairn`](../../Examples/3D/Physics/Cairn/) and [`3D/Physics/Yard`](../../Examples/3D/Physics/Yard/). Cairn is a heap of stones laid one at a time, restored with **R**, written to a file with **S**, and read back with **L**, so quitting and running the sketch again finds the same cairn standing. Yard does the same for a yard holding a truck you drive, a figure pacing across it, a second figure lying where it fell, and a heightfield floor and a cloth banner that the file names rather than holds.

<a name="importing"></a>

### Reading physics from a file

A `.usd` scene can say more than what its prims look like. The `UsdPhysics` schema lets a file say four more things.

- Which prims are rigid bodies, and which are scenery.
- What shape each one collides as.
- How heavy they are.
- How they are jointed together.

A scene carrying that comes into a world in one call:

```swift
let scene = loadScene("yard.usda")!
world.addBodies(from: scene)          // every body and joint the file describes
```

Nothing else is needed. The bodies are ordinary `Body3D`s, so they collide, stack, take impulses, snapshot, and draw the way any others do. Each one's `assetName` is the name of the prim it came from, which is how a drawing loop tells them apart.

**What comes across.** Rigid bodies (falling, driven with `physics:kinematicEnabled`, or scenery), with their mass, density, center of mass, velocity, and whether they start asleep. Colliders as boxes, balls, capsules, cylinders, cones, hulls, and exact meshes. Friction and restitution from a bound physics material. The fixed, revolute, prismatic, spherical, and distance joints, with their limits. And the scene's gravity, if you ask for it with `applyGravity: true`.

Four rules are worth knowing, because each is the schema's and not a choice made here:

- **A collider's shape is the prim's own geometry.** There is no shape attribute. A `Cube` with `PhysicsCollisionAPI` on it is a box, and a `Sphere` is a ball. A scale on the prim makes a bigger shape, since a solver's shapes carry no scale of their own.
- **A rigid body owns everything under it.** Several collider prims in one subtree are one body wearing a compound collider, which is how a hammer is a handle and a head rather than two loose pieces.
- **A collider with no rigid body over it is scenery**, and never moves.
- **USD stands a capsule, cylinder, and cone on z** unless the prim's `axis` says otherwise, where Ollin's stand on y. A rod authored the default way therefore arrives lying down, because that is what the file says.

**What does not.** Articulations, joint drives and their limit API, and collision groups and filtered pairs are said in the file's own vocabulary rather than one this world has. So they are left alone. The stage's `upAxis` and `metersPerUnit` are not applied either, the same contract the rest of scene import keeps. A scene arrives as authored.

Reading is lossy, and that is exactly why this direction works. A file's notion of a body is a description, and anything it does not say has a sensible answer here. Writing would not be, which is why a world you want back *exactly* goes into Ollin's own snapshot instead. The two are complementary. Import to pick up an arrangement somebody else authored, and snapshot to keep one you found.

The worked example is [`3D/Physics/Imported`](../../Examples/3D/Physics/Imported/), whose `yard.usda` is hand-written and readable. It holds a seesaw on a hinge, a stack, a hammer, a sign on a hinge held to the world, and a capsule authored the default way so it comes in on its side.

<a name="grabbing"></a>

### Grabbing with the mouse

Reaching into the scene is two sketch calls, one to pick up and one to drag.

```swift
var grabbed: Joint3D?

override func mousePressed() {
    grabbed = grabBody(at: Vector2(mouseX, mouseY), in: world)
}
override func mouseReleased() {
    grabbed?.remove()
    grabbed = nil
}
// in draw(), before world.step:
if let grabbed { dragGrab(grabbed, to: Vector2(mouseX, mouseY)) }
```

`grabBody(at:in:)` casts a ray from the active camera through the canvas point. It hangs the body it hits on a soft drag spring at the touched point, and remembers how deep into the view that point sat. `dragGrab(_:to:)` then moves the body in the screen-parallel plane at that depth, so dragging feels like sliding it across the glass. The probe without the pickup is `body(under:in:)`, which returns the body and the world point the ray touched. World-space dragging without a camera is the lower-level `world.grab(_:at:)` plus the joint's `target`.

The camera drag and the body drag both want the mouse, so sketches that grab usually set a hand-placed `perspective(...)` rather than `cameraControl()`.

<a name="drawing"></a>

### Drawing bodies

`withBody(_:)` wraps `withState` and moves the 3D transform stack to the body's pose. The block therefore draws in body-local space, and every renderer feature applies untouched, materials, shadows, and export included:

```swift
for body in world.bodies {
    fill(body.userData as? Color ?? .white)
    withBody(body) {
        switch body.collider {
        case .box(let w, let h, let d): drawBox(width: w, height: h, depth: d)
        case .sphere(let r):            drawSphere(radius: r)
        case .capsule(let h, let r):    drawCapsule(radius: r, height: h)
        case .cylinder(let h, let r):   drawCylinder(radius: r, height: h)
        default:                        break
        }
    }
}
```

The simulation is deterministic within a build. The same setup stepped the same way reproduces exactly, which is what the seeded-variations story needs live. Exact poses can shift across toolchain rebuilds, so physics scenes aren't pinned by pixel snapshots. The behavioral test suite pins the solver instead, and [a snapshot](#snapshots) is how an arrangement is kept for good.

Worked examples:

- [`3D/Physics/Stack`](../../Examples/3D/Physics/Stack/) - a crate pyramid under cannon fire.
- [`3D/Physics/Tumble`](../../Examples/3D/Physics/Tumble/) - a mixed-solid pile you can drag.
- [`3D/Physics/Chain`](../../Examples/3D/Physics/Chain/) - a wrecking ball on a ball-jointed chain.
- [`3D/Physics/Windmill`](../../Examples/3D/Physics/Windmill/) - a motor-driven compound blade cross, batting balls through limited, spring-shut swing gates.
- [`3D/Physics/Rockslide`](../../Examples/3D/Physics/Rockslide/) - rocks tumbling down eroded heightfield terrain.
- [`3D/Physics/Trigger`](../../Examples/3D/Physics/Trigger/) - a scoring hoop and a loaded tray, both sensors, with every knock ringing at the speed it landed.
- [`3D/Physics/Ragdoll`](../../Examples/3D/Physics/Ragdoll/) - a skinned figure that stands and waves, or collapses, depending on whether its joints are powered.
- [`3D/Physics/Drape`](../../Examples/3D/Physics/Drape/) - a banner in the wind, a sheet over a crate, and a beach ball you can deflate.
- [`3D/Physics/Sightlines`](../../Examples/3D/Physics/Sightlines/) - a lamp that lights only the crates it can see, a drone holding its clearance by sweep, and a pulse that shoves whatever a sphere overlaps.
- [`3D/Physics/Cairn`](../../Examples/3D/Physics/Cairn/) - a heap of stones saved to a file and put back exactly.
