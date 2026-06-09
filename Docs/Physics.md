#### <sup>[Ollin](../README.md) → [Documentation](./README.md) → `Physics`</sup>

---

## Physics

Let motion come from simulation instead of hand-tuned numbers. Physics lives in a separate library so the drawing core carries no extra weight — add `import OllinPhysics` alongside `import Ollin` to reach it.

The model is lightweight and creative, not a game engine: a [`World`](#world) holds [`Particle`](#particle)s (point masses) and the [`Spring`](#spring)s between them, you set the global rules (gravity, an optional container, whether particles collide), and you step it once a frame. It's tuned for "a few hundred bodies that feel right", not exact physical accuracy.

The same `World` also holds a second kind of body. [`Particle`](#particle)/[`Spring`](#spring) is the **soft** side — a Verlet solver good at cloth, chains, and squishy blobs. [`Body`](#rigid-bodies) is the **rigid** side — real rigid bodies that have an orientation, rotate, rest in stable stacks, and link with joints, for the cases the soft model can't reach (a toppling tower, a swinging pendulum). The rigid side is backed by [Box2D](https://box2d.org); both share the world's gravity, walls, and per-frame `step`, and you can use either or both. Skip ahead to [Rigid bodies](#rigid-bodies) if that's what you're after.

The usual shape: build the world once in `setup()`, `step` it and draw from its particles in `draw()`.

```swift
import Ollin
import OllinPhysics

final class Drops: Sketch {
    let world = World()

    override func setup() {
        world.bounds = Rectangle(x: 0, y: 0, width: width, height: height)
        world.collisions = true
        for _ in 0 ..< 200 {
            world.addParticle(at: Vector2(random(width), random(height * 0.3)),
                              radius: 14 * scale)
        }
    }

    override func draw() {
        background(.black)
        world.step(dt: deltaTime)
        fill(.white)
        for p in world.particles {
            drawCircle(center: p.position, radius: p.radius)
        }
    }
}
```

Gravity pulls the discs down, the walls catch them, and `collisions` keeps them from overlapping — they pile up.

### Contents

- [World](#world) — the simulation: bodies, rules, and the per-frame `step`
- [Particle](#particle) — a point mass; position, velocity, mass, pinning
- [Spring](#spring) — a distance link between two particles (cloth, chains, soft bodies)
- [How the solver works](#how-the-solver-works) — Verlet integration and relaxation, in one paragraph
- [Soft bodies](#soft-bodies) — building a squishy blob from springs
- [Rigid bodies](#rigid-bodies) — `Body`, colliders, materials, and joints (the Box2D side)

<a name="world"></a>

### World

```swift
let world = World()
```

The container for everything. You add particles and springs to it, set its rules, and call `step(dt:)` each frame.

**Building it**

```swift
@discardableResult
func addParticle(at position: Vector2, radius: Double = 0, mass: Double = 1) -> Particle
@discardableResult
func connect(_ a: Particle, _ b: Particle, length: Double? = nil, stiffness: Double = 1) -> Spring
func remove(_ spring: Spring)
func remove(_ particle: Particle)
func removeAll()

var particles: [Particle] { get }
var springs: [Spring] { get }
```

`addParticle` returns the [`Particle`](#particle) so you can pin it, push it, or wire it into a spring. A `radius` of `0` (the default) makes a non-colliding point; give it a positive radius to collide as a disk. `connect` links two particles with a [`Spring`](#spring), defaulting its rest length to their current spacing.

**The rules**

```swift
var gravity: Vector2 = Vector2(0, 980)   // points per second², y-down
var drag: Double = 0.01                  // velocity damping, 0…1
var bounds: Rectangle?                   // optional container; nil lets bodies leave
var bounce: Double = 0.5                 // wall restitution, 0…1
var collisions: Bool = false             // push particles apart as solid disks
var iterations: Int = 8                  // relaxation passes per step
var maxTimestep: Double = 1.0 / 30       // clamp on dt, for stability
```

- **`gravity`** is a constant acceleration on every unpinned particle. Set `.zero` for a weightless, free-floating field.
- **`drag`** stands in for air friction: `0` conserves motion (things drift forever), a small value bleeds energy so they settle.
- **`bounds`** keeps particles inside a rectangle, accounting for each one's `radius`; `bounce` is how much speed they keep off a wall (`0` sticks, `1` is lossless).
- **`collisions`** turns on disk-vs-disk separation, broad-phased through a spatial hash so it scales to thousands of bodies. It's off by default — a cloth doesn't want its own points colliding, and it's a per-frame pass — so you opt in for packings and piles. Points with `radius == 0` never collide.
- **`iterations`** is how hard the solver works to hold springs and collisions together. More makes stiff stacks and tight packings firmer, at a linear cost.

**Stepping**

```swift
func step(dt: Double)
```

Advance the simulation by `dt` seconds — pass `deltaTime`. A `dt` of `0` (a paused or first frame) does nothing; a large one is clamped to `maxTimestep` so a stutter or a window drag doesn't launch everything off-screen.

<a name="particle"></a>

### Particle

```swift
let p = world.addParticle(at: Vector2(540, 200), radius: 24)
```

A point mass — the body the world moves. You usually make one with `World.addParticle`, then read its `position` to draw.

```swift
var position: Vector2          // where it is now
var velocity: Vector2 { get }  // implicit, as a per-step displacement
var radius: Double             // collision radius (0 = a non-colliding point)
var mass: Double               // heavier resists being pushed
var pinned: Bool               // held in place (an anchor)
var userData: Any?             // hang your own data off it

func applyForce(_ force: Vector2)   // accumulate a force for the next step
func push(_ amount: Vector2)        // add to velocity (a per-step displacement)
func place(at point: Vector2)       // teleport without imparting velocity
@discardableResult func pin() -> Particle
@discardableResult func unpin() -> Particle
```

Motion is **Verlet**: a particle doesn't store a velocity, it keeps its previous position, and the velocity is the gap between the two. That's why there are two ways to move one. `place(at:)` teleports it (moving the previous position along with it, so no velocity is imparted); `push(_:)` *adds* velocity by nudging the previous position. To throw a particle, place it and then push it.

```swift
p.place(at: Vector2(100, 100))   // set it down, still
p.push(Vector2(8, 0))            // now flick it to the right
```

`pin()` anchors a particle: gravity and springs no longer move it, but it still acts on whatever it's connected to. It's how you hang a cloth from its top edge or fix a pivot. `userData` lets you attach a colour, an index, or any per-body state without a parallel array.

<a name="spring"></a>

### Spring

```swift
let s = world.connect(a, b)        // holds their current distance
s.stiffness = 0.4                  // springy instead of rigid
```

A link that tries to hold two particles a fixed distance apart — a cloth thread, a chain segment, a soft-body strut.

```swift
let a: Particle
let b: Particle
var length: Double         // the rest distance it pulls back to
var stiffness: Double      // 0…1; 1 is a rigid stick, less gives
var strain: Double { get } // signed: 0 at rest, + stretched, − compressed
```

With `stiffness` at `1` the link behaves like a rigid stick; lower it and the link gives, springing back over a few frames. `strain` reads how far it's stretched right now, handy for tinting a cloth by stress.

<a name="rigid-bodies"></a>

### Rigid bodies

Where a [`Particle`](#particle) is a soft point with no orientation, a [`Body`](#body) is a proper rigid body: it has an `angle`, spins, rests in stable stacks, and bounces off other bodies with real contact response. It's what you reach for when the soft model can't do the job — a tower of blocks that topples, a hinged chain, a pile of tumbling shapes. The rigid side is backed by [Box2D](https://box2d.org), wrapped behind Ollin's own types and measured in sketch points.

```swift
import Ollin
import OllinPhysics

final class Tower: Sketch {
    let world = World()

    override func setup() {
        world.gravity = Vector2(0, 2600)
        world.bounds = bounds                       // the floor and walls
        for row in 0 ..< 7 {
            world.addBody(.box(width: 100, height: 44),
                          at: Vector2(width / 2, height - 60 - Double(row) * 46))
        }
    }

    override func draw() {
        background(.black)
        world.step(dt: deltaTime)
        fill(.white)
        for body in world.bodies {
            withState {
                translate(body.position)
                rotate(body.angle)                  // real rotation, not a fake spin
                drawRect(center: .zero, width: 100, height: 44)
            }
        }
    }
}
```

The pattern is the same as particles: build in `setup()`, `step` and draw from `world.bodies` in `draw()`. Each body's look is yours to hang off `userData` (its colour, its drawn size), then drawn from its `position` and `angle`.

**Adding bodies**

```swift
@discardableResult
func addBody(_ collider: Collider, at position: Vector2,
            kind: Body.Kind = .dynamic, density: Double = 1,
            friction: Double = 0.3, restitution: Double? = nil) -> Body

var bodies: [Body] { get }
```

- **`collider`** is the body's shape (below). **`kind`** is `.dynamic` (moved by forces — the default), `.static` (immovable: walls, ground, a hinge anchor), or `.kinematic` (moved only by a velocity you set).
- **`density`** sets the mass (heavier bodies shove lighter ones), **`friction`** is surface grip (`0` slick … `1` grippy), and **`restitution`** is bounciness `0…1`, defaulting to the world's `bounce`.

**Colliders**

```swift
enum Collider {
    case circle(radius: Double)
    case box(width: Double, height: Double)
    case capsule(from: Vector2, to: Vector2, radius: Double)   // a rounded stadium
    case polygon([Vector2])                                    // convex, ≤ 8 points
}
```

Geometry is given in body-local points (centred on the body's origin); the body's `position` and `angle` place it. A `.polygon` is made convex for you (its convex hull is taken), so concave input is rounded out rather than rejected.

**The Body**

```swift
var position: Vector2          // centre, in points
var angle: Double              // orientation, radians (clockwise, y-down)
var velocity: Vector2          // points per second (a real velocity)
var angularVelocity: Double    // radians per second
var mass: Double { get }
var kind: Body.Kind            // .dynamic / .static / .kinematic
var userData: Any?

func applyForce(_ force: Vector2)     // steady push (thrust, wind)
func applyImpulse(_ impulse: Vector2) // instant kick (a hit, a launch)
func applyTorque(_ torque: Double)    // spin it
```

**Shared rules and units**

The rigid side reads the same `gravity`, `bounds` (as walls), `bounce` (wall and default contact restitution), and `drag` (as body damping) you already set, and rides the same `step(dt:)`. One knob is its own:

```swift
var pixelsPerMeter: Double = 100
```

Box2D works in meters and behaves best for objects roughly 0.1–10 m. `pixelsPerMeter` bridges that to sketch points — the default of 100 puts a 100-point shape at 1 m, its sweet spot — so you keep thinking in points. (The Verlet particle side works in points directly and ignores this.)

**Joints**

Link two bodies with a constraint, or grab one with the cursor:

```swift
@discardableResult
func connect(_ a: Body, _ b: Body, _ kind: JointKind) -> Joint
@discardableResult
func grab(_ body: Body, at point: Vector2) -> Joint

enum JointKind {
    case revolute(at: Vector2)                        // a free hinge at a world point
    case distance(from: Vector2, to: Vector2,
                  length: Double? = nil, stiffness: Double = 1)   // a rod (soft < 1)
    case weld                                          // lock together rigidly
    case prismatic(at: Vector2, axis: Vector2)         // a slider along an axis
}
```

`revolute` is the workhorse — chain it down a line of links for a rope or pendulum, anchor the first to a `.static` body to hang it. `distance` holds two anchors a fixed span apart, softening to a spring below `stiffness: 1`. `grab` returns a [`Joint`](#joint) you steer by setting its `target` each frame (point it at the cursor) and `remove()` to let go:

```swift
let held = world.grab(body, at: Vector2(mouseX, mouseY))
// each frame while dragging:
held.target = Vector2(mouseX, mouseY)
// to release:
held.remove()
```

See the `Stack`, `Tumble`, and `Chain` examples for the whole thing — a toppling pyramid, a pile of mixed shapes, and grabbable swinging chains.

<a name="body"></a>
<a name="collider"></a>
<a name="joint"></a>

<a name="how-the-solver-works"></a>

### How the solver works

Each `step` integrates every particle forward (time-corrected Verlet, so a wandering frame rate doesn't change how fast things move), then runs a handful of **relaxation** passes that pull springs back toward their length, push overlapping disks apart, and keep everything inside `bounds`. Because every constraint is solved by nudging *positions*, the velocity follows for free — a bounce, a spring's recoil, and a collision all just move points, and the implicit Verlet velocity carries the result into the next frame. It's the approach behind cloth and soft-body demos the web over, and it stays entirely in Ollin's value-type idiom.

<a name="soft-bodies"></a>

### Soft bodies

A squishy blob is a small composition: a hub particle, spokes out to a ring of rim particles, and springs around the rim. Slack spokes let it deform, the rim springs keep it roughly round, and giving the rim particles a radius (with `world.collisions = true`) stops blobs passing through each other.

```swift
func makeBlob(at center: Vector2, radius: Double) -> [Particle] {
    let sides = 16
    let hub = world.addParticle(at: center, mass: 3)
    let rimRadius = radius * sin(.pi / Double(sides))   // adjacent rims just touch

    var rim: [Particle] = []
    for s in 0 ..< sides {
        let angle = Double(s) / Double(sides) * .tau
        let p = world.addParticle(at: center + Vector2(angle: angle, length: radius),
                                  radius: rimRadius)
        rim.append(p)
        world.connect(hub, p, stiffness: 0.2)            // spoke (springy)
    }
    for s in 0 ..< sides {
        world.connect(rim[s], rim[(s + 1) % sides], stiffness: 0.6)   // rim ring
    }
    return rim
}
```

Draw the rim as a smooth filled outline and you have a wobbling jelly:

```swift
drawCurve(rim.map(\.position), closed: true)
```

See the `Blobs` and `Packing` examples for the whole thing.
