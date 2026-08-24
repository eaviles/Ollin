#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Drawing](./README.md) → `Local averages`</sup>

---

## Local averages

"What does the neighborhood around this pixel look like?" is a question with an expensive
obvious answer and a cheap surprising one. The obvious answer reads every pixel in the
neighborhood, so a wide neighborhood costs more than a narrow one. The cheap answer builds
one table first, and then reads any neighborhood, of any size, in four lookups.

That table is a **summed-area table**, and two filters ride on it: `Filter.boxBlur`, which
averages the square around each pixel, and `Filter.adaptiveThreshold`, which cuts each pixel
against the average of its own surroundings instead of against one number for the whole
picture.

<img src="../../Guide/Images/16-LayersAndEffects/LocalAverages.jpg" alt="Three panels. A page of dark bars and dots on pale paper with a light falling across it, bright at the top left and deep in shadow at the bottom right; the same page cut to black and white by one threshold, which swallows the whole shadowed half into solid black; and the same page cut against each pixel's own neighborhood, where every bar and dot survives on clean white paper" width="680">

### Contents

- [Quick start](#quick-start)
- [A blur that does not care how wide it is](#box-blur)
- [A cut that ignores the light](#adaptive-threshold)
- [Choosing the window](#the-window)
- [How it works](#how-it-works)
- [What it costs](#what-it-costs)

<a id="quick-start"></a>
### Quick start

```swift
let layer = renderTarget()
withTarget(layer) {
    background(.white)
    fill(.black)
    drawText("a page of notes", 80, 200)
}

// Average the 601-pixel square around every pixel. Four lookups each.
drawImage(layer.filtered(.boxBlur(radius: 300)).image, 0, 0)

// Or cut the page to two tones, each pixel against its own surroundings.
drawImage(layer.filtered(.adaptiveThreshold()).image, 0, 0)
```

<a id="box-blur"></a>
### A blur that does not care how wide it is

`boxBlur(radius:)` replaces every pixel with the average of the square of that radius around
it. It is the plainest blur there is, and the reason to reach for it is the price rather than
the look:

```swift
layer.filtered(.boxBlur(radius: 4))     // these two
layer.filtered(.boxBlur(radius: 400))   // cost the same
```

A Gaussian blur is the better-looking one, and while the radius stays small it is also the
faster one, so reach for [`gaussianBlur`](Effects.md) there. Come here when the reach is
large, or when the radius has to change while a sketch is running and you do not want the
frame rate changing with it.

Three box blurs in a row approximate a Gaussian closely enough that the eye stops telling
them apart, and that is still three fixed-price passes:

```swift
layer.filtered(.boxBlur(radius: 90))
     .filtered(.boxBlur(radius: 90))
     .filtered(.boxBlur(radius: 90))
```

A window that hangs over the border averages what is really there rather than counting the
empty space outside as black, so the edges of the layer keep their brightness.

<a id="adaptive-threshold"></a>
### A cut that ignores the light

A plain [`threshold`](Effects.md) picks one number and sends every pixel above it to white
and every pixel below it to black. On a photograph of a page lit from one side there is no
number that works: the one that keeps the shadowed corner floods the lit one.

`adaptiveThreshold` compares each pixel with the average of its own neighborhood instead
(Bradley & Roth, 2007). Hard contrast survives that comparison and a slow change in
illumination does not, so both corners come out:

```swift
let page = renderTarget()
withTarget(page) { drawImage(photo, 0, 0) }
drawImage(page.filtered(.adaptiveThreshold()).image, 0, 0)
```

| | |
|---|---|
| `window` | how wide the neighborhood is, in pixels. `nil` (the default) is an eighth of the layer |
| `bias` | the fraction below the local average a pixel must fall before it goes dark. 0.15 by default |
| `invert` | swap the two tones |

`bias` is a *fraction* rather than a distance, and that is what makes the cut survive uneven
light: light falling on a page multiplies what comes back off it, and only a test that scales
with the average is unchanged by a multiplication. Ollin makes that comparison in linear
light, where a change in illumination really is a plain scale.

The two tones carry the layer's own alpha, so a mark drawn on an empty layer binarizes
without the empty part turning into a black rectangle.

<a id="the-window"></a>
### Choosing the window

The window wants to be large enough to hold both ink and paper. If it is smaller than the
marks, the middle of a thick stroke can see nothing but more stroke, decides that is what
paper looks like there, and comes out hollow:

```
window too small          window large enough
┌──────────────┐          ┌──────────────┐
│  ███    ███  │          │  ██████████  │   the same stroke, cut
│  ██      ██  │          │  ██████████  │   at two window sizes
└──────────────┘          └──────────────┘
```

Since the window costs nothing to widen, err on the wide side. The published default of an
eighth of the image is a good starting point for a page of text.

<a id="how-it-works"></a>
### How it works

A summed-area table (Crow, 1984) holds, at every texel, the sum of everything above and to
the left of it, itself included. Once you have it, the sum over any rectangle is two
subtractions and an addition:

```
      A ─────────── B          sum of the shaded box
      │             │            =  D − B − C + A
      │      ┌──────┤
      │      │//////│          A, B, C, D are single lookups
      C ─────┼──────D          in the table, wherever the box is
             │//////│          and however big it is
```

Divide by the area and you have the average. Four lookups, always.

Ollin builds the table by recursive doubling (Hensley et al., 2005). One pass adds what sits
one texel back, the next adds what sits two back, then four, and so on, so a row's whole
running total is carried in about eleven passes rather than a thousand. The same ladder then
runs down the columns. Both techniques are written from those papers and credited in
[`ATTRIBUTION.md`](../../ATTRIBUTION.md).

<a id="what-it-costs"></a>
### What it costs

Two things, and neither of them grows with the window.

**Time.** Building the table is about twenty passes over the layer: roughly 6 ms of GPU time
for a 1080 square. One of these in a frame is comfortable. A dozen are not.

**Precision.** This is the structure's one real weakness, and it is worth knowing which way
it points. A running total spends most of a float's mantissa on itself, so a box sum is a
difference between two large numbers and carries a small *absolute* error. What you see is
that error divided by the area you asked for, so it **falls away as the window grows**. On a
1080 square that is about 7/255 in the worst corner of a 3-pixel window, and under 1.5/255
from 37 pixels up. The narrow end is the weak end, which is convenient: it is the end you
would use a Gaussian for anyway.

---

See also [Effects](Effects.md) for the layer and filter substrate this is built on,
[Measured distance fields](DistanceFields.md) for the other question you can ask of every
pixel of a layer at once, and [Images](Images.md) for getting a photograph into a layer in
the first place.
