#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Simulation](./README.md) → `Watercolor`</sup>

---

## Watercolor

Wet paint on rough paper, simulated. A `Sim.watercolor` field is a sheet of textured paper: drawing into it lays down water and pigment, and each frame the wash *behaves* the way real watercolor does. Water flows inside the wetted area, steered by the paper's tooth; the wet edge sheds water so pigment drifts outward and dries as the signature dark rim; pigment settles at each paint's own pace (dense paints drop early, granulating ones collect in the paper's hollows, staining ones refuse to lift); moisture creeps through the paper's pores, so a wet touch on a damp wash blooms into a branching backrun; and the finished layers composite optically (the Kubelka-Munk model), so thin washes glow and glazes mix like light through stained glass.

The model is the classic three-layer wash simulation from Curtis, Anderson, Seims, Fleischer & Salesin, *Computer-Generated Watercolor* (SIGGRAPH 1997): a shallow-water layer where water and pigment flow, a pigment-deposition layer where paint settles onto the sheet, and a capillary layer where moisture travels through the paper itself.

```swift
var paint: WatercolorField!

override func setup() {
    paint = watercolor(pigments: [.frenchUltramarine, .quinacridoneRose])
}

override func draw() {
    withField(paint) {
        noStroke()
        if mouseIsPressed { fill(paint.ink(0)); drawCircle(mouseX, mouseY, 24) }
    }
    drawImage(paint.image, 0, 0)
}
```

### Contents

- [Painting into the field](#painting)
- [Pigments](#pigments)
- [Washes: dry and blot](#washes)
- [The six classic effects](#effects)
- [Knobs](#knobs)
- [Notes](#notes)

<a id="painting"></a>
### Painting into the field

A `WatercolorField` is a persistent [`SimField`](../Drawing/Effects.md#simfield): make it once in `setup()` with `watercolor(...)` and hold it. Painting is ordinary drawing inside a `withField(paint) { }` block, with the field's palette mapped onto the mark's color channels:

- **red** is the first pigment, **green** the second, **blue** the third;
- **alpha is water**: it wets the paper and adds the pressure that makes paint move.

`ink(_:load:water:)` builds those brush colors for you: `paint.ink(0, load: 0.6, water: 1)` is a wet brush carrying the first pigment. A wetter stroke spreads further and carries its load thinner (the water dilutes the pigment); a drier one stays put. `paint.water()` is a clean-water brush: it wets and pushes the wash around without adding any pigment. Any drawing call works as a brush (circles, polylines, text, an image), and `noStroke()` matters: a stroked mark would ring every shape with its stroke color, and a black stroke is pigment-free water.

The field's `image` is the finished painting, opaque over the paper color, ready to composite; `filtered(_:)` post-processes it like any layer.

<a id="pigments"></a>
### Pigments

A `WatercolorPigment` carries the paint's optics (how a layer absorbs and scatters red, green, and blue light) and its three wet habits:

| property | what it does |
|---|---|
| `density` | how readily it settles onto the paper: dense paints drop early and travel less |
| `staining` | how hard settled paint grips: staining paints resist being lifted back into moving water |
| `granulation` | how much the paper's tooth biases settling: granulating paints collect in the hollows and dry speckled |

Twelve real paints with measured coefficients ship as presets: `.quinacridoneRose`, `.indianRed`, `.cadmiumYellow`, `.hookersGreen`, `.ceruleanBlue`, `.burntUmber`, `.cadmiumRed`, `.brilliantOrange`, `.hansaYellow`, `.phthaloGreen`, `.frenchUltramarine`, and `.interferenceLilac` (a paint that shows more color over black than over white).

To invent a paint, describe what it looks like: `WatercolorPigment(overWhite:overBlack:)` derives the optical coefficients from the color a layer of it shows painted over white and over black paper. A transparent paint keeps its hue over white and goes nearly black over black; an opaque one looks alike on both. That pair of swatches is enough to pin the optics down.

```swift
let ink = WatercolorPigment(overWhite: Color(hex: 0x2A6E4F),   // a deep viridian
                            overBlack: Color(hex: 0x0A2418),
                            density: 0.03, staining: 2, granulation: 0.5)
paint = watercolor(pigments: [ink, .burntUmber])
```

A field's palette holds up to three pigments (one per color channel). Painting a mixed color paints a mixture: `fill(Color(red: 0.5, green: 0.3, blue: 0, alpha: 1))` loads the brush with both of the first two pigments at once.

<a id="washes"></a>
### Washes: dry and blot

A wash stays wet (it keeps flowing) until you say otherwise, and there are two ways to say it:

- **`paint.dry()`** fixes everything: the current wash bakes into a *dried glaze* under the next one. Later strokes paint over it wet-on-dry, disturbing nothing, and the dried layers composite optically, so glazing thin washes over one another builds the luminous depth watercolorists prize. This is the glazing workflow: wash, dry, wash, dry.
- **`paint.blot()`** lifts only the standing water: the wash stops flowing, but its pigment stays where it lies, still movable, and the sheet stays damp. This is the "drying but still damp" state a backrun wants (below).

Both take effect on the next frame the field steps.

<a id="effects"></a>
### The six classic effects

Every hallmark of the medium comes out of the simulation rather than a filter:

- **Edge darkening**: leave a wet stroke alone and its rim darkens as it sits, because the wet edge sheds water and the interior replenishes it, ferrying pigment outward. `edgeDarkening` is the strength (0 turns it off).
- **Dry-brush**: set `dryBrush` above zero (try `0.4...0.6`) and paint only lands where the paper's tooth rises above the threshold, so strokes skip and break up.
- **Backruns**: blot a wash, then *hold* a clean-water touch in it. The water floods back through the damp paint, pushing pigment ahead of it into a pale bloom ringed by a dark, branching edge. A single tap only nudges; holding the wet brush (painting the drop over consecutive frames) is what blooms.
- **Granulation**: paint with a granulating pigment (`.frenchUltramarine`, `.burntUmber`) and the wash dries speckled, following the sheet's texture.
- **Flow effects**: paint wet-in-wet (a loaded stroke into a still-wet wash) and the color spreads soft and feathery, steered by the paper.
- **Glazing**: dry the sheet, then wash over it. The layers mix optically, not additively: hansa yellow over ultramarine reads as the muted green those real paints actually make.

<a id="knobs"></a>
### Knobs

`Sim.watercolor(...)` takes the palette plus:

| knob | default | what it does |
|---|---|---|
| `edgeDarkening` | 0.04 | how much water the wet edge sheds per step (the dark rim; the reference model runs `0.01...0.05`) |
| `backruns` | `true` | run the capillary layer (moisture creeping through the paper's pores) |
| `dryBrush` | 0 | 0 paints normally; above it, only paper higher than the threshold takes paint |
| `absorbency` | 0.3 | how fast the sheet drinks where it's wet (feeds the backrun creep) |
| `grain` | 14 | the paper texture's feature scale, in field texels |
| `paperSeed` | 7 | picks the sheet; pass `Double(variation)` to give every seed its own paper |
| `paperColor` | warm white | the sheet's own color, shown wherever no pigment covers |
| `speed` | 1 | main simulation steps per frame (`1...4`) |

The sim is settable live (`paint.sim = .watercolor(...)`), so any of these can ride a `@Param` while the painting carries on; retuning `paperSeed` or `grain` regenerates the sheet under the existing paint.

<a id="notes"></a>
### Notes

- The default field `scale` is 0.5: the wash runs many GPU passes per frame, and half resolution keeps it cheap while reading as paper-soft. The simulation is resolution-dependent (features live in field texels), so a sketch that changes `scale` changes the wash's character too.
- The painting evolves deterministically: the paper is generated from `paperSeed` and every pass is a fixed function of the state, so exports reproduce and the same script replays byte-identically.
- For the generative-geometry take on watercolor (stacked deformed translucent polygons, no simulation, plotter-friendly), see [Generators → Watercolor](../Generators/Watercolor.md).
- See the `Simulation/Watercolor` example: a scripted painting (wash, wet-in-wet charge, blot and bloom, dry, glaze) you can take over with the mouse.
