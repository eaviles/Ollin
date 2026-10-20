#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Generators](./README.md) → Textures</sup>

---

## Textures

A material texture is a surface a sketch asks for by name: a rust bloom, a verdigris patina, a terrazzo floor. The generators that paint them live on the [Effects](../Drawing/Effects.md#generate) page (`.rust`, `.verdigris`, `.terrazzo`, and the `.bubbleWrap` filter beside them). This page is about the geometry under two of them, which a sketch can hold, draw, and plot: a **`Patina`** is the blooms a corrosion grows from, and a **`Terrazzo`** is the chips of a floor. Each is scattered from a seed, and each generator takes one, so the blob or the chip a plotter draws is the blob or the chip the screen shows.

```swift
let blooms = Patina.scatter(in: canvasRectangle, count: 12, seed: 3)
drawImage(generate(.rust(blobs: blooms)).image, 0, 0)
stroke(.black); noFill()
for blob in blooms.blobs { drawPolygon(blob.outline.points) }   // lands on the paint
```

<img src="../../Guide/Images/18-YourFirstShader/MaterialTextures.jpg" alt="Three labeled tiles: orange rust blooms with darker cores, blisters, and a lit edge over gray steel; the same blooms in the greens of verdigris with a pale tide line over bronze; and a terrazzo floor of red, slate, ochre, and cream chips in three sizes, the larger ones hatched" width="680">

### Contents

- [A patina's blooms](#patina)
- [A terrazzo's chips](#terrazzo)
- [The generators that read them](#generators)
- [A crease in a sheet](#crease)

<a name="patina"></a>

#### A patina's blooms

```swift
let region = Rectangle(x: 0, y: 0, width: 600, height: 400)
let blooms = Patina.scatter(in: region, count: 12, radius: 40 ... 140, seed: 1)
let blob = blooms.blobs[0]
blob.outline                     // a closed Contour of 96 points
blob.masses                      // the two nested masses, contours too
blob.blisters                    // [Circle]
blob.boundaryRadius(at: 0.5)     // the outline's radius at an angle
blob.contains(Vector2(100, 80))
blooms.outlines                  // every bloom's outline
```

A **`Patina.Blob`**, a `Blob` for short, is a circle whose radius wavers around it. The outline's radius is the mean `radius` times one plus four harmonics of the angle: two and three waves around for the big lobes, five and eight for the ragged edge (`Patina.Blob.harmonics`). Each harmonic has an amplitude in `amplitudes` and a start in `phases`. `boundaryRadius(at:)` reads the outline's radius at an angle. `swing` is how far it can wander from the mean as a fraction, so the outline always lies between `radius * (1 - swing)` and `radius * (1 + swing)`. `outline` samples it as a closed contour.

Inside the bloom sit two **`masses`**, the darker cores. They are the same waver at `Patina.Blob.massScales` of the radius, 0.62 and 0.36, with their phases turned so they are not pure copies. Their centers are moved by `massOffset`, a fraction of the radius for the first and 1.7 times it for the second. Two to four **`blisters`**, small circles inside the bloom, complete it. `tone` is a draw in 0…1 the generators use to vary each bloom's color a little.

`scatter(in:count:radius:seed:)` throws up to `count` blooms over a region, each with a mean radius drawn from `radius`. A bloom is placed only where its center is at least three quarters of the two radii away from every bloom already placed. Blooms overlap at their ragged edges and never stack, and a crowded region takes fewer than asked. The same seed makes the same patina, down to every blister. The `using:` form takes any random generator, and `Patina(blobs:)` builds one from blobs of your own when the scatter should follow your own rule, each made with `Patina.Blob(center:radius:amplitudes:phases:massOffset:blisters:tone:)`.

<a name="terrazzo"></a>

#### A terrazzo's chips

```swift
let region = Rectangle(x: 0, y: 0, width: 600, height: 400)
let floor = Terrazzo.scatter(in: region, chipRadius: 44, density: 0.55, gap: 3, tones: 5, seed: 1)
let chip = floor.chips[0]
chip.shape                       // the chip as a Shape, for drawShape or a clip
chip.points                      // its corners
chip.tier                        // 0 the largest tier, 2 the smallest
chip.tone                        // an index into a palette
floor.outlines
```

A **`Terrazzo.Chip`**, a `Chip` for short, is a polygon inside a circle. `center` and `radius` are the circle, and every corner lies within it. `rotation` is the angle of the first corner, and `corners` holds each corner's distance from the center as a fraction of the radius, in 0.72…1, going around. A chip has five to eight corners, no two chips are alike, none is regular, and one corner is always on the circle. `sides`, `points`, `outline`, `shape`, and `contains(_:)` read it.

`scatter(in:chipRadius:density:gap:tones:seed:)` lays the floor by **dart throwing** (Cook, 1986) in three size tiers, largest first. The circles are at `chipRadius` and at `Terrazzo.tierScales` of it, 0.55 and 0.3. Each tier places chips at random until together they cover about `density` of the region in the shares `Terrazzo.tierShares`, half, three tenths, and two tenths, or until its darts keep missing. A chip lands only where its circle clears every chip already placed by `gap`, so **no two chips ever touch**, and the floor reports the `gap` it was laid with. Each chip takes one of `tones` colors by index. Dart throwing jams before a floor is full, so a density past about 0.5 lays little more than 0.5. The `using:` form takes any random generator, and `Terrazzo(chips:gap:)` builds a floor from chips of your own, each made with `Terrazzo.Chip(center:radius:rotation:tier:tone:corners:)`.

<a name="generators"></a>

#### The generators that read them

`.rust(blobs:...)`, `.verdigris(blobs:...)`, and `.terrazzo(chips:...)` take the scatter and paint it: the GPU reads the very blobs and chips the sketch holds, so an outline stroked from one lands on the paint, and a scatter rebuilt every frame (a bloom growing, a floor laid chip by chip) is repainted every frame. With no scatter handed in, each generator scatters its own over the layer from its `seed` with the same calls, so `generate(.rust(seed: 3))` paints the blooms `Patina.scatter(in: layer, count: 14, radius: 40 ... 150, seed: 3)` builds over a rectangle the layer's size, byte for byte. Every parameter of the paint (the tones, the lip, the blisters, the tide, the hatching) is on the [Effects](../Drawing/Effects.md#generate) page, beside the catalog they belong to.

<a name="crease"></a>

#### A crease in a sheet

The fourth texture is a fold rather than a scatter. `Heightfield.creased(along:width:amplitude:)` presses a crease into any heightfield along a polyline, shaped by one closed-form kernel (`Heightfield.creaseProfile(at:)`): a cusp with a rounded tip, an asymmetric step that lifts one flank, and a trough two widths out on both sides. The same kernel shapes the folds of `.paperTexture`. It lives on the [Terrain](Terrain.md#crease) page with the rest of `Heightfield`.
