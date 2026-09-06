#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Drawing](./README.md) → `Light in a flat sketch`</sup>

---

## Light in a flat sketch

Draw a scene into one layer and some lamps into another, and `Combine.light` computes how
much light reaches every pixel. The result is an ordinary layer, so you can draw, filter,
and combine it like any other.

Nothing in the result is drawn by hand. The shadows, the falloff, the soft edges, and the
color a lit wall casts onto its neighbor all come from the same measurement. Because they
come from one measurement, they stay consistent with each other, as real light is.

### Contents

- [Quick start](#quick-start)
- [The two layers](#the-two-layers)
- [What you get without asking](#what-you-get)
- [The parameters](#the-parameters)
- [In a compose block](#compose)
- [What it costs](#cost)
- [What it will not do](#limits)
- [How it works](#how-it-works)

<a id="quick-start"></a>
### Quick start

```swift
let room = makeRenderTarget()
withTarget(room) {
    noStroke()
    fill(Color(hex: 0x2E6F5E))
    drawRect(300, 500, 480, 40)
}

let lamps = makeRenderTarget()
withTarget(lamps) {
    noStroke()
    fill(.white)
    drawCircle(mouseX, mouseY, 18)
}

drawImage(room.combined(with: lamps, .light()).image, 0, 0)
```

Move the pointer around, and the bar casts a shadow that turns with it. The shadow is
sharp where it meets the bar and soft further away.

<a id="the-two-layers"></a>
### The two layers

**The base layer is the scene.** Whatever you draw there is solid, and its alpha sets how
much of a ray it stops. A shape drawn at half opacity lets half the light through. An empty
layer lets all of the light through, which means it is a room with nothing in it.

**The aux layer is the lamps.** Whatever you draw there gives off light in its own color, so
a warm circle makes warm light and a blue circle makes blue light. The amount of light comes
from the color's own brightness, so white at `brightness: 4` gives four times the light of
white at 1.

A lamp is also an object in the scene, so it stops light as well as making it. Two lamps
with a wall between them do not light each other through the wall.

**The result is the light**, not the scene with light added. So draw that result as your
frame. A surface appears in the result because light lands on it and the surface gives some
of that light back. The `bounces` parameter controls that return. With no bounce, every
surface stays black and only the lamps are visible.

<a id="what-you-get"></a>
### What you get without asking

- **Shadows that soften with distance.** A shadow has a hard edge next to the shape that
  casts it. Further away, the same edge spreads over many pixels, because a pixel there can
  see more of the lamp. This comes from one measurement, not from a blur laid over a hard
  shadow.
- **Falloff.** The further a pixel is from a small lamp, the less of the circle of directions
  the lamp covers. So the light halves as the distance doubles. A wide lamp falls off more
  slowly, because it stays wide for longer. You do not have to set anything for that.
- **Color that travels.** With `bounces` at 1 or more, every lit surface gives its own color
  back into the room. A red wall makes the floor beside it red, and a green wall makes it
  green.
- **Light through a gap.** A row of shapes with gaps between them cuts the light into beams,
  and the beams fan out as real beams do. You do not draw the beams yourself.
- **A cost that does not follow the scene.** One lamp and two hundred lamps cost the same,
  and so do ten shapes and ten thousand. The cost depends on the size of the layer and on
  how far light is allowed to travel.

<a id="the-parameters"></a>
### The parameters

```swift
scene.combined(with: lamps, .light(reach: 600, brightness: 4, bounces: 1,
                                   sky: Color(white: 0.05), quality: .default))
```

- **`reach`** how far light travels, in pixels. `nil`, the default, reaches across the whole
  layer. This is the speed parameter, because a shorter reach removes rungs from the ladder
  of fields the answer is built on. That ladder is explained under How it works. A shorter
  reach also looks like a smaller room, because the light stops past it.
- **`brightness`** scales the lamps before anything is traced. Raise it when a small lamp has
  to fill a large space. Values above 1 are normal here, because the frame is
  [tone mapped](HDR.md) at the end like any other frame.
- **`bounces`** how many times light comes back off what it lands on. `0` leaves every surface
  black, which gives the plain shadow look. `1` is the default, and it is what makes a room
  take the color of its walls. More bounces give a softer result, and each one costs another
  pass over the whole ladder.
- **`sky`** the light that arrives from beyond the reach of the field. Clear, the default,
  gives a dark room. Any color looks like a lit room with a window, or like an outdoor scene.
  That color is what fills the parts of the picture no lamp reaches.
- **`quality`** how closely the light is measured: `.performance`, `.default`, or `.detail`.
  The tiers are relative to the hardware, like every other quality tier. The setting controls
  how far apart the probes sit and how many steps a ray may take. An export raises `.default`
  to `.detail`.

<a id="compose"></a>
### In a compose block

Inside `compose { }`, the same operation is a modifier on the layer being lit, and the lamps
go in an `aside`:

```swift
compose {
    layer {
        fill(Color(hex: 0x2E6F5E))
        drawRect(300, 500, 480, 40)
    }
    .lit(by: aside { fill(.white); drawCircle(mouseX, mouseY, 18) }, brightness: 4)
}
```

<a id="cost"></a>
### What it costs

The times below were measured on an M2 at 1080 by 1080 in a release build. Each time covers
the whole operation: the field, the ladder, and the bounce.

| quality | no bounce | one bounce |
| --- | --- | --- |
| `.performance` | 7.8 ms | 11.3 ms |
| `.default` | 13.1 ms | 23.4 ms |
| `.detail` | 42.0 ms | 79.6 ms |

A second bounce costs about as much as the first. Each ray widens into a cone. That cone
costs nothing measurable at `.performance` and `.default`, and up to a tenth more at
`.detail`. A shorter `reach` is cheaper, because the ladder gets shorter. A smaller layer is
much cheaper. Half the width and half the height is a quarter of the work. So
`makeRenderTarget(scale: 0.5)` is the first thing to try when a sketch runs too slowly.

<a id="limits"></a>
### What it will not do

- **Inside a solid, you see the light on its nearest face.** Light stops at a surface, so
  light never reaches the inside of a shape. What is drawn there instead is the light just
  outside its nearest face. That is exactly right for a thin wall. For a wide round shape
  lit unevenly, the middle is where two sides meet, so a soft seam can show there.
- **A lamp is opaque.** If you want to see through a lamp, draw it into the scene layer as
  well, with the alpha you want it to have. Keep the lamps layer for the light itself.
- **Only what is in the layer exists.** A ray that leaves the layer meets the `sky` and
  nothing else. So a scene that runs off the edge is lit as if it stopped at the edge.
- **Fine detail needs closely spaced probes.** At `.performance`, the probes sit four pixels
  apart, and around a small bright lamp that spacing looks blocky at native size. At
  `.default` the probes sit two pixels apart, and in an export they sit one pixel apart.

<a id="how-it-works"></a>
### How it works

The technique is **radiance cascades**. It is worth knowing how radiance cascades work,
because the parameters follow from it.

To know the light at a point, you need many probes close to a lamp and few far from it. You
also need few directions close to the lamp and many far from it. So the answer is built as a
ladder of fields. Each field holds a single ring of distance around every point it samples.
The first rung has a probe every pixel or two, and each probe looks four ways over a short
span. Every rung above it halves the probes along each axis and quadruples the directions.
Its span is four times as long, and it begins where the rung below it ended. Dividing the
probes by four and multiplying the directions by four cancel out, so every rung is the same
size, however far it reaches.

The rays are marched against a [measured distance field](DistanceFields.md) of the scene.
That is why the cost does not follow how much was drawn. A ray crosses an empty room in one
step, whatever stands outside the room. Each ray is a thin cone rather than a line, and it
stands for the wedge of directions between its neighbors. A lamp the ray passes counts by
the share of that wedge the lamp covers. A line, by contrast, either meets a lamp or misses
it. With lines, one probe sees a lamp a few rays wide with a different number of rays than
the next probe does. A shadow's edge then comes out as cells the size of the probe spacing.
The cone reads the fraction instead, so the edge is one smooth ramp.

The technique is Alexander Sannikov's. Ollin implements it from the published description
and credits it in [`ATTRIBUTION.md`](../../ATTRIBUTION.md). The credit covers the
"bilinear fix" as well, which makes each rung's rays end where the rung above them begins.

---

See also [Effects](Effects.md) for the layer and combine substrate this is built on,
[Measured distance fields](DistanceFields.md) for the field the rays march against, and
[HDR & tone mapping](HDR.md) for what happens to light brighter than white.
