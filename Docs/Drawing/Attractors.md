#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Drawing](./README.md) → `Strange attractors`</sup>

---

## Strange attractors & chaotic maps

A strange attractor is the shape a chaotic system settles onto: a bounded path that never repeats, tracing wispy, layered forms like the Lorenz butterfly or the Clifford filigree. Ollin gives you two flavors, both of which hand back plain points you draw however you like.

- **`StrangeAttractor`** is a *continuous* system, a velocity field integrated over time with fourth-order Runge-Kutta. Its orbit is a `[Vector3]`, so it rides the [point-cloud](../3D/3D.md) path through the camera. Lorenz, Rössler, Aizawa, and friends.
- **`ChaoticMap`** is a *discrete* iterated map, a `[Vector2]` orbit you plot as a scatter of points (prettiest accumulated additively into a density field). Clifford, Peter de Jong, Hénon.

Each orbit is a pure function of its starting point and parameters, so a run always reproduces. Pick a system from the built-in factories, or supply your own rule.

### Contents

- [Quick start](#quick-start)
- [StrangeAttractor (continuous)](#strange)
- [ChaoticMap (discrete)](#map)
- [Drawing sugar](#sugar)
- [Your own system](#custom)

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

A continuous system is its **velocity field**: at a phase-space point it returns the instantaneous rate of change `(dx, dy, dz)/dt`. `orbit(count:settle:)` integrates that field from `start` with fixed-step fourth-order Runge-Kutta, dropping `settle` warmup steps first so the path has reached the attractor before you collect points.

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

The orbits live in their own units (Lorenz spans roughly ±25), so center and scale them for the camera, as the [`3D/StrangeAttractor`](../../Examples/3D/StrangeAttractor) example does.

<a name="map"></a>

### ChaoticMap (discrete)

A discrete map is its **iteration rule**: the next point given the current one. `orbit(count:settle:)` just iterates it from `start`. The output stays bounded (the trigonometric maps within roughly ±2 on each axis), so translate and scale it onto the canvas.

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

The four constants reshape these maps completely; nudge them to explore. They look their best accumulated additively (`blendMode(.add)` over [`noClear()`](Accumulation.md)) so repeated visits brighten into filaments.

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

---

See also [`3D`](../3D/3D.md) for the `PointCloud` and camera the continuous orbits ride, [`Accumulation`](Accumulation.md) and [`HDR`](HDR.md) for the additive density build-up the 2D maps want, and [`Voronoi`](Voronoi.md)/[`Grid`](Geometry.md) for the other geometry helpers.
