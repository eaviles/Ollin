#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Concepts](./README.md) → `Light and color`</sup>

---

## Light and color

A `Color` you write is an sRGB color, which is the kind of number a display takes. In the middle of a frame, Ollin works in linear light instead, where a number is proportional to the light it stands for. The last pass of the frame converts back and puts the picture on screen.

You can write sketches for a long time without thinking about any of this. It is still worth one screen of reading, because it explains why a few things behave better here than they do elsewhere.

### Why the middle is linear

sRGB numbers are not proportional to light. Mid-gray, 128 of 255, carries about a fifth of the light of white rather than half of it. So adding or averaging numbers like that directly gives the wrong answer. Two lights sum too bright, a blur comes out darker than what went in, and a half-covered edge reads too dark.

Shaders therefore convert the colors you give them into linear light, and every shape composites into a floating-point canvas that holds light the same way. That canvas can hold values above 1, because light adds up and a bright thing is allowed to be bright.

### What the last pass does

Once a frame is finished, one pass turns that canvas into the image on screen. The pass does three things, in this order:

1. **Tone-maps.** Values above 1 roll off toward white instead of being cut flat. `toneMap(_:)` chooses the shape of that roll.
2. **Dithers.** A pattern fixed to the pixel position breaks up the step between neighboring output levels, so a smooth ramp does not band.
3. **Encodes to sRGB** and writes to the display.

That is the only point where a frame is reduced to eight bits per channel. Exports run the same pass, which is why an exported file matches the window.

### What follows from it

- **Adding light works.** `blendMode(.add)` with faint marks sums the way light sums. That is what makes an [accumulated](../Drawing/Accumulation.md) canvas read as a long exposure instead of a smear.
- **Blur and bloom keep their brightness.** A blurred layer is blurred in linear light, so it does not darken.
- **Bright can stay bright.** On a display with headroom, [`colorOutput`](../Drawing/ColorOutput.md) presents through Display P3. Highlights then go past white instead of clipping at it.
- **A clear color is a color too.** The background is converted like everything else. So the frame starts from the same light that the shapes composite into.

There is one deliberate exception. Ollin remaps the *coverage* of a thin stroke or a small dot, so that a fine mark does not read faint or beaded. The remap touches partial coverage only, never a color or an alpha you set.

### Read next

- [`HDR & tone mapping`](../Drawing/HDR.md) - the float pipeline and the tone-map curves, with the looks they make.
- [`Color`](../Drawing/Color.md) - the `Color` type, OKLab mixing, ramps, palettes, and colormaps.
- [`Wide gamut & HDR output`](../Drawing/ColorOutput.md) - P3 on screen, highlights past white, HDR video and stills.
- [Guide, Chapter 2](../../Guide/02-Color.md) - color taught as a chapter, with the same idea in pictures.
