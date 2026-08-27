#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Concepts](./README.md) → `Light and color`</sup>

---

## Light and color

A `Color` you write is an sRGB color, the kind of number a display takes. Everything in the middle of a frame is linear light instead, where a number is proportional to the light it stands for. The last pass of the frame converts back and puts the picture on screen.

You can write sketches for a long time without thinking about this. It is worth one screen because it explains why a few things behave better here than they do elsewhere.

### Why the middle is linear

sRGB numbers are not proportional to light. Mid-gray, 128 of 255, carries about a fifth of the light of white rather than half of it. Add or average numbers like that directly and the answer is wrong. Two lights sum too bright, a blur comes out darker than what went in, and a half-covered edge reads too dark.

So shaders convert the colors you give them into linear light, and every shape composites into a floating-point canvas held that way. The canvas can hold values above 1, because light adds up and a bright thing is allowed to be bright.

### What the last pass does

Once a frame is finished, one pass turns that canvas into the image on screen. It does three things in order:

1. **Tone-maps.** Values above 1 roll off toward white instead of being cut flat. `toneMap(_:)` chooses the shape of that roll.
2. **Dithers.** A pattern fixed to the pixel position breaks up the step between neighboring output levels, so a smooth ramp does not band.
3. **Encodes to sRGB** and writes to the display.

That is the only point where a frame is reduced to eight bits per channel. Exports run the same pass, which is why a file matches the window.

### What follows from it

- **Adding light works.** `blendMode(.add)` with faint marks sums the way light sums, which is what makes an [accumulated](../Drawing/Accumulation.md) canvas read as a long exposure instead of a smear.
- **Blur and bloom keep their brightness.** A blurred layer is blurred in linear light, so it does not darken.
- **Bright can stay bright.** On a display with headroom, [`colorOutput`](../Drawing/ColorOutput.md) presents through Display P3 and lets highlights go past white rather than clipping at it.
- **A clear color is a color too.** The background is converted like everything else, so the frame starts from the same light the shapes composite into.

There is one deliberate exception. The *coverage* of a thin stroke or a small dot is remapped so a fine mark does not read faint or beaded. It touches partial coverage only, never a color or an alpha you set.

### Read next

- [`HDR & tone-mapping`](../Drawing/HDR.md) - the float pipeline and the tone-map curves, with the looks they make.
- [`Color`](../Drawing/Color.md) - the `Color` type, OKLab mixing, ramps, palettes, and colormaps.
- [`Wide gamut & HDR output`](../Drawing/ColorOutput.md) - P3 on screen, highlights past white, HDR video and stills.
- [Guide, Chapter 2](../../Guide/02-Color.md) - color taught as a chapter, with the same idea in pictures.
