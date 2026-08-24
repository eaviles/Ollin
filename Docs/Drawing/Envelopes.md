#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Drawing](./README.md) → `Envelopes & caustics`</sup>

---

## Envelopes & caustics

**`envelope`** finds the curve a family of lines draws without any of them being it. **`caustic`** is that idea applied to light: the bright line in the bottom of a cup is where the reflected rays crowd, each one grazing past it and none of them being it.

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

The construction is that simple: **the envelope is where consecutive lines cross**. As two members of the family come together, their crossing settles onto the point where the family touches the curve. That means the answer arrives rather than lands: it is off by an amount that falls with the *square* of the step between lines, so doubling the samples quarters the error.

### Contents

- [envelope](#envelope)
- [Reflected and bent rays](#rays)
- [caustic](#caustic)
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

The family, in order, gives back the curve it leans on.

Neighboring lines that run parallel never cross, so **the envelope breaks there**, and the answer is a list of runs rather than one line. Each run is a stretch where the family really does touch something. A family of parallel lines has no envelope at all, and gives back nothing.

Pass `closed: true` when the family comes back to where it started, so the last line is asked about the first.

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

The rays that leave a curve when it is lit. The surface at each point is taken from its two neighbors, so a curve wants enough points to be smooth, and an open curve loses its two ends (they have no two neighbors).

`refractedRays` bends by Snell's law into a material of refractive `index`. **A ray meeting the surface too steeply turns back instead of crossing**, which is total internal reflection, and those rays are left out rather than faked, so the array can be shorter than the curve.

<a name="caustic"></a>

#### caustic

```swift
caustic(off curve: [Vector2], from source: LightSource,
        closed: Bool = false) -> [Contour]

caustic(through curve: [Vector2], from source: LightSource,
        index: Double, closed: Bool = false) -> [Contour]

drawCaustic(off curve: [Vector2], from source: LightSource, closed: Bool = false)
```

The envelope of the rays, which is the bright curve itself. Two classic answers are worth knowing, because they say whether a picture came out right:

- A circle lit from **far away** draws a **nephroid**: two cusps, reaching from half the radius out to the mirror it bounced off.
- A circle lit from a **point on its own rim** draws a **cardioid**, with one cusp.
- A source at the **middle** sends every ray straight back through the middle, so there is no curve at all.

<a name="notes"></a>

#### Practical notes

- **Only the lit side of a closed curve should be handed in.** A whole circle has two families of bounces, the near side and the far side, and they lean on different curves. Feed the stretch of wall the light actually reaches, as an open run, and the picture matches the physics. The `Patterns/Caustic` example shows how to pick that stretch.
- **Sample the curve well.** The error falls with the square of the spacing, so a few hundred points around a circle is comfortable and a few dozen is visibly loose.
- **The rays are ordinary values.** Draw them, cut them, or hand them to the shape booleans: crowding rays drawn faintly under the curve is what makes a caustic read as light rather than as a line.
- The result is `Contour`s, so it strokes, hatches, and exports to SVG for a pen plotter like anything else.

Example: `Patterns/Caustic`. Guide: [Chapter 15](../../Guide/15-ShapesAsMaterial.md).

---

#### Where this comes from

The envelope of a family of lines is classical differential geometry; the discrete construction used here, crossing neighbors, is the one used to draw caustics in practice. The circle's caustics were worked out in the seventeenth century, with Ehrenfried Walther von Tschirnhaus and Christiaan Huygens among the names attached. See [`ATTRIBUTION.md`](../../ATTRIBUTION.md).

#### Go deeper

- [Classic curves](./Curves.md): the nephroid's relatives, and the closed forms that draw them directly
- [Geometry](./Geometry.md): `Contour`, resampling, and the booleans the runs feed
- [Caustics in 3D](../3D/Caustics.md): the same physics rendered as light on a surface rather than as a curve
