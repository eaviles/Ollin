#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Drawing](./README.md) → `Envelopes & caustics`</sup>

---

## Envelopes & caustics

**`envelope`** finds the curve that a family of lines draws. No single line in the family is that curve, but together they trace it out. **`caustic`** applies the same idea to light. The bright line in the bottom of a cup is where the reflected rays crowd together, and each ray only grazes past it.

```swift
for run in caustic(off: circlePoints, from: .parallel(0), closed: true) {
    drawPolyline(run.points)
}
```

```
    \  \  \  |  /  /  /      move a line smoothly and it leans on a curve,
     \  \  \ | /  /  /       touching it once. two neighbors cross right
      \  \  \|/  /  /        about where the family touches, so the
   ----+----*----+-----      crossings of consecutive lines trace it out
```

The construction is that simple: **the envelope is where consecutive lines cross**. As two members of the family come together, their crossing settles onto the point where the family touches the curve. So the answer is close rather than exact. The error falls with the *square* of the step between lines, which means doubling the samples quarters it.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/15-ShapesAsMaterial/RaysLeanOnACurve-dark.jpg">
  <img src="../../Guide/Images/15-ShapesAsMaterial/RaysLeanOnACurve.jpg" alt="Two panels. On the left forty tangent lines of a circle, with the circle they lean on picked out in orange. On the right a circular cup lit from outside, its bounced rays crowding along an orange caustic curve with a cusp" width="680">
</picture>

### Contents

- [envelope](#envelope)
- [Reflected and bent rays](#rays)
- [caustic](#caustic)
- [huygensFront](#huygens)
- [Practical notes](#notes)

<a name="envelope"></a>

#### envelope

```swift
struct Ray2 {
    var origin: Vector2
    var direction: Vector2
    func point(at t: Double) -> Vector2
    func distance(to point: Vector2) -> Double   // to the whole line, both ways
}

envelope(of rays: [Ray2], closed: Bool = false) -> [Contour]
drawEnvelope(of rays: [Ray2], closed: Bool = false)
```

Pass the family in order, and you get back the curve those lines lean on.

Neighboring lines that run parallel never cross, so **the envelope breaks there**. The result is a list of runs rather than one line, and each run is a stretch where the family does touch a curve. A family of parallel lines never crosses anywhere, so it has no envelope and gives back nothing.

Pass `closed: true` when the family comes back to where it started, which crosses the last line with the first.

<a name="rays"></a>

#### Reflected and bent rays

```swift
enum LightSource {
    case point(Vector2)      // throwing rays in every direction
    case parallel(Double)    // all travelling at this angle, from far off
}

reflectedRays(off curve: [Vector2], from source: LightSource,
              closed: Bool = false) -> [Ray2]

refractedRays(through curve: [Vector2], from source: LightSource,
              index: Double, closed: Bool = false) -> [Ray2]
```

These two calls give you the rays that leave a curve when it is lit. The surface at each point is taken from its two neighbors, so the curve needs enough points to be smooth. An open curve loses its two end points, because they have no two neighbors.

`refractedRays` bends each ray by Snell's law into a material of refractive `index`. A ray that meets the surface too steeply **turns back instead of crossing**, which is total internal reflection. Those rays are left out rather than faked, so the array can be shorter than the curve.

<a name="caustic"></a>

#### caustic

```swift
caustic(off curve: [Vector2], from source: LightSource,
        closed: Bool = false) -> [Contour]

caustic(through curve: [Vector2], from source: LightSource,
        index: Double, closed: Bool = false) -> [Contour]

drawCaustic(off curve: [Vector2], from source: LightSource, closed: Bool = false)
```

These calls return the envelope of the rays, which is the bright curve itself. Two classic answers are worth knowing, because they tell you whether a picture came out right:

- A circle lit from **far away** draws a **nephroid**. It has two cusps, and it reaches from half the radius out to the mirror it bounced off.
- A circle lit from a **point on its own rim** draws a **cardioid**, with one cusp.
- A source at the **middle** sends every ray straight back through the middle, so there is no curve at all.

<a name="huygens"></a>

#### huygensFront

```swift
huygensFront(from front: [Vector2], advancing distance: Double,
             closed: Bool = false) -> [Contour]
```

`huygensFront` finds where a wave will be, by Huygens' construction. Every point of the front sends out a wavelet, and the new front is the curve those wavelets lean on. It is the same envelope idea, with circles in place of lines.

```swift
for step in stride(from: 30.0, through: 400, by: 30) {
    for run in huygensFront(from: shore, advancing: -step) { drawPolyline(run.points) }
}
```

This is not the same as moving every point sideways. Where the front curves back on itself, the sideways move folds over. It crosses itself, and **those folded pieces sit inside their neighbors' wavelets rather than on the front**. The construction drops them, because of the rule it is made of. A point of the new front is exactly `distance` from the old front, and no nearer to any part of it. That rule is what turns a folded offset into a real wavefront. It is also why a front travelling into a hollow eventually tears and comes to a point. The tear starts exactly when the front has travelled the radius the curve bends at, which is where a curved mirror's focus is.

A positive distance travels along the front's own normal, so a ring built by increasing angle grows. A negative distance goes the other way. The result is a list of runs, because a front breaks into pieces as it travels.

**The check runs against every segment of the old front**, so the cost grows with the square of the point count. A few hundred points is comfortable. Build a wall of fronts in `setup()` rather than in `draw()`.

<a name="notes"></a>

#### Practical notes

- **Pass in only the lit side of a closed curve.** A whole circle has two families of bounces. The near side and the far side lean on different curves. Pass the stretch of wall the light actually reaches, as an open run, and the picture matches the physics. The `Patterns/Caustic` example shows how to pick that stretch.
- **Sample the curve well.** The error falls with the square of the spacing. A few hundred points around a circle is comfortable, and a few dozen is visibly loose.
- **The rays are ordinary values.** You can draw them, cut them, or pass them to the shape booleans. Drawing the crowding rays faintly under the curve is what makes a caustic read as light rather than as a line.
- **A sampled curve is a run of chords sitting a little inside it.** A front measured against them is right to about one sagitta. `huygensFront` compares each moved point against its *own* two segments rather than against the distance you asked for. That comparison keeps a front moving into a bend from throwing itself away.
- The result is `Contour`s, so you can stroke it, hatch it, and export it to SVG for a pen plotter like any other geometry.

Examples: `Patterns/Caustic`, `Patterns/Wavefront`. Guide: [Chapter 15](../../Guide/15-ShapesAsMaterial.md).

---

#### Where this comes from

The envelope of a family of lines is classical differential geometry. The discrete construction used here, crossing neighbors, is the one people use to draw caustics in practice. The circle's caustics were worked out in the seventeenth century. Ehrenfried Walther von Tschirnhaus and Christiaan Huygens are two of the names attached to that work. The wavelet construction is Huygens' own, from his *Traite de la Lumiere* of 1690. See [`ATTRIBUTION.md`](../../ATTRIBUTION.md).

#### Go deeper

- [Classic curves](./Curves.md): the nephroid's relatives, and the closed forms that draw them directly
- [Geometry](./Geometry.md): `Contour`, resampling, and the booleans that the runs feed into
- [Caustics in 3D](../3D/Caustics.md): the same physics rendered as light on a surface rather than as a curve
