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
- [Joints](#joints) - hinges, ball-and-sockets, rods, welds, sliders
- [Motors, limits, and springs](#motors) - powered hinges and sliders, travel stops, springy ends
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
.hull([Vector3])                        // convex hull of at least 4 points
.mesh(mesh)                             // exact triangles; static bodies only
```

`capsule` and `cylinder` stand along the body's y axis (rotate the body to orient them), and their `height` matches `drawCapsule`/`drawCylinder`, so the mesh call takes the collider's own numbers. A `.mesh` collider is for scenery (terrain, a loaded set piece): it has no volume for mass, so a dynamic body created with one is pinned in place; moving shapes want `.hull` or a primitive.

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

Worked examples: [`3D/Physics/Stack`](../../Examples/3D/Physics/Stack/) (a crate pyramid under cannon fire), [`3D/Physics/Tumble`](../../Examples/3D/Physics/Tumble/) (a mixed-solid pile you can drag), [`3D/Physics/Chain`](../../Examples/3D/Physics/Chain/) (a wrecking ball on a ball-jointed chain), and [`3D/Physics/Windmill`](../../Examples/3D/Physics/Windmill/) (a motor-driven mill batting balls through limited, spring-shut swing gates).
