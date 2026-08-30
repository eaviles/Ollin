#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Drawing](./README.md) → `The frequency domain`</sup>

---

## The frequency domain

A picture is a grid of pixels. It is also a sum of waves, and the Fourier transform is how
you get from one reading to the other. `Filter.fourier()` writes the second reading out, and
`Filter.inverseFourier()` reads it back, both on the GPU.

The reason to make the trip is that some things are hard on one side and easy on the other.
Blur, sharpen, and every filter that acts on *scale* is one multiplication in the frequency
domain. So is convolution against any kernel you can draw. And a field can be built there
from nothing but a description of its energy, which is how the [ocean](../3D/Ocean.md) is
made.

### Contents

- [Quick start](#quick-start)
- [What comes back](#what-comes-back)
- [Filtering by scale](#filtering)
- [Building a field from its spectrum](#synthesis)
- [The rules](#rules)
- [What it costs](#cost)
- [How it works](#how-it-works)

<a id="quick-start"></a>
### Quick start

```swift
let plate = makeRenderTarget(width: 512, height: 512)
withTarget(plate) {
    background(.black)
    fill(.white)
    drawCircle(256, 256, 90)
}

let spectrum = plate.filtered(.fourier())          // what the picture is made of
drawImage(spectrum.filtered(.spectrum()).image, 0, 0)   // and what that looks like
```

The picture that comes back is a map of scales rather than of places: slow, wide gradients
sit near the middle, and fine detail out at the edges.

<a id="what-comes-back"></a>
### What comes back

**A spectrum is data, not a picture.** Each texel holds two numbers, the real and imaginary
parts of one wave, in the red and green channels. Drawing it directly shows almost nothing,
because the middle of it is thousands of times the rest. `Filter.spectrum(gain:)` is the
view: the strength of each wave, compressed by a logarithm. Raise `gain` until the faint
high frequencies come up out of the black.

**The lowest frequency is in the middle.** The transform's own ordering puts it in the
corner and wraps the negative frequencies around the edges, which is right for the
arithmetic and unreadable as a picture, so the pass moves it to the middle. A mask drawn
over the result therefore covers what it looks like it covers.

**One channel goes in, one comes out.** A transform works on one signal and a color layer is
three, so `.fourier(of:)` names the channel: `.luminance` (the default, the linear-light
brightness a picture's structure lives in), or `.red` / `.green` / `.blue` / `.alpha`. What
comes back through `.inverseFourier()` is gray for the same reason. Run three transforms if
you need the color.

<a id="filtering"></a>
### Filtering by scale

Multiplying a spectrum keeps some waves and drops others, and multiplying is what a mask
does:

```swift
let mask = makeRenderTarget(width: 512, height: 512)
withTarget(mask) {
    background(.black)
    fill(.white)
    drawCircle(256, 256, 30)          // keep the middle: the slow waves
}

let soft = plate.filtered(.fourier())
    .combined(with: mask, .mask())
    .filtered(.inverseFourier())
```

Keep the middle and the picture comes back soft. Invert the mask (white outside, black
inside) and the broad tones go instead, leaving the edges. A ring keeps one band of scales
and nothing else, which no ordinary blur can do.

Two things are worth knowing before reaching for this over `.gaussianBlur`. A hard-edged
mask rings: cutting a band off sharply makes the ripples around every edge that the third
panel of the example shows, and softening the mask's own edge softens them. And the
transform costs far more than a separable blur, so the reason to come here is a filter that
cannot be written any other way, not a faster blur.

<a id="synthesis"></a>
### Building a field from its spectrum

The inverse transform on its own is a generator: write a spectrum, transform it, and a field
comes out. That is more useful than it sounds, because the physics of many natural surfaces
is written as a spectrum. A wind-driven sea is measured as how much water stands at each
wavelength and heading, never as a list of waves, so one inverse transform of that
measurement *is* the sea. [The ocean](../3D/Ocean.md) is that, and nothing else.

<a id="rules"></a>
### The rules

- **The layer must be square, and its side a power of two.** 256, 512, 1024. The butterfly
  halves the length at every rung, so anything else has no ladder to climb. A layer that
  does not fit comes back untouched with a note naming its size, rather than as a black
  rectangle. `makeRenderTarget(width: 512, height: 512)` is how you make one.
- **A round trip is the picture that went in.** The transform is exact to float32 through
  all sixteen rungs of a 256 square, which is inside one 8-bit level.
- **The spectrum layer is float32, not the usual half float.** The sum a transform builds is
  the whole picture added up, and the middle of a 512 square runs to hundreds of thousands.
  It is a normal layer in every other way: it filters, combines, and draws.

<a id="cost"></a>
### What it costs

A transform is `2 · log2(n)` fullscreen passes over an `n` square layer, so a 256 square is
16 passes and a 512 square is 18. Each pass reads two texels and writes one. On the machines
this was written on a 256 square transform costs well under a millisecond, and a round trip
with a mask in the middle is 33 passes.

<a id="how-it-works"></a>
### How it works

The ladder is the Stockham autosort form of the radix-2 Cooley-Tukey transform, written as a
*gather*: each pass reads the two texels its output depends on and writes one, so a fragment
shader can run it with no scatter and no separate bit-reversal pass. The rows are
transformed first, then the columns, which is what makes a 2D transform a sequence of 1D
ones.

Both complex fields a texel can hold (red-green and blue-alpha) are transformed together,
since the butterfly reads them the same way. Nothing in the public surface uses the second
pair, but the ocean does: it carries the height in one and the two sideways shifts in the
other, and pays for one transform rather than two.

---

Worked example: [`Examples/Effects/Fourier`](../../Examples/Effects/Fourier/Sketch.swift).

See also [Effects](Effects.md) for the layer, filter, and combine substrate this is built
on, [The ocean](../3D/Ocean.md) for the field it builds, and
[Measured distance fields](DistanceFields.md) for the other pass that turns a layer into
data rather than a picture.
