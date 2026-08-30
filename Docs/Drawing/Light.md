#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Drawing](./README.md) → `Light in a flat sketch`</sup>

---

## Light in a flat sketch

Draw a scene into one layer and some lamps into another, and `Combine.light` works out how
much light reaches every pixel. What comes back is an ordinary layer, so it draws, filters,
and combines like any other.

Nothing in the result is drawn by hand. The shadows, the falloff, the soft edges and the
color a lit wall throws onto its neighbor all come out of the same measurement, which is
why they agree with each other the way light does.

### Contents

- [Quick start](#quick-start)
- [The two layers](#the-two-layers)
- [What you get without asking](#what-you-get)
- [The knobs](#the-knobs)
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

Carry the pointer around and the bar throws a shadow that turns with it, sharp where it
meets the bar and soft further away.

<a id="the-two-layers"></a>
### The two layers

**The base layer is the scene.** Whatever you draw there is solid, and its alpha is how much
of a ray it stops. A shape drawn at half opacity lets half the light through. An empty layer
lets all of it through, which is a room with nothing in it.

**The aux layer is the lamps.** Whatever you draw there gives light off in its own color, so
a warm circle makes warm light and a blue one makes blue light. Brightness is the color's
own: white at `brightness: 4` is four times the light of white at 1.

A lamp is a thing in the world, so it stops light as well as making it. Two lamps with a
wall between them do not light each other through it.

**The result is the light**, not the scene with light added. Draw it as the frame. A surface
appears in it because light lands on it and it gives some back, which is the `bounces` knob;
with no bounce every surface stays black and only the lamps are seen.

<a id="what-you-get"></a>
### What you get without asking

- **Shadows that soften with distance.** Beside the shape that casts it, a shadow has a hard
  edge. Further away the same edge spreads over many pixels, because a pixel there can see
  more of the lamp. This is one measurement, not a blur laid over a hard shadow.
- **Falloff.** A small lamp covers less and less of the circle of directions a pixel can look
  along, so the light halves as the distance doubles. A wide lamp falls off more slowly, on
  its own, because it stays wide for longer.
- **Color that travels.** With `bounces` at 1 or more, every lit surface gives its own color
  back into the room. A red wall reddens the floor beside it, and a green one greens it.
- **Light through a gap.** A row of shapes with gaps between them cuts the light into beams,
  and the beams fan out the way they should. Nothing draws a beam.
- **A cost that does not follow the scene.** One lamp and two hundred lamps cost the same,
  and so do ten shapes and ten thousand. What costs is the size of the layer and how far
  light is allowed to travel.

<a id="the-knobs"></a>
### The knobs

```swift
scene.combined(with: lamps, .light(reach: 600, brightness: 4, bounces: 1,
                                   sky: Color(white: 0.05), quality: .default))
```

- **`reach`** how far light travels, in pixels. `nil`, the default, reaches across the whole
  layer. This is the speed knob, because it takes rungs off the ladder the answer is built
  on, and it also reads as a smaller room: past it the light stops.
- **`brightness`** scales the lamps before anything is traced. Raise it for a small lamp that
  has to fill a large space. Values above 1 are ordinary here, since the frame is
  [tone mapped](HDR.md) at the end like any other.
- **`bounces`** how many times light comes back off what it lands on. `0` leaves every surface
  black, which is the plain shadow look. `1` is the default and is what makes a room take the
  color of its walls. More is softer, and each one costs a second pass over the whole ladder.
- **`sky`** the light that arrives from beyond the reach of the field. Clear, the default, is
  a dark room. Any color reads as a lit room with a window, or as an outdoor scene, and it is
  what fills the parts of a picture no lamp reaches.
- **`quality`** how closely the light is measured: `.performance`, `.default`, or `.detail`,
  hardware-relative like every other quality tier. It sets how far apart the probes sit and
  how many steps a ray may take. An export lifts `.default` to `.detail`.

<a id="compose"></a>
### In a compose block

Inside `compose { }` the same op reads as a modifier on the layer being lit, with the lamps
as an `aside`:

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

Measured on an M2 at 1080 by 1080, release, for the whole term (the field, the ladder, and
the bounce):

| quality | no bounce | one bounce |
| --- | --- | --- |
| `.performance` | 7.8 ms | 11.3 ms |
| `.default` | 13.1 ms | 23.4 ms |
| `.detail` | 42.0 ms | 79.6 ms |

A second bounce costs about as much as the first. A shorter `reach` is cheaper, because the
ladder gets shorter. A smaller layer is much cheaper: half the width and half the height is
a quarter of the work, so `makeRenderTarget(scale: 0.5)` is the first thing to reach for if a
sketch needs the frame rate back.

<a id="limits"></a>
### What it will not do

- **A solid shows the light on the face nearest it.** Light stops at a surface, so the inside
  of a shape is not somewhere light ever reaches. What is drawn there instead is the light
  standing just off its nearest face. For a thin wall that is exactly right. For a wide round
  shape lit unevenly, the middle is where two sides meet, and a soft seam can show there.
- **A lamp is opaque.** Draw a lamp you want to see through into the scene layer as well,
  with the alpha you want it to have, and keep the lamps layer for the light itself.
- **Only what is in the layer exists.** A ray that leaves the layer meets the `sky` and
  nothing else, so a scene that runs off the edge is lit as though it stopped there.
- **Fine detail costs probes.** At `.performance` the probes sit four pixels apart, and around
  a small bright lamp that reads as blocky at native size. `.default` is two pixels, and an
  export is one.

<a id="how-it-works"></a>
### How it works

The technique is **radiance cascades**, and the shape of it is worth knowing because the
knobs follow from it.

To know the light at a point you need many probes close to a lamp and few far from it. You
also need few directions close to it and many far from it. So the answer is built as a
ladder of fields. Each one holds a single ring of distance around every point it samples. The first rung has
a probe every pixel or two, each looking four ways over a short span. Every rung above it
halves the probes along each axis and quadruples the directions. Its span is four times as
long, and begins where the rung below it ended. Probes divided by four and directions times
four cancel, so every rung is the same size, however far it reaches.

The rays are marched against a [measured distance field](DistanceFields.md) of the scene,
which is why the cost does not follow how much was drawn: a ray crosses an empty room in one
step whatever stands outside it.

The technique is Alexander Sannikov's, implemented here from the published description and
credited in [`ATTRIBUTION.md`](../../ATTRIBUTION.md), along with the "bilinear fix" that
makes each rung's rays end where the rung above them begins.

---

See also [Effects](Effects.md) for the layer and combine substrate this is built on,
[Measured distance fields](DistanceFields.md) for the field it marches against, and
[HDR & tone-mapping](HDR.md) for what happens to light brighter than white.
