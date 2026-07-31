#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Generators](./README.md) → Chladni figures</sup>

---

## Chladni figures

The patterns sand draws on a ringing plate. Bow or drive a square plate at one of its resonant modes and it vibrates everywhere except along its **nodal lines**; loose sand walks off the moving regions and gathers where the plate stands still, tracing the symmetric figures Ernst Chladni catalogued in 1787. Ollin ships the standing-wave field in closed form, both as a per-point function for geometry and as a GPU [`Generator`](../Drawing/Effects.md#generate) that fills a layer with the finished figure.

```
   m 5, n 2 (sand)        m 7, n 3 (sand)         wave
     ~~\    /~~             (  )  (  )          + - + - +
        \  /               ) ~~~~~~ (           - + - + -
     ~~ /  \ ~~             ( ~~~~ )            + - + - +
       /    \              ) ~~~~~~ (           - + - + -
     __/    \__             (  )  (  )          + - + - +
```

### Contents

- [The field](#field)
- [The generator](#generator)
- [Nodal lines as geometry](#geometry)
- [Ringing the plate with sound](#audio)
- [Practical notes](#notes)

<a name="field"></a>

#### The field

```swift
let s = chladni(u, v, m: 5, n: 2)          // -1…1 at plate coordinates 0…1
let s = chladni(u, v, m: 5, n: 2, a: 1, b: -1)   // amplitude mix
```

The closed form superposes a plate mode with its mirror image:

```
s(x, y) = a·cos(nπx)·cos(mπy) + b·cos(mπx)·cos(nπy)
```

normalized so the result spans `-1…1` over plate coordinates `0…1`. The zero set of `s` is the figure. `m` and `n` are the **mode numbers**: integers ring true modes of the square plate (higher numbers ring finer figures), and fractional values are the in-between fields, so animating `m` or `n` melts one figure smoothly into the next. Outside `0…1` the field continues as mirrored plates, seamlessly.

With the default amplitudes `a: 1, b: -1` (a plate driven at its center) the field is antisymmetric across the diagonal: the diagonal itself is always nodal, swapping `m` and `n` negates the field, and `m == n` cancels to zero everywhere; there is no figure, because that drive isn't ringing a mode. Other `a`/`b` mixes weight the two mirrored modes unevenly and open the wider family of figures.

<a name="generator"></a>

#### The generator

```swift
let plate = generate(.chladni(m: 5, n: 2))                    // sand on a dark plate
let wave  = generate(.chladni(m: 7, n: 3, style: .wave, phase: time))
drawImage(plate.image, 0, 0)
```

`generate(.chladni(...))` evaluates the same field per pixel and paints one of two readings:

- **`.sand`** (the default): ink accumulates around the nodal lines with a Gaussian falloff, `weight` wide in field units. `grain` runs the lines from smooth airbrushed ink (`0`) to loose sand speckle (`1`), and as `phase` advances the grains re-throw in small steps, shivering like sand on a ringing plate.
- **`.wave`**: the signed field itself, swinging the antinodes between `background` and `foreground` by `cos(phase)` while the nodal lines hold still; feed `phase` your `time` and the plate breathes.

`scale` above 1 tiles mirrored plates. Like every generator it composes with the effect chain (`generate(_:width:height:)` for an explicit-size layer, `.filtered(...)` to post-process) and, like the design patterns, it animates only by the explicit `phase` you pass, so exports reproduce.

The library mirror `chladni(p, m, n)` is available inside [user shaders](../Shaders/ShaderLibrary.md) (the `noise` module), so a look built on the field carries into per-pixel code.

<a name="geometry"></a>

#### Nodal lines as geometry

The figure's lines are the field's zero contour, and the [marching-squares tracer](Isolines.md) extracts them directly:

```swift
let plate = Rectangle(x: 90, y: 90, width: 900, height: 900)
let lines = isolines(at: 0, in: plate, resolution: 240) { p in
    let uv = plate.uv(of: p)
    return chladni(uv.x, uv.y, m: 5, n: 2)
}
for line in lines { drawPolyline(line.points, closed: line.isClosed) }
```

That yields the figure as plotter-ready `Contour`s for [SVG/PDF export](../Output/Export.md), hatching, or any of the geometry tools. The other classic reading seeds particles at random and walks each downhill on `|s|` (sand marching to the nodes); `chladni` is cheap enough to evaluate per particle per frame.

<a name="audio"></a>

#### Ringing the plate with sound

Physical plates pick their figure by frequency: each `(m, n)` mode rings at its own pitch, rising with the square plate's `m² + n²` eigenvalue. A sketch can borrow that mapping from the [audio analyzer](../Helpers/Audio.md): give every mode in a small table its own frequency, read `magnitude(in:)` around each pitch, and morph the plate toward whichever mode hears the most energy. The `Audio/ChladniResonance` example does exactly this, sweeping a synthesized `Tone` across the resonances so figures snap in and out the way they do under a signal generator on a real plate; swap the tone for an `AudioInput()` and whistling at the Mac sweeps the figures instead.

<a name="notes"></a>

#### Practical notes

- **Pick `m ≠ n`, and mind the diagonal.** Equal modes cancel at the default amplitudes; the sand style then floods the whole plate (an honest reading of a plate that isn't ringing). When animating between modes, keep `m > n` at every stop and the morph never crosses the degenerate diagonal.
- **`(m, n)` and `(n, m)` draw the same figure.** The swap negates the field, and both readings are symmetric in sign, so treat mode pairs as unordered.
- **Deterministic by construction.** The field is a pure function and the generator animates only by `phase`, so a fixed phase exports byte-identically; the sand speckle is a hash of pixel position and phase, no random state.
- **The wave style is the debugging view.** When a figure surprises you, flip to `.wave`: the signed field shows which regions move together and where the sign flips, which makes the mode numbers legible.

---

Related: [`Isolines`](Isolines.md) (nodal lines as contours), [`Effects`](../Drawing/Effects.md) (the generator substrate), [`Audio`](../Helpers/Audio.md) (ringing the plate by ear), [`Noise`](Noise.md) (the field-function family it joins).
