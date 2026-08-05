#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Simulation](./README.md) → `Physics3D`</sup>

---

## 3D physics

Rigid bodies inside the 3D scene: crates that stack and topple, balls that roll, chains that swing, all with real contact response. This is the spatial sibling of the [2D physics world](Physics.md)'s rigid side, and it keeps the same shape: build a [`World3D`](#world3d) once, add [`Body3D`](#body3d)s, step it each frame, and draw each body from its pose. It lives in the same satellite, so `import OllinPhysics` brings both.

Beside the bodies there are three things that aren't ones: a [`Character3D`](#characters), a walking figure you steer from `draw()` rather than push around with forces, a [`Vehicle3D`](#vehicles), a chassis on sprung wheels you drive, and a [`SoftBody3D`](#softbodies), a mesh whose vertices are simulated so it drapes and squashes.

The solver behind it is [Jolt Physics](https://github.com/jrouwe/JoltPhysics), vendored and wrapped the way Box2D backs the 2D side; nothing of it leaks into the API.

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

Distances are the 3D scene's world units (y-up, matching the camera). The solver thinks in meters and is happiest with bodies roughly 0.1…10 units across, which is the scale the 3D examples already draw at; `unitsPerMeter` rescales the bridge if your scene is built larger.

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
- [Water](#water) - buoyancy: what floats, how deep it sits, and what carries it
- [Saving and loading](#snapshots) - keeping an arrangement you like, and putting it back
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

`ground` is a wide static slab whose top face sits at the given level; `nil` (the default) lets bodies fall forever. `step(dt:)` clamps to `maxTimestep` (1/30 s) so a stalled frame can't launch the scene, and runs one collision pass per ~60 Hz of simulated time.

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

`density` is relative (1 is the default material; heavier shoves lighter), `friction` runs 0 slick … 1 grippy, and `restitution` defaults to the world's `bounce`.

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

`userData` is a free slot for whatever the sketch wants to hang off a body (its color, its mesh), and `collider` keeps the shape the body was created with so a drawing loop can match a mesh to it without a parallel array.

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

**`freedom`** is which of the six directions the body may use: three to travel along, three to turn about, in world axes. Everything is free by default.

```swift
.all                        // the default
.plane()                    // travels in x and y, turns about z: a flat world
.plane(normal: .unitY)      // travels in x and z, turns about y: a top view
.upright                    // travels any way, turns only about up, never tips
.noTurning                  // slides and is shoved, never spins
.noMoving                   // spins where it is, never travels
[.moveX, .turnZ]            // or spell out whatever fits
```

`.plane()` is the 2.5D lever: a sketch drawn side-on stays flat however hard things hit each other, while everything else about the world (lighting, shadows, solid drawing, the whole collider catalog) carries on in three dimensions. A locked direction is one the solver gives the body infinite mass along, so **nothing** can move it that way: not gravity, not a contact, not a joint, not a velocity you set yourself. Only whole world axes can be taken away, so `.plane(normal:)` rounds its normal to the nearest axis; there is no tilted plane. An empty set would leave a body no freedom at all, which the solver cannot express, so it reads as `.all`. To hold a body still, set `kind = .static` instead.

**`gravityScale`** is how hard this one body answers the world's gravity: `1` as everything else, `0` weightless, negative to rise.

```swift
balloon.gravityScale = -0.3
feather.gravityScale = 0.15      // falls a sixth as far in the same second
```

**`checksPath`** sweeps the body's shape along its whole path each step instead of only testing where it ends up. Off by default, and worth turning on for anything small and quick: a body that covers more than its own width between two steps can be in front of a thin wall at one step and past it at the next, having never touched it.

```swift
let pellet = world.addBody(.sphere(radius: 0.05), at: muzzle, checksPath: true)
pellet.velocity = Vector3(0, 0, 120)
```

It costs nothing while the body is slow: the check only runs once a body covers a good fraction of its own size in a step, and an ordinary throw lands on exactly the same spot either way. What it does cost is a little honesty about speed, since a body that hits something at pace gives up the rest of its step where it struck. (This is continuous collision detection, under a name that says what it does.) Two neighbours have their own answer to the same problem and need nothing turned on: a `Character3D` already tests its path as it walks, and a `Vehicle3D`'s wheels feel for the road by casting rays, so it is the chassis (`vehicle.body.checksPath`) that would want it if anything did.

<a name="collider3d"></a>

### Collider3D

The local shape of a body, centered on its origin; position and orientation come from the body.

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

The upright shapes all stand along the body's y axis (rotate the body to orient them), and their `height` matches the matching draw call (`drawCapsule`, `drawCylinder`, `drawCone`), so the mesh call takes the collider's own numbers. The tapered pair slope between two radii: a `taperedCylinder` keeps flat caps (equal radii make a plain cylinder, a zero top radius is exactly `.cone`), and a `taperedCapsule` rounds both ends with caps of different sizes, both radii positive. A `.mesh` collider is for scenery (a loaded set piece, an exact sculpted form): it has no volume for mass, so a dynamic body created with one is pinned in place; moving shapes want `.hull`, a primitive, or a `.compound` of them.

<a name="compound"></a>

### Compound bodies

`.compound` fuses several colliders into one rigid body: a hammer, a table, a windmill's blade cross. Each part is a child collider posed in the body's local space, and the body's mass, balance, and inertia come from the whole assembly, so a lopsided tool tumbles the way a lopsided tool should.

```swift
let hammer = world.addBody(.compound([
    .part(.capsule(height: 0.9, radius: 0.06)),          // the handle
    .part(.box(width: 0.3, height: 0.14, depth: 0.14),
          at: Vector3(0, 0.52, 0), density: 8),          // the head, leading the swing
]), at: Vector3(0, 3, 0))
```

`.part(_:at:rotated:axis:density:)` places any collider at a position and rotation inside the body; everything defaults to "at the origin, unrotated", so a single offset part is also how you shift a shape off its body's origin. A part's `density` is relative and multiplies the body's own, which is what makes the hammer's head heavy against its handle. Parts can nest (a compound inside a compound), and they should be solid shapes: a `.mesh` or `.heightfield` part pins the body in place, the same as using one bare.

Draw a compound the way it was built: `withBody` poses the whole body, then translate and rotate to each part's pose and draw its shape. The [`3D/Physics/Windmill`](../../Examples/3D/Physics/Windmill/) example does exactly that with a small recursive helper.

<a name="terrain"></a>

### Terrain and scenery

`.heightfield` turns a [`Heightfield`](../Generators/Terrain.md) into solid ground, sized exactly like its `mesh(width:depth:height:)`: a `width` × `depth` grid centered on the body's origin, each sample lifted to `height · value`. Collider and drawn mesh trace one surface, so what rolls matches what renders:

```swift
let land = Heightfield.diamondSquare(size: 257, roughness: 0.55, seed: 7)
    .eroded(.hydraulic(), seed: 7)
world.addBody(.heightfield(land, width: 14, depth: 14, height: 4),
              at: .zero, kind: .static)
drawMesh(land.mesh(width: 14, depth: 14, height: 4))   // the same numbers
```

The field is resampled onto a square power-of-two grid for the solver (at least the source resolution, capped at 1024 samples per side), so any grid shape works; beyond the field's edges there is nothing, and bodies roll off into the void. Like `.mesh`, a heightfield can only be static.

For scenery that arrives as a file, one call colliders a whole [`Scene`](../3D/Scenes.md):

```swift
let hall = loadScene("hall.usdz")!
world.addStaticColliders(from: hall)
```

It walks the node tree and adds one static mesh body per mesh node, with the node's world transform (nested groups, authored rotations and scales included) baked into the triangles. Colliders take each mesh as authored, at rest: skins and morph targets aren't posed. `friction:` and `restitution:` apply to all of them, and the scene itself keeps drawing through `drawScene(_:)`.

<a name="joints"></a>

### Joints

`connect` links two bodies with a `Joint3D`; anchors and axes are world coordinates at the moment of connecting.

```swift
world.connect(door, frame, .revolute(at: hingePoint, axis: .unitY))
world.connect(link, next, .ball(at: meetingPoint))
world.connect(a, b, .distance(from: pa, to: pb))          // a rod; stiffness < 1 softens
world.connect(a, b, .weld)                                // rigid at current pose
world.connect(carriage, rail, .prismatic(at: p, axis: .unitX))
```

`.ball` is the 3D-only kind: a ball-and-socket that rotates freely in every direction, the joint of hanging chains. A hinge (`.revolute`) allows rotation only about its axis. Cut any joint with `joint.remove()`.

`.swingTwist` is the ball-and-socket with limits, and the joint a body is made of. Give it the bone's direction and it lets that bone lean away from where it started by at most `swing` radians in any direction (tracing a cone) while rolling about itself within `twist`:

```swift
world.connect(chest, upperArm,
              .swingTwist(at: shoulder, axis: Vector3(-1, 0, 0),
                          swing: 80 * .pi / 180, twist: -0.6...0.6))
```

A shoulder is a wide cone with a little twist; a knee is a narrow one. `swing: 0` locks the bone straight, `.pi` frees it entirely. Its `angle` reads how far the joint is currently bent, and `friction` gives it the stiffness of an old hinge. It is what `addRagdoll` hangs every limb on.

Three more kinds do what none of these can: [`.path`](#morejoints) threads a body onto a track, [`.pulley`](#morejoints) runs a rope over two hooks, and [`.allowing`](#morejoints) is the general joint written as the freedoms it keeps. Two more link one joint to another: [gears and a rack and pinion](#links).

<a name="motors"></a>

### Motors, limits, and springs

Hinges and sliders can do more than swing free: bound their travel, power them, and spring their stops. Together they make doors that close themselves, windmills that turn, drawers that stop at the end of their rails.

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

`drive(to:)` is a spring servo: `frequency` is how fast it pulls (2 is a lazy door closer, 20 a snappy robot servo) and `damping` at 1 settles clean, lower overshoots and bounces. Both forms take `strength`, a cap on the motor's torque (N·m) or force (N); the unlimited default just reaches its target, while a small value gives the motor something to lose against, like a door closer a rolling ball can barge through:

```swift
door.drive(to: 0, frequency: 1.2, strength: 60)
```

Driving is stateful: set it once and the motor keeps pulling every step until `stopMotor()` or a new `drive`. Where the joint sits right now reads back as `door.angle` (radians) or `drawer.offset` (world units), both 0 at the connect pose.

Two passive knobs finish the set:

```swift
hinge.friction = 80                          // drag torque/force when unpowered
gate.softenLimits(frequency: 3, damping: 0.5)   // springy end stops
```

`friction` is the stiff old hinge: a constant resistance the joint's motion must overcome while no motor is powering it, which is also what winds a spinning wheel down after `stopMotor()`. `softenLimits` swaps the hard stops for springs, so a gate thrown against its limit gives a little and bounces back; `frequency` 0 restores the wall. The other joint kinds have no axis to power, so the motor calls on a `.ball`, `.distance`, or `.weld` note once and do nothing (`.distance` has its own spring: the `stiffness` on the case).

A `.swingTwist` joint takes both motor calls too, and one more of its own. A single number about a joint that bends in every direction can only mean the roll about its own axis, so `drive(at:)` and `drive(to:)` run the twist and leave the bend alone; `joint.twist` reads that roll back where `joint.angle` reads the bend. To point the bone somewhere, say so:

```swift
neck.drive(toward: (bird.position - head.position).normalized, frequency: 6)
neck.stopMotor()                                   // and it hangs again
```

`drive(toward:)` pulls the joint's axis onto a world direction, rolled `twist` radians about itself, clamped to the joint's own cone and twist limits: aim past the cone and it leans as far as it may. Set it each frame to follow something.

<a name="morejoints"></a>

### Tracks, ropes, and freedoms

Three more kinds, each doing something no hinge or slider can.

**`.path` is a track.** Give it a ring of points and the second body is threaded onto the smooth curve through them, free to travel along it and nothing else. The rollercoaster car, the bead on a wire, the camera on a dolly rail:

```swift
let ride = world.connect(rails, cart,
                         .path(through: points, looping: true,
                               alignment: .followsPath))
ride.drive(at: 6)          // world units per second along the track
ride.drive(to: 0.5)        // or seek half way round and hold there
ride.progress              // 0 at the first point, 1 at the last
```

The curve is a spline *through* the points, not a polyline, so a handful of them describes a long track, and the body joins it at the point nearest to wherever it already is (place it on the track before connecting). `alignment` says how much of its turning the track takes over: `.free` leaves it tumbling, `.rolls` lets it spin only about the direction of travel, `.followsPath` banks it into every bend, and `.fixed` holds the first body's orientation the whole way round. The track belongs to that first body, so hanging it off a moving one carries the whole ride along. A flat `Contour` becomes a track on the ground in one call:

```swift
world.connect(ground, cart, .path(loop, atHeight: 0.3))   // contour y runs along world z
```

**`.pulley` is a rope over two hooks.** One end is on each body, and the total length is what ties them together, so one side rising is the other falling:

```swift
world.connect(tray, counterweight,
              .pulley(from: trayTop, over: leftHook,
                      and: rightHook, to: weightTop))
```

Read it as written: from the tray, up over the left hook, across to the right one, and down to the weight. `ratio` is how many falls of rope hold the second side (2 is a block and tackle, where that side moves half as far and lifts twice as much). A rope resists being pulled longer but not being let slack, which is what lets both ends drop together; `taut: true` makes it a rigid linkage instead, so lifting one end drives the other down. Both ends must be an ordinary or a static body: the solver reads a kinematic one wrongly, so that case is refused with a note (move a static end instead).

**`.allowing` is the general joint, written as what it keeps.** Every other kind is a choice out of the six degrees of freedom a body has, so when none of them fits, name the freedoms:

```swift
// A post a platter rides: it may rise and it may spin, and nothing else.
world.connect(post, platter,
              .allowing([.moveY, .turnY], at: top, travel: 0...1.4))
```

The freedoms are the same `Freedom3D` set a body's own [motion knobs](#motion) use, in world axes at the moment of connecting. `travel` bounds every direction it may move in and `rotation` every axis it may turn about, both measured from the connect pose; leave either out to run unbounded. `.allowing([])` is a weld, `.allowing([.turnX, .turnY, .turnZ])` is a `.ball`, and a single turn with a range is a hinge, which is a good way to see what the named kinds are made of.

<a name="links"></a>

### Gears and racks

The last two are links between *joints*, not bodies, because what they tie together is the motion those joints allow. Build each part's own joint first, then connect the joints:

```swift
let small = world.connect(frame, pinion, .revolute(at: hub, axis: .unitZ))
let big = world.connect(frame, wheel, .revolute(at: farHub, axis: .unitZ))
world.connect(small, big, .gear(teeth: 20, and: 36))
```

Turning either hinge now turns the other, in the opposite sense and at the ratio asked for. `.gear(ratio:)` says the same thing as a number: how many turns the first makes per turn of the second. It counts teeth and has no sign, so to make a pair turn the same way, flip one hinge's axis.

A rack and pinion ties a hinge to a slider, so turning drives sliding:

```swift
let rack = world.connect(frame, bar, .prismatic(at: p, axis: .unitX))
world.connect(big, rack, .rackAndPinion(travelPerTurn: 2 * .pi * pinionRadius))
```

`travelPerTurn` is how far the bar runs, in world units, for one full turn of the pinion, which for a pinion of radius `r` rolling along it is its own circumference. A negative value runs the bar the other way.

Both links take a hinge as their first joint, and a hinge (gear) or a slider (rack and pinion) as their second; anything else notes once and does nothing. Each joint's moving part is the body that is not static, or the second body it was connected with when both can move, which matches the order every `connect` call is written in (the frame first, the part that turns second). And because the shapes never touch, meshed wheels want to be told not to collide, or their plain cylinders will jam:

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

A `Contact3D` carries the pair (`a` and `b`, always in the same order, not "the one that moved"), where they met (`point`), the `normal` pointing from `a` toward `b`, and `speed`, how fast they were closing when they met. `speed` is measured *before* the solver answers the collision, so it reads the force of the impact rather than what survived the bounce, which is what you want for the volume of a clink or the size of a spark. Two helpers save the "which one is mine" dance:

```swift
contact.involves(ball)          // is this ball in it?
contact.other(than: ball)       // what did it hit?
```

Contacts are per body **pair**. A crate resting on a mesh floor touches it along many triangles and a compound body touches on several of its parts, but that is one `began` when it lands and one `ended` when it lifts.

An `ended` contact carries only the pair: by the time the solver notices a touch is over there is nothing left to measure, and the other body may already have been removed, so `point`, `normal`, and `speed` are zero there.

The two sides are typed `any Colliding3D`, not `Body3D`, because either may be a [soft body](#softbodies): a cloth is a real thing in the world that lands on floors and sails into sensors, but there is nothing to push it with and no single pose to read, and the type is what says so. `involves`, `other(than:)`, and `===` all work either way; reach for the concrete kind when you want to act on it:

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

The floor from `world.ground` is a body too, just not one in `bodies` (nothing added it, and a drawing loop shouldn't have to skip a 1000-unit slab). It answers to `world.groundBody`, so a landing is recognisable:

```swift
if contact.other(than: ball) === world.groundBody { thud() }
```

One thing to know about `touching`: the solver lets a settled body sleep, and a sleeping body stops reporting contacts, so a stack that has come to rest reads as touching nothing. That is the right answer for events (nothing is happening) and a surprising one for occupancy. When the question is "what is resting in this region", use a sensor, which stays awake.

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

Sensors push nothing and are pushed by nothing, so a ball falls through one exactly as it would through empty air, and a sensor can share space with solid geometry (the hoop above is a solid rim of beads with a sensor disc filling the ring: the rim is what a ball clatters off, the sensor is the hole).

A sensor sets its own motion: it is kinematic and never sleeps, whatever `kind` was asked for, so it goes on reporting bodies that have settled and fallen asleep inside it. That is what makes a tray or a pressure plate work:

```swift
let tray = world.addBody(.box(width: 3, height: 0.7, depth: 3),
                         at: Vector3(0, 0.55, 0), isSensor: true)
let load = tray.touching.count        // still right once they doze off
```

Because it never falls, a sensor stays where it is put; move one by setting its `position` (to make a detector follow something, drive it from that body's pose each frame). Sensors are also invisible to `body(under:in:)` and `grabBody(at:in:)`: the cursor's ray looks straight through them to the solid scene behind.

Sensors detect *moving* bodies (dynamic and kinematic), not static scenery, and not each other, so a trigger volume laid over the ground doesn't spend every step reporting the ground.

<a name="groups"></a>

### Collision groups

Everything in a world collides with everything else. A **collision group** is a name you put things in so the world can be told that two of those names pass straight through each other.

```swift
let bead = world.addBody(.sphere(radius: 0.2), at: p, group: "beads")
world.ignoreCollisions(between: "beads", and: "glass")
```

That is the whole surface: `group:` wherever a thing is made, and one sentence per rule. The rule is a fact about a pair rather than a direction, so there is no way to say that beads ignore the glass and forget that the glass ignores beads. `allowCollisions(between:and:)` withdraws a rule, and `collides(_:with:)` reads one back.

**Everything starts in `.default`, and naming a group is not itself a rule.** A world nobody has written a rule for behaves exactly like a world with no groups. A group only means something once something has been said about it, which is why a group name is a plain string and needs no declaring.

**A group collides with itself** until told otherwise, so two crates in one group still stack. Saying it twice is how confetti falls through its own drift:

```swift
world.ignoreCollisions(between: "confetti", and: "confetti")
```

**What a rule reaches.** A filtered pair is filtered everywhere the pair could have met: it never collides, it never reaches [`contacts`](#contacts), a [sensor](#sensors) in an ignored group never reports it, a [character](#characters) walks through it (including through another character), and a [vehicle](#vehicles)'s wheels do not feel it under them. Every kind of thing takes a group:

```swift
world.addBody(…, group: "phantoms")
world.addCharacter(…, group: "phantoms")
world.addVehicle(…, group: "traffic")
world.addRagdoll(from: figure, group: "phantoms")
world.addSoftBody(from: cloth, group: "drapes")
world.addStaticColliders(from: hall, group: "scenery")
```

and each of them can be moved between groups while it runs: `body.group`, `character.group`, `vehicle.group`, `ragdoll.group`, `softBody.group`. A rule written after things have already settled on each other still applies; the bodies are woken so the solver looks at the pair again.

A figure's own limbs are kept from fighting each other by a separate mechanism that groups never touch, so two ragdolls in one group still collide with each other exactly as they should.

**Asking as a group.** Every [query](#queries) takes `as:`, which asks the question the way a body of that group would ask it, looking straight through whatever that group passes through:

```swift
world.ignoreCollisions(between: "bullets", and: "glass")

world.raycast(from: muzzle, to: target)                  // stops at the pane
world.raycast(from: muzzle, to: target, as: "bullets")   // goes through it
```

A query with no `as:` is asked in `.default` and sees the whole world.

**The bookkeeping.** A world holds `World3D.maxCollisionGroups` (64) groups; naming more keeps the extras in `.default` rather than quietly aliasing them onto a group already in use. `world.collisionGroups` lists the ones it knows in the order they were named, which is how a misspelled name is found: a typo is a *new* group, and a rule written about it does nothing.

Worked example: `Examples/3D/Physics/Sieve` sorts three colors of bead down one ramp, with the sorting itself being three `ignoreCollisions` calls.

<a name="queries"></a>

### Queries

`contacts` reports what the solver noticed while it stepped. A **query** asks it something it was never asked, between steps: what is along this line, what would a shape run into, what is inside this region right now. All of them answer immediately, none of them changes anything, and none needs a body built to ask with.

Every answer is a `Hit3D`: what it ran into (`body`, typed `any Colliding3D` since it may be a [soft body](#softbodies)), the `point` where the query touched it, the outward surface `normal` there, and `distance`, how far along the query the touch was (from a ray's start, or how far a swept shape travelled).

**Rays.** `raycast(from:to:)` returns the nearest body along a segment, `raycastAll(from:to:)` every body along it, nearest first.

```swift
// line of sight: the crate is visible when the crate is what the ray found
let visible = world.raycast(from: lamp, to: crate.position)?.body === crate

// a ground probe: how far down the floor is
let drop = world.raycast(from: p, to: p - Vector3(0, 20, 0))?.distance
```

A ray is a segment, not an infinite line: it reaches exactly as far as `to`. For a direction and a reach, pass `to: p + direction * reach`.

**Sweeps.** `sweep(_:from:to:)` slides a collider along a line without turning it and returns the first thing it runs into (`sweepAll` returns them all). A ray asks what is in the way; a sweep asks whether something *fits*, which is what a clearance probe, a camera that must not end up inside a wall, or a step a character is about to take actually needs.

```swift
// hold 1.5 units above whatever passes below, crates included
let below = world.sweep(.sphere(radius: 0.4), from: overhead,
                        to: overhead - Vector3(0, 12, 0))
let height = (below?.point.y ?? 0) + 1.5
```

`rotated:`/`axis:` turn the probe, which changes what fits (a wide, thin box goes through a narrow gap edge-on and not flat). A sweep that sets off already touching reports `distance` 0. `mesh` and `heightfield` colliders describe scenery rather than a probe and cannot be swept or overlapped with; use a hull, a compound, or a primitive.

**Overlaps.** `bodiesOverlapping(_:at:)` returns the bodies inside a shape placed in the world, in a stable order, one entry per body however many of its parts are inside. `bodiesContaining(_:)` is the same question for a bare point.

```swift
for caught in world.bodiesOverlapping(.sphere(radius: 4), at: blast) {
    guard let body = caught as? Body3D else { continue }   // only a solid takes one
    body.applyImpulse((body.position - blast).normalized * 12)
}
```

A [sensor](#sensors) answers the same question *continuously* from a body that exists in the scene, which is what a pressure plate or a goal wants. An overlap answers it once, anywhere, with a shape that never existed.

**What a query sees.** Solid bodies, static scenery and the `ground` slab included, plus the ones the world keeps out of `bodies` (a character's stand-in, a ragdoll's limbs), so a walking figure can be spotted through `character.body`. **Soft bodies** are in there too: a hanging sheet stops a sightline the way a wall does, and the hit names the `SoftBody3D`. One thing is deliberately transparent: a **sensor**, since a detector volume is a region to be inside rather than a surface to hit (pass `includingSensors: true` to have them reported too). `ignoring:` takes anything to look straight through, which is how something casts from inside itself, or through a curtain:

```swift
let ahead = world.raycast(from: robot.position, to: target,
                          ignoring: [robot])
```

`as:` narrows it the other way, by [collision group](#groups) rather than by naming bodies.

Queries cost nothing but the search: asking does not step the world, so a per-body sight check every frame is an ordinary thing to write.

<a name="characters"></a>

### Characters

A `Character3D` is a walking figure: a capsule that goes where you steer it, climbs steps, is stopped by walls and by slopes too steep to hold it, and jumps. It is not a rigid body. Nothing tumbles it and nothing knocks it over, which is exactly what you want for something a person drives, and it is why walking is a `draw()` poll rather than a pile of forces.

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

`step(dt:)` sweeps every character forward along with the bodies, so there is no second update call to remember. `move(_:)` sets the horizontal velocity the character is *trying* to walk at and holds it until changed; falling and jumping are the world's business, so the vertical part is ignored. `jump(_:)` is granted only if the character is on the ground on the next step, which means calling it every frame while a key is held gives a hop each time it lands rather than flight.

**Position is the feet.** `walker.position` is the point the capsule stands on, so a figure modeled standing at the origin lands where it should. `withCharacter(_:)` moves the 3D transform stack there and turns it by `facing`, the mirror of `withBody(_:)`.

#### What it can get past

Three settings decide what the geometry does to the character, and each has a visible edge:

| | what it means |
| --- | --- |
| `stepHeight` | The tallest step it walks up without jumping (0.4 by default): a stair, a kerb, a ledge. Set it to `0` and the same stairs become a wall. |
| `maxSlope` | The steepest slope it can climb, in radians (50° by default). A steeper face still holds it up, but it can't get any further up. |
| `pushStrength` | The hardest it can shove a dynamic body sideways, in newtons (100 by default). At `0` crates become immovable walls to walk around. |

`stepHeight` is the distance the character probes upward, not a hard ceiling: because the capsule's rounded foot rides the edge a little first, a ledge somewhat taller than the setting may still be climbed. Give it a clear margin rather than tuning to the exact centimetre.

Whether a push actually shifts something is a contest between `pushStrength` and what the body weighs. A 4 kg crate on an ordinary floor slides under the default 100 N; a 43 kg one doesn't, because ground friction alone asks for more than that. Make crates light if you want them scattered.

#### Reading it back

| | |
| --- | --- |
| `isOnGround` | Standing on ground it can walk on: the test to gate a jump or swap a walk cycle for a falling pose. |
| `groundState` | The full answer: `.onGround`, `.onSteepSlope` (held, but too steep to climb), `.notSupported` (touching something that can't hold it), `.inAir`. |
| `groundNormal` | The surface under its feet, to lean a drawn figure into a slope. |
| `groundBody` | What it is standing on, or `nil` in the air. A moving platform carries the character along with it. |
| `velocity` | What it is *trying* to do: intent, including the fall and the jump. |
| `actualVelocity` | What the world let it do, measured from the ground actually covered. |

Those last two are the pair worth knowing. Walk into a wall and `velocity` still reads a full walking pace while `actualVelocity` reads nothing, so a walk cycle driven by `actualVelocity` stops its legs when the character stops moving:

```swift
let pace = Vector2(walker.actualVelocity.x, walker.actualVelocity.z).length
stride += pace * deltaTime * 3.4        // legs stall against a wall
```

#### Among the ordinary bodies

A character is swept through the world by hand rather than simulated as a body, so it isn't in the scene by itself. It carries a stand-in that is: `walker.body`, a kinematic `Body3D` moving inside the capsule. That is what makes the character visible to everything else in this page. Sensors see it walk in, `world.contacts` names it, and `body(under:in:)` can pick it:

```swift
if lookout.isTouching(walker.body) { /* standing on the platform */ }
```

The stand-in is deliberately kept out of `world.bodies`, the same way the ground slab is, so a drawing loop over the bodies doesn't render a capsule where the sketch draws its own figure. Its `position` is the stand-in's center; read `walker.position` for the feet.

Teleport with `position`, which also re-reads what is underfoot on the spot, and `stop()` clears both the walking velocity and any speed carried from a fall. Characters collide with each other as well as with the scenery.

The worked example is [`3D/Physics/Stroll`](../../Examples/3D/Physics/Stroll/): an eroded island with stairs up to a lookout that lights as you arrive.

<a name="vehicles"></a>

### Vehicles

A `Vehicle3D` is a machine you operate rather than a body you push: a chassis carried on sprung wheels, with an engine and a gearbox behind the throttle. You set four numbers each frame and the wheels do the rest, finding their own grip on whatever they are rolling over.

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

`step(dt:)` hands each vehicle's controls to the solver along with everything else, so there is no second update call. **The vehicle drives along the chassis's local +z**, with +y up, so model whatever you draw facing that way; positive `steering` turns it to its own right.

The chassis is an ordinary `Body3D`. `car.body` collides, takes impulses, reports contacts, and is in `world.bodies` like anything the sketch added; what makes it a vehicle is the constraint on top, which owns the wheels. Its weight is `mass` (1500 kg by default) rather than the shape's volume, and by default its center of mass drops to the height of the wheel mounts, which is what stops a car rolling over the first time it turns hard.

#### The controls

| | |
| --- | --- |
| `throttle` | The gas pedal, `-1…1`. Positive drives forward, negative reverses. |
| `steering` | Where the wheels point, `-1` hard left … `1` hard right. |
| `brake` | The brake pedal, `0…1`: slows every wheel that has `brakeTorque`. |
| `handBrake` | `0…1`: locks only the wheels with `handBrakeTorque`, which is what makes the back step out. |

All four hold until changed, so set them every frame. `drive(throttle:steering:brake:)` sets three at once and `coast()` lifts everything off.

Asking for the other direction while the vehicle is still rolling brakes first and takes the new direction only once it has stopped, which is how a car with an automatic gearbox behaves. Press "back" at speed and you get the brakes; press it again from a standstill and you reverse.

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
| `grip` | Scales the tire's own friction: `1` is normal, lower is slick. The ground's friction combines with it, so slippery ground still slides a grippy tire. |
| `casterAngle` | How far the fork is raked back. A car leaves it at `0`; a two-wheeler needs a real rake (see below). |

**Wheels level with each other along the vehicle share an axle**, worked out from where they sit rather than the order you listed them, and an axle with any driven wheel is turned by the engine, so marking one of a pair marks its pair. A lone wheel, as a two-wheeler's are, is an axle by itself. Each full pair is also tied by an anti-roll bar (`antiRollStiffness`, 1000 N/m by default, `0` to untie them), which is what keeps the vehicle flat through a corner.

Everything on a wheel can be changed while the vehicle drives, so a slider on the springs or the grip is felt on the next step. `driven` is the gearbox rather than the wheel, so it is the one that costs something: changing it rebuilds the drive on the next step and re-gears it against whatever is now driven. Set the whole list, then step, then read the flags back to see what the drivetrain settled on:

```swift
for wheel in car.wheels { wheel.driven = wheel.position.z > 0 }   // front drive
world.step(dt: deltaTime)
```

#### The engine

Two numbers stand in for the whole drivetrain:

- **`engineTorque`** (500 N·m by default) is how hard the engine pulls. More of it spins the wheels sooner rather than accelerating harder: grip is the ceiling, not power.
- **`topSpeed`** (30 units/s) is the gearing. Top gear at the engine's redline turns the driven wheels this fast, so it is a ceiling the vehicle approaches on a flat straight rather than a promise. Winding it down gears the vehicle for pull instead of pace.

Both can be changed while driving. The gearbox shifts itself; `gear` reads which one it picked (`-1` reverse, `0` neutral, `1` first, and up) and `rpm` how fast the engine is turning, which is what to drive an engine sound from.

#### Reading it back

| | |
| --- | --- |
| `speed` | How fast it is travelling along its own forward axis; negative in reverse. |
| `forward` / `up` | The chassis's axes in world space. A chase camera wants `forward`; `up` tips as the vehicle leans. |
| `isOnGround` | Whether any wheel is touching. `false` means nothing the driver does will change anything. |
| `wheel.center` | Where the wheel is now, suspension travel included. |
| `wheel.spin` / `wheel.steerAngle` | How far it has rolled and how far it is turned. |
| `wheel.isOnGround` / `wheel.groundBody` / `wheel.groundNormal` | What that tire is on. |
| `wheel.suspensionCompression` | `0` fully extended … `1` bottomed out: watch a car squat under power and dive under braking. |
| `wheel.slip` / `wheel.slideAngle` | How much the tire is sliding along itself and across itself. Color a wheel by `slip` and a spinning one lights up. |

`withWheel(_:)` moves the 3D transform stack to a wheel's pose, steering and spin included, the way `withBody(_:)` does for a body. A tire modeled as a cylinder along +y lands right.

Two more knobs sit on the vehicle. `maxTilt` caps how far the chassis may lean from upright (`nil` by default, so it rolls over like anything else; around `.pi / 3` keeps a car on its wheels over rough ground). `wheelContact` picks how the wheels find the ground: `.cylinder` (the default) sweeps the tire's real footprint and is the steadiest over terrain, `.sphere` rounds off edges, and `.ray` is a single cheap ray that can drop a narrow wheel into a gap it should have ridden over.

#### Two wheels

A two-wheeler is the same call with `balances: true`, which adds the controller that holds it up and leans it into turns. It needs one thing a car doesn't: a real `casterAngle` on the front wheel, because the trail that comes with a raked fork is what lets it hold a line instead of flopping over at the first correction.

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

Running dead straight even an unbalanced two-wheeler stays up, because nothing tips it; the balancing shows the moment something does. Start it leaned over and it stands back up, and it leans into a corner rather than falling out of it.

The worked example is [`3D/Physics/Joyride`](../../Examples/3D/Physics/Joyride/): a car you drive over an eroded island, with the springs and the grip on live sliders.

<a name="tracks"></a>

### Tracks

`tracked: true` builds the same machine on two tracks. The wheels become road wheels, split into a left and a right band by **which side of the hull they sit on**, and the three controls mean what they always did:

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

Steering is the one that reaches the ground differently, because a track has nothing to turn. The number sets how much slower the inside band runs: half lock stops it, so the machine turns about its own inside track, and **full lock runs it backwards, which spins the machine where it stands**. It needs throttle to do any of that, the way a real one does: the bands are turned by the engine, so with the engine idle there is nothing to run one against the other.

```swift
crawler.throttle = 1
crawler.steering = 1        // turn on the spot
```

`trackSpeed(.left)` and `trackSpeed(.right)` read how fast each band is running over the ground, in world units per second. They are equal in a straight line, differ through a turn, and run opposite ways in a pivot, so they are what to scroll a drawn track by. `wheels(on:)` gives one band's road wheels, front of the machine first, which is what a drawing loop walks to lay a track around them.

Most of a wheel means the same thing on a band. These do not:

| | |
| --- | --- |
| `driven` | Marks the **sprocket** its band is turned at, rather than one of a driven pair. With none marked, each band takes its rearmost wheel. |
| `brakeTorque` | Adds up over a band: the whole band's brake is the sum of its wheels'. There is no separate hand brake, so `handBrake` pulls the same one. |
| `grip` | Scales a flat pair of friction coefficients rather than a tire's slip curves. This is why a track keeps pulling while it slides, and what lets one climb a bank that would leave a wheel spinning. |
| `steers` / `maxSteerAngle` / `casterAngle` | Inert. A road wheel never turns, and `steerAngle` always reads zero. |
| `slip` / `slideAngle` | Always zero: a road wheel only ever turns as fast as the band it rides, so it has no slip of its own to report. |

Everything else, the suspension especially, works exactly as it does on a wheel, and a tracked machine takes `maxTilt`, `wheelContact`, `engineTorque`, and `topSpeed` unchanged. It cannot also `balance`: a machine on tracks does not lean.

The worked example is [`3D/Physics/Crawler`](../../Examples/3D/Physics/Crawler/): a crawler working a quarry, with its bands drawn as links that scroll at the speed the solver reports.

<a name="ragdolls"></a>

### Ragdolls

A `Ragdoll3D` gives a skinned figure weight. Hand `addRagdoll(from:)` a loaded `Scene` that has a skin and it reads the skeleton, builds one rigid body per joint, and sizes each one from the part of the mesh that joint actually moves. Stepping the world then answers a question the animation cannot: where do the limbs end up when the world has a say?

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

`scene.apply(ragdoll)` is `apply(_:at:)` run backwards: instead of a keyframe track posing the joints, the simulated bodies do. It is exact, because each limb's body stands *at* its joint rather than in the middle of the bone, so writing the pose back has nothing to undo. Everything downstream (skinning, morph targets, per-material parts, materials, shadows, export) works as it always did.

The figure simulates in world space, so draw the scene without a transform of your own if you want it to land where the bodies are.

**What the fit finds.** The shape of each limb comes from the mesh, not from bone lengths: the vertices a joint pulls hardest on are gathered in that joint's own frame, and a capsule is fitted along the direction they spread. A torso comes out thick and a forearm thin even though the two bones are a similar length. `ragdoll.limbs` reports what it found (`name`, `body`, `parent`, `collider`, and where the shape sits inside the body), and `withLimb(_:)` poses the transform stack onto a limb's fitted shape so you can draw the capsules beside the skin:

```swift
for limb in ragdoll.limbs {
    withLimb(limb) {
        if case .capsule(let height, let radius) = limb.collider {
            drawCapsule(radius: radius, height: height)
        }
    }
}
```

**Limp or powered.** Left alone, the joints have limits and nothing else: this is the figure that falls downstairs. `drive(toward:)` gives it back some will, growing a motor on every joint that pulls toward the pose a scene is currently holding:

```swift
target.apply(walk, at: time)          // where the animation wants the limbs
ragdoll.drive(toward: target, strength: effort)
world.step(dt: deltaTime)
figure.apply(ragdoll)                 // where they actually ended up
```

Keep the target scene and the drawn scene apart (a `Scene` is a value type, so a second copy is one assignment). A figure driven toward the scene it was just posed from has nowhere to pull, and the pose it is chasing has to be re-established each frame.

`strength` is the most torque a joint may use, in newton-metres, and is the expressive knob: high and the figure will not be moved, low and heavy limbs sag out of the pose, which is how a figure reads as tired rather than switched off. `goLimp()` cuts the power, and `pose(from:)` puts every limb back where a scene has it, which is how a figure is stood up again.

Nothing drives the root, so a powered figure still falls as a whole: the motors hold its *shape*, not its place. To keep one on its feet, make the root limb kinematic (`ragdoll.limbs[0].body.kind = .kinematic`) and it hangs from its hips like a puppet. Setting `ragdoll.kind = .kinematic` instead makes the whole figure follow the driven pose exactly, shoving whatever is in its way.

**Limits and joints.** Every joint is a `.swingTwist`, opened at the `swing` and `twist` the call was given and retunable one at a time while the figure hangs:

```swift
world.addRagdoll(from: figure, swing: 50 * .pi / 180, twist: -0.3...0.3)
ragdoll.limit("forearmL", swing: 10 * .pi / 180)     // an elbow, not a shoulder
```

A dense rig (a hand with twenty finger bones) does not need twenty bodies. Name the joints that should get one and the rest ride the nearest limb above them rigidly, keeping their pose and their share of the flesh:

```swift
world.addRagdoll(from: figure,
                 joints: ["hips", "spine", "chest", "head",
                          "armL", "forearmL", "armR", "forearmR",
                          "legL", "shinL", "legR", "shinR"])
```

**Among the other bodies.** A ragdoll's limbs are ordinary bodies: they collide, they turn up in `world.contacts`, and they can be picked and dragged with `grabBody(at:in:)`. They are kept out of `world.bodies`, since a sketch draws the figure's mesh rather than the capsules under it; `ragdoll.bodies` is the list. Each figure gets its own collision group, so a limb never fights the one it hangs off (a thigh sits inside the pelvis and they simply ignore each other) while two figures collide normally. `applyImpulse(_:)` shoves the whole figure at once, and `world.remove(ragdoll)` takes it and its limbs away together.

The worked example is [`3D/Physics/Ragdoll`](../../Examples/3D/Physics/Ragdoll/): a figure that stands and waves while its joints are powered, collapses when they are not, and can be dragged around by an arm either way.

<a name="softbodies"></a>

### Soft bodies

Everything above moves as one rigid piece. A **`SoftBody3D`** does not: its state lives in its vertices, which are simulated particles held together by springs, so it drapes, folds, and squashes instead of turning up somewhere else with the same shape. Cloth and a beach ball are the two ends of the same idea.

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

`drawSoftBody(_:)` draws `softBody.mesh`, which is the source mesh with the simulation's positions and freshly derived normals. Everything else the mesh carried rides through untouched, so a textured sheet stays textured while it moves, and every renderer feature (materials, shadows, reflections, export) applies exactly as it does to any other mesh.

**Coincident vertices merge into shared particles.** Ollin's mesh generators are flat shaded: every triangle carries its own copies of its corners, so a generator mesh's triangles share no vertex index at all. `addSoftBody` welds by position first, so a `Mesh.box` becomes eight particles rather than twenty-four loose ones. `particleCount` reports what the simulation actually runs on; `positions` still comes back one per *source* vertex, in the source mesh's order.

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
| `iterations` | solver passes per step; more is stiffer and steadier |
| `vertexRadius` | how far a particle's own body reaches past its position |

`stiffness` and `bend` are separate because they are separate: a bedsheet barely stretches at all and folds freely, which is `stiffness: 1, bend: 0`. `pressure` needs a closed surface to fill, so it does nothing on a sheet (`isClosed` reports which you have, and setting it on an open one notes once and is ignored); `1` just holds the body's own weight up, `2` to `4` reads as a firm ball that still dents. `pressure`, `iterations`, and `vertexRadius` are all live, so a ball can deflate while you watch.

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

- **It turns up in `world.contacts`.** A cloth landing on a crate reports a `began` with a point and an approach speed, and a `ended` when it comes off, exactly like anything else; `cloth.touching`, `.contacts`, `.entered`, and `.exited` read the same lists a body's do, and a sensor sees a cloth sail into it. Two details are its own. A soft body has no one velocity at the moment its first particle lands, so `speed` is the speed the whole surface arrived at. And where a settled *pile of crates* drops its touches when it falls asleep, a settled cloth **keeps** its list: the solver stops asking a sleeping soft body who it is against, which is not the same as it having let go.
- **It floats.** [Water](#water) pushes each of its particles up on its own, and each particle rides the surface directly above it, so a raft follows the shape of a swell rather than one plane through its middle. What decides how high it rides is `density`, relative to the water's the same way a collider's is. A *closed* surface works its own out from the mass and the volume it holds, so a beach ball just floats; a sheet holds no volume to work one out from, so it starts as heavy as water (lying awash) and one line makes it a raft:

  ```swift
  raft.density = 0.3        // rides high; above 1 it sinks
  ```

  A sheet's area for its weight is enormous, which is exactly what drag measures, so a cloth heavier than water sinks slowly and a floating one is carried along by a current rather than left behind by it.
- **A query can find it.** `raycast`, `sweep`, and the overlap calls all see soft bodies, so a hanging sheet blocks a sightline and a `Hit3D` may name a `SoftBody3D`. To look through one, name it in `ignoring:` or put it in a collision group the query does not ask as.

**What a soft body still cannot do.** The solver collides them with the rigid bodies around them but not with each other, and not with themselves, so a sheet folded double will pass through its own layers (which reads as a flicker where the two lie together). Impulses, joints, and grabs do not reach one, and `body(under:in:)` answers only for solids (use `grabSoftBody(at:in:)`). Tearing is not offered, because a real tear has to split a shared vertex in two and rebuild the surface, which the solver has no way to do while it runs.

The worked examples are [`3D/Physics/Drape`](../../Examples/3D/Physics/Drape/) (a banner pegged to a washing line that flaps in a gusting wind, a sheet thrown over a crate, and a beach ball you can let the air out of) and [`3D/Physics/Raft`](../../Examples/3D/Physics/Raft/) (a cloth raft riding a swell with cargo on it, a sounding line that stops at her deck, and a harbour gate that reports her sailing through).

<a name="water"></a>

### Water

A world can have water the same way it has ground: one property, and nothing opts in.

```swift
world.water = Water(level: 0)
```

Everything already in the world starts floating. What floats and what does not comes from the `density` each body was built with, measured against the water's, so it is a number you were already setting:

```swift
world.addBody(.box(width: 1, height: 1, depth: 1), at: Vector3(0, 4, 0),
              density: 0.3)   // a cork: rides with a third of it under
world.addBody(.box(width: 1, height: 1, depth: 1), at: Vector3(2, 4, 0),
              density: 3)     // a stone: goes to the bottom
```

The waterline is not something you tune. A body of density `d` settles with fraction `d` of itself submerged, because that is the volume it has to displace to hold its own weight up: a barrel at `0.5` floats half under, one at `0.8` rides low with a fifth of it dry. `Water.density` is the same relative scale bodies use, where `1` is water, so raising it to `1.3` for brine floats every one of them higher without touching the bodies.

**The knobs.**

| | |
|---|---|
| `level` | the height of the still surface. Animate it for a tide; bodies asleep at the old level wake and follow. |
| `density` | how heavy the water is, `1` being water and the default body material. |
| `linearDrag` | how hard it resists a body dragged through it. This is what makes something dropped in settle rather than bob for ages. |
| `angularDrag` | the same for turning, which is what stops a long shape rocking too long after it lands. |
| `flow` | a current, in units per second, that carries everything afloat along. |
| `waves` | a rolling swell, or `nil` for a flat calm. |

Drag is worth a moment because it is the difference between water and a trampoline. With `linearDrag: 0`, a crate dropped in oscillates about its waterline and never stops. The default `0.5` reads like water: it dips, comes back up, and settles within a second or two.

**A swell.** `Water.Waves` gives the surface a shape, and it carries whatever is riding it:

```swift
world.water = Water(level: 0, waves: Water.Waves(amplitude: 0.25,
                                                 wavelength: 8, speed: 1.5))
```

The same surface is available to draw, which is the point of `waterMesh`: it hands back the very surface the bodies are floating on, so the swell you see and the swell they ride cannot drift apart.

```swift
if let surface = world.waterMesh(extent: 40) {
    fill(Color(hex: 0x2C7C96))
    material(.dielectric(roughness: 0.3))
    drawMesh(surface)
}
```

`waterHeight(at:)` asks the same question for a single point, for sitting something exactly on the waterline. Both read the surface as it stands this frame; `world.waterPhase` is the clock behind it, if a shader needs to move in step.

**Riding higher than it should.** `Body3D.buoyancy` multiplies what the water would otherwise do to one body: `1` is what its density says, `2` floats it as though it were half as heavy, `0` sinks it whatever it is made of. Reach for `density` first and keep this for the one crate that has to bob higher than the rest.

**Cloth floats too.** A [soft body](#softbodies) is floated particle by particle, since it has neither the one mass nor the one shape the rigid path works from, and each particle rides the surface directly above it rather than a plane through the body's middle, so a raft follows the swell instead of being curled by it. Its own `density` decides how high it rides: derived from mass and volume for a closed surface (a beach ball just floats), and `1` for a sheet, which holds no volume to derive one from, so `raft.density = 0.3` is what makes a sail into a raft. Drag bites much harder on cloth than on a crate, because a sheet's area for its weight is enormous: a heavy one sinks slowly and a floating one is carried by a current rather than left behind by it.

**What the water leaves alone.** Sensors, static and kinematic bodies, and a character's capsule are not floated: a detector volume and a walking figure go where the sketch puts them, not where the water would. The water itself is an ocean rather than a pool: everything below `level` is water, out to the horizon, so a container of water needs its own walls built from static bodies (which is all a harbour is).

One thing worth knowing about sleeping. A floating body settles at its waterline and then goes to sleep, which is what you want (it stops costing anything and holds its level exactly). If you move the water afterwards, by changing the level or any other setting, everything afloat is woken so it can follow. A swell wakes only what it actually washes over, which is why a stone that has sunk to the bottom stays asleep under a rolling sea.

The worked examples are [`3D/Physics/Flotsam`](../../Examples/3D/Physics/Flotsam/) (crates from cork to nearly waterlogged riding a swell at their own depths, a stone anchor on the bottom, and a current carrying the lot past) and [`3D/Physics/Raft`](../../Examples/3D/Physics/Raft/), where the thing afloat is a cloth. Drag either about.

<a name="snapshots"></a>

### Saving and loading

Some arrangements are worth keeping. A heap of stones that took four hundred steps to settle, a stack knocked into a shape you liked, a scene you spent a minute nudging into place by hand: none of it can be written down as code, and running the simulation again does not give it back. `snapshot()` captures the whole world as it stands, and `restore(_:)` puts it back:

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

The snapshot's own `bodyCount` and `jointCount` say what is in it before anything is restored, and `PhysicsSnapshot(data:)` / `init(contentsOf:)` / `init(resource:in:)` read one back. Anything that is not a snapshot is refused rather than half-read, and a snapshot that stops short leaves the world that is already standing alone.

**Restoring is exact.** A restored body is in the same pose, moving at the same speed, spinning the same way, and, if it had settled, still asleep, so a saved heap does not shudder back into shape on the way in. A world stepped on from a restore lands exactly where the one that was never interrupted does. It goes through the ordinary `addBody` and `connect` calls, so a restored world is one you could have built by hand, and a joint keeps the zero it was made at: a door saved standing half open is still half open, and still stops where it used to.

**What comes back.** Every rigid `Body3D` with its collider, pose, velocity, and every knob `addBody` takes (kind, sensor, density, friction, restitution, freedom, gravity scale, path checking, group, buoyancy); every `Joint3D` between them, gears and racks included; the collision-group table with its rules; and the world's `gravity`, `ground`, `bounce`, `maxTimestep`, `unitsPerMeter`, and `water`.

**What does not.** Characters, vehicles, ragdolls, and soft bodies are each built from something a snapshot has no way to carry (a rig, a wheel layout, a skinned scene, a mesh), so they are left out, with a note naming what was skipped; add them back after restoring. A grab is a hand on a body rather than part of the world, and contacts are worked out again by the next `step(dt:)`, so neither is saved. Motors are not saved either: `drive(at:)` and friends are things a sketch says, usually every frame, so say them again.

**The bodies are new objects.** `restore(_:)` empties the world first, so any `Body3D` or `Joint3D` you were holding is gone; take them from `world.bodies` and `world.joints` again. They come back in the order they were saved in, so an index still names the same body, and each one still knows its own `collider`, which is usually all a drawing loop needs.

This is also the honest answer to determinism. Simulating is reproducible within one build, but the solver runs in floating point, and a toolchain that moves one last bit moves the last bounce, which a toppling stack magnifies into a different heap. A saved arrangement has nothing left to compute, so it comes back the same anywhere. Continuing from a restore is exact for the pose and the motion; the solver's in-flight contact bookkeeping is not carried, so a scene captured mid-collision may drift a little where a settled one cannot.

The worked example is [`3D/Physics/Cairn`](../../Examples/3D/Physics/Cairn/): a heap of stones laid one at a time, restored with **R**, written to a file with **S**, and read back with **L**, so quitting and running the sketch again finds the same cairn standing.

<a name="grabbing"></a>

### Grabbing with the mouse

Reaching into the scene is two sketch calls: one to pick up, one to drag.

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

`grabBody(at:in:)` casts a ray from the active camera through the canvas point, hangs the body it hits on a soft drag spring at the touched point, and remembers how deep into the view that point sat; `dragGrab(_:to:)` then moves the body in the screen-parallel plane at that depth, so dragging feels like sliding it across the glass. The probe without the pickup is `body(under:in:)`, which returns the body and the world point the ray touched. World-space dragging without a camera is the lower-level `world.grab(_:at:)` plus the joint's `target`.

The camera drag and the body drag both want the mouse, so sketches that grab usually set a hand-placed `perspective(...)` rather than `cameraControl()`.

<a name="drawing"></a>

### Drawing bodies

`withBody(_:)` wraps `withState` and moves the 3D transform stack to the body's pose, so the block draws in body-local space and every renderer feature (materials, shadows, export) applies untouched:

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

The simulation is deterministic within a build: the same setup stepped the same way reproduces exactly, which is what the seeded-variations story needs live. Exact poses can shift across toolchain rebuilds, so physics scenes aren't pinned by pixel snapshots; the behavioral test suite pins the solver instead, and [a snapshot](#snapshots) is how an arrangement is kept for good.

Worked examples: [`3D/Physics/Stack`](../../Examples/3D/Physics/Stack/) (a crate pyramid under cannon fire), [`3D/Physics/Tumble`](../../Examples/3D/Physics/Tumble/) (a mixed-solid pile you can drag), [`3D/Physics/Chain`](../../Examples/3D/Physics/Chain/) (a wrecking ball on a ball-jointed chain), [`3D/Physics/Windmill`](../../Examples/3D/Physics/Windmill/) (a motor-driven compound blade cross batting balls through limited, spring-shut swing gates), [`3D/Physics/Rockslide`](../../Examples/3D/Physics/Rockslide/) (rocks tumbling down eroded heightfield terrain), [`3D/Physics/Trigger`](../../Examples/3D/Physics/Trigger/) (a scoring hoop and a loaded tray, both sensors, with every knock ringing at the speed it landed), [`3D/Physics/Ragdoll`](../../Examples/3D/Physics/Ragdoll/) (a skinned figure that stands and waves, or collapses, depending on whether its joints are powered), [`3D/Physics/Drape`](../../Examples/3D/Physics/Drape/) (a banner in the wind, a sheet over a crate, and a beach ball you can deflate), [`3D/Physics/Sightlines`](../../Examples/3D/Physics/Sightlines/) (a lamp that lights only the crates it can see, a drone holding its clearance by sweep, and a pulse that shoves whatever a sphere overlaps), and [`3D/Physics/Cairn`](../../Examples/3D/Physics/Cairn/) (a heap of stones saved to a file and put back exactly).
