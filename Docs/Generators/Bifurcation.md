#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Generators](./README.md) → Chaotic maps & bifurcation</sup>

---

## Chaotic maps & bifurcation

The simplest systems that turn chaotic: a one-dimensional map `x' = f(x, r)` iterated over and over, with a dial. At small `r` the orbit settles to a point. Turn the dial and it forks into a 2-cycle, then 4, then 8, faster and faster, until it never repeats at all. `IteratedMap` holds the rule and answers the three classic questions about it.

- What one orbit does, through `orbit` and `cobweb`.
- Where orbits settle across every dial position, through `bifurcation`, the fig-tree diagram.
- Whether a position is truly chaotic, through `lyapunovExponent`.

```
  x                                          .::
  1 ─                              _....--─":::'
      ─._                      _.-"   ..:::::::   the bifurcation diagram:
         "──._            _.-"      .:::::' :::   one dial position per
              "──.__  _.-"  __..--─"::.     .::   column, the settled
                    "|_..--"     ':::::.. .:::'   orbit's values stacked
                      "─.__        ':::::::::     vertically
                           "──._     '::::::::.
  0 ─                           "──----─':::::'
      |            |               |          |
     2.4          3.0            3.57         4    r
```

Everything is a pure function of the map and its arguments, with no randomness anywhere, so every diagram reproduces exactly.

### Contents

- [Quick start](#quick-start)
- [The families](#families)
- [One orbit at a time](#orbit)
- [The bifurcation diagram](#diagram)
- [The Lyapunov exponent](#lyapunov)
- [Your own family](#custom)
- [Practical notes](#notes)

<a name="quick-start"></a>

### Quick start

The logistic map's diagram as faint ink dots, drawn once into a retained batch:

```swift
var plate: Batch?

override func setup() {
    plate = makeBatch {
        noStroke()
        fill(Color(hex: 0x232A4D).withAlpha(0.18))
        pointSize(1)
        drawBifurcation(IteratedMap.logistic())     // sweeps r = 2.4...4
    }
}

override func draw() {
    background(Color(hex: 0xF6F1E7))
    if let plate { drawBatch(plate) }
}
```

Or the fully tonal version as a density image, one call:

```swift
let plate = IteratedMap.logistic().bifurcationImage(width: 1080, height: 720)
```

<a name="families"></a>

### The families

| Factory | Rule | Dial | The picture |
| --- | --- | --- | --- |
| `.logistic()` | `r·x·(1 − x)` | `2.4...4` (domain `0...4`) | The canonical cascade: one line, forks at 3, chaos past 3.5699, the period-3 window at 3.83. |
| `.sine()` | `r·sin(π·x)` | `0.6...1` | The same cascade from a different formula, Feigenbaum's universality in the flesh. |
| `.tent()` | `r·min(x, 1 − x)` | `1...2` | No forks at all: straight from a fixed point into chaos, bands merging. |
| `.gauss(alpha:)` | `exp(−α·x²) + r` | `−1...1` | The mouse: two ears, and a stretch where two attractors coexist. |

Each family carries its canonical sweep window as `parameterRange`, the interval the orbit lives in as `valueRange`, and a default `start`. `valueRange` is the diagram's vertical axis. All three are ordinary `var`s, so retune them freely.

<a name="orbit"></a>

### One orbit at a time

```swift
let values = map.orbit(at: 3.83, count: 48, settle: 2000)   // [Double]
```

`orbit(at:count:settle:from:)` iterates at a fixed dial position, discarding `settle` warmup steps so the transient is gone. At `r = 3.83` the 48 values cycle through just three numbers. At `3.9` they never repeat.

The **cobweb** is the classic way to *watch* one orbit. `cobweb(at:steps:from:)` returns the staircase polyline in map space, with both axes spanning `valueRange`. The staircase runs from the floor up to the curve, across to the diagonal, and up to the curve again. Draw it over the rule's curve, `graph(at:)`, and the diagonal:

```swift
let frame = Rectangle(x: 90, y: 90, width: 500, height: 500)
func place(_ p: Vector2) -> Vector2 { frame.point(u: p.x, v: 1 - p.y) }

drawLine(place(Vector2(0, 0)), place(Vector2(1, 1)))                    // the diagonal
drawPolyline(map.graph(at: 3.4).map(place), closed: false)              // the hump
drawPolyline(map.cobweb(at: 3.4, steps: 40).map(place), closed: false)  // the orbit
```

A converging orbit spirals into the crossing. A 2-cycle traces a square, and chaos scribbles the whole box.

<a name="diagram"></a>

### The bifurcation diagram

<img src="../../Guide/Images/18-IteratedForms/Bifurcation.jpg" alt="The logistic map's bifurcation diagram in dark ink on white: a single settled line forks into two branches, then four, compressing into a gray band of chaos threaded with pale periodic windows, with the forks at 3.0 and 3.45 and the period-3 window at 3.83 labeled" width="680">

Two renderings of the same sweep, both deterministic:

```swift
drawBifurcation(map, over: 3.4...4, in: rect)                 // dots, current fill
let plate = map.bifurcationImage(width: 900, height: 600)     // tonal density image
```

- **`drawBifurcation(_:over:in:columns:perColumn:settle:)`** draws the raw settled values as dots in the current `fill` at the current `pointSize`, mapped into `rect`. The default `rect` is the whole canvas. A translucent fill shades the dense regions darker on its own, and the dots export to SVG/PDF as real geometry for the plotter path. The diagram never changes frame to frame, so a heavy one belongs in a retained batch. The data form behind it is `bifurcation(over:columns:perColumn:settle:) -> [Vector2]`, each point `(r, x)`.
- **`bifurcationImage(width:height:over:samplesPerColumn:settle:)`** bins one long orbit per pixel column and tones the counts with a single global log factor. Periodic orbits print as crisp dark lines, and chaotic bands wash gray, ink on white. Render it once in `setup()` and `drawImage` it.

Both sample the sweep at column *centers*, never the range's exact endpoints. Some families are numerically degenerate exactly there, as the notes explain. Zooming is just a narrower `over:` range. Try `3.82...3.87`: the period-3 window contains its own complete doubling cascade, the whole diagram again in miniature.

<a name="lyapunov"></a>

### The Lyapunov exponent

```swift
let l = map.lyapunovExponent(at: 3.9)     // > 0: chaos
```

The average of `ln |f′(x)|` along the orbit. It is negative where nearby orbits converge, which is a stable cycle. It is positive where they separate exponentially, which is the working definition of chaos. Traced across the sweep window it dips below zero at every periodic window and kisses zero at every fork. For the logistic map it reaches exactly `ln 2` at `r = 4`, and for the tent map it is exactly `ln r`. The estimate uses the family's analytic `derivative` when present, else a central difference. A visit to a point with `f′ = 0` is a superstable orbit. That visit is floored rather than sent to negative infinity, so clamp the trace to your panel when you plot it.

<a name="custom"></a>

### Your own family

Any rule drops in, and the parameter can mean whatever you like:

```swift
let ricker = IteratedMap(parameterRange: 1.5...4, valueRange: 0...5, start: 0.5) { x, r in
    x * exp(r * (1 - x))          // the Ricker spawning model
}
```

Supply `derivative:` too if you want exact Lyapunov exponents. Without it the central difference is fine for smooth rules.

<a name="notes"></a>

### Practical notes

- **Settle is what makes it a diagram.** The sweep discards `settle` iterations per column, 1000 by default, so only the attractor prints. That is the standard practice for these figures. Near a fork, convergence slows to a crawl. If a fork looks smeared, raise `settle`, not `perColumn`.
- **Endpoints can be degenerate, and the sweep avoids them.** At exactly `r = 2` a floating-point tent orbit collapses to 0, one doubled bit at a time. The logistic critical orbit dies in two steps at exactly `r = 4`, which is why the factories start at 0.3 rather than the critical point 0.5. Column-center sampling means a sweep *to* an endpoint never lands *on* it.
- **The Gauss map's diagram depends on `start`.** Part of its range holds two attractors at once, so sweeping with a different `start` genuinely redraws a stretch of the picture. That is the map being honest, not a bug.
- **Costs are small.** A full 1080-column image is a few million arithmetic steps, milliseconds of `setup()` work. The one thing worth avoiding is recomputing a sweep every frame. Hold the `Image`, or record the dots into a [`Batch`](../Drawing/Batches.md).

---

See also [`Strange attractors`](../Drawing/Attractors.md) for the 2D and 3D members of the family (`ChaoticMap`, `StrangeAttractor`), [`Accumulation`](../Drawing/Accumulation.md) for additive density build-up, and [`Export`](../Output/Export.md) for the vector export the dot form feeds.
