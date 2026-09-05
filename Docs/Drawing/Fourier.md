#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Drawing](./README.md) → `The frequency domain`</sup>

---

## The frequency domain

A picture is a grid of pixels. It is also a sum of waves, and the Fourier transform takes
you from one description to the other. `Filter.fourier()` turns a layer into its waves, and
`Filter.inverseFourier()` turns them back into a picture. Both run on the GPU.

The reason to make that trip is that some work is hard on one side and easy on the other.
Blur, sharpen, and every other filter that acts on *scale* become one multiplication in the
frequency domain. Convolution against any kernel you can draw becomes one multiplication
too. You can also build a field there from nothing but a description of its energy, which is
how the [ocean](../3D/Ocean.md) is made.

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

The picture that comes back maps scales rather than places. Slow, wide gradients sit near
the middle, and fine detail sits out at the edges.

<a id="what-comes-back"></a>
### What comes back

**A spectrum is data, not a picture.** Each texel holds two numbers in the red and green
channels, the real and imaginary parts of one wave. Drawing it directly shows almost
nothing, because the middle of it is thousands of times larger than the rest.
`Filter.spectrum(gain:)` gives you a view of it instead, showing the strength of each wave
compressed by a logarithm. Raise `gain` until the faint high frequencies come up out of the
black.

**The lowest frequency is in the middle.** The transform's own ordering puts it in the
corner and wraps the negative frequencies around the edges. That order is right for the
arithmetic but unreadable as a picture, so the pass moves the lowest frequency to the
middle. A mask you draw over the result then covers the frequencies it looks like it covers.

**One channel goes in, one comes out.** A transform works on a single signal, and a color
layer holds three, so `.fourier(of:)` names the channel to use. The channels you can name
are `.luminance`, `.red`, `.green`, `.blue`, and `.alpha`. `.luminance` is the default, and
it is the linear-light brightness that a picture's structure lives in. What comes back
through `.inverseFourier()` is gray for the same reason. Run three transforms if you need
the color.

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
inside) and the broad tones go instead, which leaves the edges. A ring keeps one band of
scales and drops everything else, which no ordinary blur can do.

Two things are worth knowing before you use this instead of `.gaussianBlur`. First, a
hard-edged mask rings. Cutting a band off sharply makes ripples around every edge, which the
third panel of the example shows, and softening the mask's own edge softens them. Second,
the transform costs far more than a separable blur. Come here for a filter that cannot be
written any other way, not for a faster blur.

<a id="synthesis"></a>
### Building a field from its spectrum

The inverse transform on its own is a generator. Write a spectrum, transform it, and a field
comes out. That is useful because the physics of many natural surfaces is written as a
spectrum in the first place. A wind-driven sea is measured as how much water stands at each
wavelength and heading, never as a list of waves, so one inverse transform of that
measurement gives you the sea. [The ocean](../3D/Ocean.md) is built that way and no other.

<a id="rules"></a>
### The rules

- **The layer must be square, and its side a power of two.** 256, 512, and 1024 all work.
  The butterfly halves the length at every rung, so any other size cannot be halved all the
  way down. A layer that does not fit comes back untouched, with a note naming its size,
  rather than as a black rectangle. Make one with
  `makeRenderTarget(width: 512, height: 512)`.
- **A round trip gives you back the picture that went in.** The transform stays accurate to
  float32 through all sixteen rungs of a 256 square, and that is inside one 8-bit level.
- **The spectrum layer is float32, not the usual half float.** The sum a transform builds is
  the whole picture added up, so the middle of a 512 square runs to hundreds of thousands.
  In every other way it is a normal layer, so you can filter it, combine it, and draw it.

<a id="cost"></a>
### What it costs

A transform is `2 · log2(n)` fullscreen passes over an `n` square layer, so a 256 square
takes 16 passes and a 512 square takes 18. Each pass reads two texels and writes one. On the
machines this was written on, a 256 square transform costs well under a millisecond. A round
trip with a mask in the middle is 33 passes.

<a id="how-it-works"></a>
### How it works

The ladder is the Stockham autosort form of the radix-2 Cooley-Tukey transform, written as a
*gather*. Each pass reads the two texels its output depends on and writes one, so a fragment
shader can run it with no scatter and no separate bit-reversal pass. The rows are
transformed first and the columns second, which is what turns a 2D transform into a sequence
of 1D ones.

A texel can hold two complex fields, one in red and green and one in blue and alpha, and
both are transformed together because the butterfly reads them the same way. Nothing in the
public surface uses the second pair, but the ocean does. It carries the height in one pair
and the two sideways shifts in the other, so it pays for one transform rather than two.

---

Worked example: [`Examples/Effects/Fourier`](../../Examples/Effects/Fourier/Sketch.swift).

See also [Effects](Effects.md) for the layer, filter, and combine substrate this is built
on, and [The ocean](../3D/Ocean.md) for the field it builds.
[Measured distance fields](DistanceFields.md) is the other pass that turns a layer into data
rather than a picture.
