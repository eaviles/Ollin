#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Drawing](./README.md) → `Strange attractors`</sup>

---

## Strange attractors & chaotic maps

A strange attractor is the shape a chaotic system settles onto. It is a bounded path that never repeats, and it traces wispy, layered forms like the Lorenz butterfly or the Clifford filigree. Ollin gives you two flavors, and both hand back plain points you draw however you like.

- **`StrangeAttractor`** is a *continuous* system, a velocity field integrated over time with fourth-order Runge-Kutta. Its orbit is a `[Vector3]`, so it rides the [point-cloud](../3D/3D.md) path through the camera. Lorenz, Rössler, Aizawa, and friends.
- **`ChaoticMap`** is a *discrete* iterated map, a `[Vector2]` orbit you plot as a scatter of points (prettiest accumulated additively into a density field). Clifford, Peter de Jong, Hénon, Gumowski-Mira, Ikeda, hopalong.
- **`AttractorFlow`** runs the same continuous systems on the GPU with a million particles riding the field at once, so the shape arrives as moving material rather than a still curve.

The family's one-dimensional members (the logistic map and friends, with their bifurcation diagrams, cobwebs, and Lyapunov exponents) live in [`IteratedMap`](../Generators/Bifurcation.md).

Each orbit is a pure function of its starting point and parameters, so a run always reproduces. Pick a system from the built-in factories, or supply your own rule.

### Contents

- [Quick start](#quick-start)
- [StrangeAttractor (continuous)](#strange)
- [ChaoticMap (discrete)](#map)
- [Drawing sugar](#sugar)
- [Your own system](#custom)
- [A million at once: AttractorFlow](#flow)
- [The systems in a shader of your own](#shaderlib)

<a name="quick-start"></a>

### Quick start

A Lorenz attractor, integrated once and orbited by the camera:

```swift
var cloud = PointCloud()

override func setup() {
    let path = StrangeAttractor.lorenz().orbit(count: 150_000, settle: 2000)
    cloud = PointCloud(positions: path, color: .white, size: 0.012)
}

override func draw() {
    background(.black)
    cameraShowcase(target: .zero, radius: 24)   // drag to orbit, scroll to zoom
    drawPointCloud(cloud)
}
```

A 2D Clifford map accumulated into a glowing density field:

```swift
override func setup() { noClear(); noStroke() }   // pile onto a persistent canvas

let map = ChaoticMap.clifford()
var p = Vector2(0.1, 0.1)

override func draw() {
    if frameCount == 1 { background(.black) }
    blendMode(.add)
    fill(Color(red: 0.4, green: 0.7, blue: 1, alpha: 0.05))
    var points = [Vector2]()
    for _ in 0..<80_000 {                 // continue the one long orbit
        p = map.next(p)
        points.append(Vector2(width / 2 + p.x * 240, height / 2 + p.y * 240))
    }
    drawPoints(points)
}
```

<a name="strange"></a>

### StrangeAttractor (continuous)

A continuous system is its **velocity field**. At a phase-space point it returns the instantaneous rate of change `(dx, dy, dz)/dt`. `orbit(count:settle:)` integrates that field from `start` with fixed-step fourth-order Runge-Kutta. It drops `settle` warmup steps first, so the path has reached the attractor before you collect points.

```swift
let path = StrangeAttractor.lorenz().orbit(count: 100_000, settle: 1000)
```

| Member | Meaning |
| --- | --- |
| `orbit(count:settle:) -> [Vector3]` | The trajectory: `count` points after `settle` warmup steps. |
| `derivative: (Vector3) -> Vector3` | The velocity field. Sample it for the orbit speed (color by `derivative(p).length`). |
| `start: Vector3` | The initial condition. |
| `step: Double` | The integration time step. |

The built-in systems, each from its published equations with its classic parameters (override any of them):

| Factory | Shape |
| --- | --- |
| `.lorenz(sigma:rho:beta:)` | The original two-lobed butterfly. |
| `.rossler(a:b:c:)` | A single folded band. |
| `.aizawa(a:b:c:d:e:f:)` | A spiralling sphere-and-spindle. |
| `.thomas(b:)` | A looping, axis-symmetric lattice walk. |
| `.halvorsen(a:)` | Three intertwined scrolls. |
| `.dadras(a:b:c:d:e:)` | A four-winged twist. |
| `.chen(alpha:beta:delta:)` | A tightly wound double scroll. |
| `.fourWing(a:b:c:)` | Four lobes meeting at the center. |

The orbits live in their own units (Lorenz spans roughly ±25), so center and scale them for the camera, as the [`3D/StrangeAttractor`](../../Examples/3D/Geometry/StrangeAttractor) example does.

<a name="map"></a>

### ChaoticMap (discrete)

A discrete map is its **iteration rule**, the next point given the current one. `orbit(count:settle:)` just iterates it from `start`. The output stays bounded (the trigonometric maps within roughly ±2 on each axis), so translate and scale it onto the canvas.

```swift
let points = ChaoticMap.clifford(a: -1.4, b: 1.6, c: 1, d: 0.7).orbit(count: 200_000)
```

| Member | Meaning |
| --- | --- |
| `orbit(count:settle:) -> [Vector2]` | The orbit: `count` points after `settle` warmup steps. |
| `next: (Vector2) -> Vector2` | The iteration rule (call it to continue one long orbit across frames). |
| `start: Vector2` | The starting point. |

| Factory | Form |
| --- | --- |
| `.clifford(a:b:c:d:)` | `sin(a·y) + c·cos(a·x)`, `sin(b·x) + d·cos(b·y)`. |
| `.deJong(a:b:c:d:)` | `sin(a·y) - cos(b·x)`, `sin(c·x) - cos(d·y)`. |
| `.henon(a:b:)` | `1 - a·x² + y`, `b·x`. |
| `.gumowskiMira(mu:a:b:)` | `y + a·(1 - b·y²)·y + G(x)`, `G(x') - x`, with `G(x) = mu·x + 2(1-mu)·x²/(1+x²)²`. |
| `.ikeda(u:)` | A spin by `t = 0.4 - 6/(1 + x² + y²)`: `1 + u·(x·cos t - y·sin t)`, `u·(x·sin t + y·cos t)`. |
| `.hopalong(a:b:c:)` | `y - sgn(x)·√\|b·x - c\|`, `a - x`. |

The constants reshape these maps completely, so nudge them to explore. They look their best accumulated additively (`blendMode(.add)` over [`noClear()`](Accumulation.md)) so repeated visits brighten into filaments. Each has its own character. Gumowski-Mira wanders a near-conservative sea of islands into many-petaled filigree: `mu` picks the blossom, and the *starting point* picks which structure the orbit wanders. The long transient is the picture, so plot it with no `settle`. The richest plates layer several orbits from different seeded starts. Ikeda folds everything into one swirl, within roughly `[-0.4, 1.7] × [-2.2, 0.9]` at the default `u = 0.9`. Hopalong hops around nested rings that keep widening as the orbit runs. Its reach grows slowly with `count`: roughly ±4 after a million steps at the defaults.

<a name="sugar"></a>

### Drawing sugar

For the common cases there are one-call draw verbs, using the current `fill`:

```swift
drawAttractor(.lorenz())            // a point cloud through the camera (needs a `camera`)
drawAttractor(.clifford())          // a 2D scatter at the current `pointSize`
```

`drawAttractor(_ attractor: StrangeAttractor, count:settle:size:)` builds and draws a uniform-color `PointCloud`. For per-point color (by speed or position), build the cloud yourself from `attractor.orbit(...)`. `drawAttractor(_ map: ChaoticMap, count:settle:)` plots the orbit in the map's own coordinate space, so `translate`/`scale` it onto the canvas.

<a name="custom"></a>

### Your own system

Both types take a closure, so any first-order system or iterated map drops in:

```swift
// A custom continuous system.
let spin = StrangeAttractor(start: Vector3(1, 0, 0), step: 0.01) { p in
    Vector3(-p.y, p.x, 0)            // dx/dt = (-y, x, 0): a circle
}

// A custom map.
let mine = ChaoticMap(start: .zero) { p in
    Vector2(sin(2.1 * p.y) - p.x * 0.3, cos(1.7 * p.x))
}
```


<a name="flow"></a>

### A million at once: `AttractorFlow`

`StrangeAttractor` integrates **one** orbit and hands you the points. `AttractorFlow` runs the same field on the GPU under a million particles at once, each on its own trajectory, stepped every frame. Instead of a curve you get the attractor as material: dense where the orbit dwells, thin where it hurries, and visibly flowing along itself.

```swift
var flow: AttractorFlow!

override func setup() {
    flow = attractorFlow(count: 1_000_000, .lorenz())
}

override func draw() {
    background(.black)
    blendMode(.add)                    // let the particles pile into a density plot
    toneMap(.aces)
    cameraShowcase(target: flow.center, radius: flow.extent * 3.4)
    updateAttractorFlow(flow)
    drawParticles(flow)                // camera-facing splats, like a point cloud
}
```

A flow is 3D and rides the camera, so `drawParticles` is a no-op without one. Measured on an M2 at 1080², a million particles step and draw at 55 fps, with 0.2 ms of CPU per frame.

**It sizes and paces itself.** At build the flow integrates one CPU orbit of the same system, and reads everything else off it. Aizawa's whole shape is a unit and a half across, and Lorenz spans fifty. Both open framed, lit, and moving at a sensible speed, with no per-system numbers in your sketch:

| Property | What it is |
| --- | --- |
| `center: Vector3` | The middle of the attractor. Point a camera here. |
| `extent: Double` | How far it reaches. A camera radius of about `extent * 3` frames it. |

Both are percentiles of the orbit rather than its outright extremes. Several of these systems take rare long excursions, so a maximum keeps growing the longer you watch. The four-wing's reach measures 2.0 over 120,000 points and 3.5 over 400,000. A percentile settles instead.

| Knob | Meaning |
| --- | --- |
| `system: AttractorSystem` | Which field. Settable live: the flow re-measures and the particles flow into the new shape. |
| `speed: Double` | Pace, as a multiple of the measured one (1 crosses the attractor about once a second). |
| `size: Double?` | Splat diameter in world units. `nil` derives one from `extent`. |
| `colors: [Color]` | The speed ramp, up to eight stops. |
| `opacity: Double` | How much light one particle contributes. Low, so density reads as tone. |
| `maxSubsteps: Int` | The most Runge-Kutta steps one frame may take. |

**Color is speed, brightness is density.** A particle's color comes from how fast it is moving, and that is what shows the structure. You see the fast outer sweeps against the slow, crowded core. The default stops shift hue and hold their brightness roughly level on purpose, because drawn additively the *brightness* already means density. A ramp that also ran dark to light would put two different facts on one channel. A slow crowded region would then come out looking like a fast empty one.

**Particles start on the attractor**, sampled from a settled orbit and nudged off it by a hair. The nudge is what matters. Exactly on the orbit, every particle rides the same trajectory forever. The picture can only ever be that one curve with dots sliding along it. A hair off it, chaos separates them into a million trajectories within a few laps. Starting them in a box instead would mean watching them fall onto the shape first. How long that takes is the system's own contraction rate. It is a fraction of a second for Lorenz, and a minute of watching nothing for Aizawa.

**The step never outruns the system.** Each frame advances `speed` worth of the system's own time. That time is split into fourth-order Runge-Kutta steps. It takes as many as it needs to keep every step at or under the one the system was published at. Ask for more pace than `maxSubsteps` allows and the flow runs slower than asked, rather than taking a coarser step. A step past that one is a different system. A particle can leave the neighborhood altogether, which wild constants can cause. It is dropped back into the middle rather than flying off, so a stray can never streak the frame.

**Reproducibility** works as it does everywhere on this GPU path. A flow repeats on one machine, but it is not promised frame-exact across GPUs, and there is no pixel snapshot of one. Every system also answers `.attractor`, the CPU `StrangeAttractor` twin with the same constants, for a still plot or a measurement beside the moving one.

See the [`Simulation/Attractor`](../../Examples/Simulation/Attractor) example.

<a name="shaderlib"></a>

### The systems in a shader of your own

The velocity fields and the Runge-Kutta step are part of the [shader library](../Shaders/ShaderLibrary.md). They are spliced into every compute kernel and user shader. So a sketch can ride a chaotic system in a kernel it wrote itself:

```swift
lazy var motes = Particles(count: 500_000, step: """
    float3 p = float3(position, seedA);
    for (int i = 0; i < 3; ++i) {
        OLLIN_RK4_STEP(p, 0.006, ollin_lorenz(_p, 10.0, 28.0, 8.0 / 3.0));
    }
    position = p.xy; seedA = p.z;
""")
```

`OLLIN_RK4_STEP(state, h, derivative)` advances a `float3` one step. `derivative` is an expression in the sample point `_p`, which is how a system's constants reach it. Metal has no function pointers here, so this is a macro like the neighbor iteration. Beside the eight flows sit the six maps: `ollin_clifford`, `ollin_de_jong`, `ollin_henon`, `ollin_gumowski_mira`, `ollin_ikeda`, and `ollin_hopalong`. A map returns the next point outright and needs no integration.

---

See also [`Chaotic maps & bifurcation`](../Generators/Bifurcation.md) for the one-dimensional members of this family (`IteratedMap`: the logistic route to chaos, bifurcation diagrams, cobwebs, Lyapunov exponents), [`3D`](../3D/3D.md) for the `PointCloud` and camera the continuous orbits ride, [`Accumulation`](Accumulation.md) and [`HDR`](HDR.md) for the additive density build-up the 2D maps want, [`Compute`](../Shaders/Compute.md) for the GPU particle path `AttractorFlow` runs on, and [`Voronoi`](Voronoi.md)/[`Grid`](Geometry.md) for the other geometry helpers.
