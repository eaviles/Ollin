#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Simulation](./README.md) → `Physics3D`</sup>

---

## 3D physics

Rigid bodies inside the 3D scene: crates that stack and topple, balls that roll, chains that swing, all with real contact response. This is the spatial sibling of the [2D physics world](Physics.md)'s rigid side, and it keeps the same shape: build a [`World3D`](#world3d) once, add [`Body3D`](#body3d)s, step it each frame, and draw each body from its pose. It lives in the same satellite, so `import OllinPhysics` brings both.

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
- [Collider3D](#collider3d) - the shape catalog
- [Compound bodies](#compound) - several shapes fused into one body
- [Terrain and scenery](#terrain) - heightfield ground and `Scene` colliders
- [Joints](#joints) - hinges, ball-and-sockets, rods, welds, sliders
- [Motors, limits, and springs](#motors) - powered hinges and sliders, travel stops, springy ends
- [Contacts](#contacts) - what hit what this step, and how hard
- [Sensors](#sensors) - regions that detect without colliding
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
body.isAwake                  // settled bodies sleep until touched

body.applyForce(Vector3(0, 40, 0))      // steady, accumulated for next step
body.applyImpulse(Vector3(2, 0, 0))     // instantaneous kick
body.applyTorque(Vector3(0, 5, 0))      // spin about each axis
```

`userData` is a free slot for whatever the sketch wants to hang off a body (its color, its mesh), and `collider` keeps the shape the body was created with so a drawing loop can match a mesh to it without a parallel array.

<a name="collider3d"></a>

### Collider3D

The local shape of a body, centred on its origin; position and orientation come from the body.

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

`.heightfield` turns a [`Heightfield`](../Generators/Terrain.md) into solid ground, sized exactly like its `mesh(width:depth:height:)`: a `width` × `depth` grid centred on the body's origin, each sample lifted to `height · value`. Collider and drawn mesh trace one surface, so what rolls matches what renders:

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

`.ball` is the 3D-only kind: a ball-and-socket that rotates freely in every direction, the joint of hanging chains and ragdolls. A hinge (`.revolute`) allows rotation only about its axis. Cut any joint with `joint.remove()`.

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

The simulation is deterministic within a build: the same setup stepped the same way reproduces exactly, which is what the seeded-variations story needs live. Exact poses can shift across toolchain rebuilds, so physics scenes aren't pinned by pixel snapshots; the behavioral test suite pins the solver instead.

Worked examples: [`3D/Physics/Stack`](../../Examples/3D/Physics/Stack/) (a crate pyramid under cannon fire), [`3D/Physics/Tumble`](../../Examples/3D/Physics/Tumble/) (a mixed-solid pile you can drag), [`3D/Physics/Chain`](../../Examples/3D/Physics/Chain/) (a wrecking ball on a ball-jointed chain), [`3D/Physics/Windmill`](../../Examples/3D/Physics/Windmill/) (a motor-driven compound blade cross batting balls through limited, spring-shut swing gates), [`3D/Physics/Rockslide`](../../Examples/3D/Physics/Rockslide/) (rocks tumbling down eroded heightfield terrain), and [`3D/Physics/Trigger`](../../Examples/3D/Physics/Trigger/) (a scoring hoop and a loaded tray, both sensors, with every knock ringing at the speed it landed).
