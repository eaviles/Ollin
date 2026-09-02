#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Simulation](./README.md) → `Watercolor`</sup>

---

## Watercolor

Wet paint on rough paper, simulated. A `Sim.watercolor` field is a sheet of textured paper. Drawing into it lays down water and pigment, and each frame the wash *behaves* the way real watercolor does.

- Water flows inside the wetted area, steered by the paper's tooth.
- The wet edge sheds water, so pigment drifts outward and dries as the signature dark rim.
- Pigment settles at each paint's own pace. Dense paints drop early, granulating ones collect in the paper's hollows, and staining ones refuse to lift.
- Moisture creeps through the paper's pores, so a wet touch on a damp wash blooms into a branching backrun.
- The finished layers composite optically, by the Kubelka-Munk model, so thin washes glow and glazes mix like light through stained glass.

The model is the classic three-layer wash simulation from Curtis, Anderson, Seims, Fleischer & Salesin, *Computer-Generated Watercolor* (SIGGRAPH 1997). Water and pigment flow in a shallow-water layer. Paint settles onto the sheet in a pigment-deposition layer. Moisture travels through the paper itself in a capillary layer.

<img src="../../Guide/Images/19-GridSimulations/WetPaint.jpg" alt="A simulated watercolor painting: a horizontal ultramarine wash with a darkened edge and rose charged into its middle, a pale backrun bloom with branching ridges where water was dropped, and a vertical yellow band glazed across everything, turning green where it crosses the blue" width="560">

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
- [Drying and blotting a wash](#washes)
- [The six classic effects](#effects)
- [Parameters](#parameters)
- [Notes](#notes)

<a id="painting"></a>
### Painting into the field

A `WatercolorField` is a persistent [`SimField`](../Drawing/Effects.md#simfield). Make it once in `setup()` with `watercolor(...)` and hold it. Painting is ordinary drawing inside a `withField(paint) { }` block. The field's palette maps onto the mark's color channels.

- **red** is the first pigment, **green** the second, and **blue** the third.
- **alpha is water**. It wets the paper and adds the pressure that makes paint move.

`ink(_:load:water:)` builds those brush colors for you. `paint.ink(0, load: 0.6, water: 1)` is a wet brush carrying the first pigment. A wetter stroke spreads further and carries its load thinner, because the water dilutes the pigment. A drier one stays put. `paint.water()` is a clean-water brush. It wets and pushes the wash around without adding any pigment. Any drawing call works as a brush, such as circles, polylines, text, or an image. `noStroke()` matters here. A stroked mark would ring every shape with its stroke color, and a black stroke is pigment-free water.

The field's `image` is the finished painting, opaque over the paper color and ready to composite. `filtered(_:)` post-processes it like any layer.

<a id="pigments"></a>
### Pigments

A `WatercolorPigment` carries the paint's optics (how a layer absorbs and scatters red, green, and blue light) and its three wet habits:

| property | what it does |
|---|---|
| `density` | how readily it settles onto the paper, so dense paints drop early and travel less |
| `staining` | how hard settled paint grips, so staining paints resist being lifted back into moving water |
| `granulation` | how much the paper's tooth biases settling, so granulating paints collect in the hollows and dry speckled |

Twelve real paints with measured coefficients ship as presets: `.quinacridoneRose`, `.indianRed`, `.cadmiumYellow`, `.hookersGreen`, `.ceruleanBlue`, `.burntUmber`, `.cadmiumRed`, `.brilliantOrange`, `.hansaYellow`, `.phthaloGreen`, `.frenchUltramarine`, and `.interferenceLilac` (a paint that shows more color over black than over white).

To invent a paint, describe what it looks like. `WatercolorPigment(overWhite:overBlack:)` derives the optical coefficients from two colors. They are the color a layer of it shows over white paper, and the color it shows over black paper. A transparent paint keeps its hue over white and goes nearly black over black. An opaque one looks alike on both. That pair of swatches is enough to pin the optics down.

```swift
let ink = WatercolorPigment(overWhite: Color(hex: 0x2A6E4F),   // a deep viridian
                            overBlack: Color(hex: 0x0A2418),
                            density: 0.03, staining: 2, granulation: 0.5)
paint = watercolor(pigments: [ink, .burntUmber])
```

A field's palette holds up to three pigments, one per color channel. Painting a mixed color paints a mixture. `fill(Color(red: 0.5, green: 0.3, blue: 0, alpha: 1))` loads the brush with both of the first two pigments at once.

<a id="washes"></a>
### Drying and blotting a wash

A wash stays wet and keeps flowing until you say otherwise. There are two ways to say it.

- **`paint.dry()`** fixes everything. The current wash bakes into a *dried glaze* under the next one. Later strokes paint over it wet-on-dry, disturbing nothing. The dried layers composite optically, so glazing thin washes over one another builds the luminous depth watercolorists prize. That is the glazing workflow, wash, dry, wash, dry.
- **`paint.blot()`** lifts only the standing water. The wash stops flowing, but its pigment stays where it lies, still movable, and the sheet stays damp. That is the "drying but still damp" state a backrun wants (below).

Both take effect on the next frame the field steps.

<a id="effects"></a>
### The six classic effects

Every hallmark of the medium comes out of the simulation rather than a filter.

- **Edge darkening.** Leave a wet stroke alone and its rim darkens as it sits. The wet edge sheds water, and the interior replenishes it, ferrying pigment outward. `edgeDarkening` is the strength (0 turns it off).
- **Dry-brush.** Set `dryBrush` above zero (try `0.4...0.6`). Paint then lands only where the paper's tooth rises above the threshold, so strokes skip and break up.
- **Backruns.** Blot a wash, then *hold* a clean-water touch in it. The water floods back through the damp paint. It pushes pigment ahead of it into a pale bloom, ringed by a dark, branching edge. A single tap only nudges. Holding the wet brush is what blooms, which means painting the drop over consecutive frames.
- **Granulation.** Paint with a granulating pigment (`.frenchUltramarine`, `.burntUmber`), and the wash dries speckled, following the sheet's texture.
- **Flow effects.** Paint wet-in-wet, which is a loaded stroke into a still-wet wash. The color spreads soft and feathery, steered by the paper.
- **Glazing.** Dry the sheet, then wash over it. The layers mix optically rather than additively. Hansa yellow over ultramarine reads as the muted green those real paints actually make.

<a id="parameters"></a>
### Parameters

`Sim.watercolor(...)` takes the palette, plus these parameters.

| parameter | default | what it does |
|---|---|---|
| `edgeDarkening` | 0.04 | how much water the wet edge sheds per step, which makes the dark rim (the reference model runs `0.01...0.05`) |
| `backruns` | `true` | run the capillary layer, where moisture creeps through the paper's pores |
| `dryBrush` | 0 | 0 paints normally, and above it only paper higher than the threshold takes paint |
| `absorbency` | 0.3 | how fast the sheet drinks where it's wet (feeds the backrun creep) |
| `grain` | 14 | the paper texture's feature scale, in field texels |
| `paperSeed` | 7 | picks the sheet; pass `Double(variation)` to give every seed its own paper |
| `paperColor` | warm white | the sheet's own color, shown wherever no pigment covers |
| `speed` | 1 | main simulation steps per frame (`1...4`) |

The sim is settable live (`paint.sim = .watercolor(...)`), so any of these can ride a `@Param` while the painting carries on. Retuning `paperSeed` or `grain` regenerates the sheet under the existing paint.

<a id="notes"></a>
### Notes

- The default field `scale` is 0.5. The wash runs many GPU passes per frame, and half resolution keeps it cheap while reading as paper-soft. The simulation is resolution-dependent, because its features live in field texels. A sketch that changes `scale` changes the wash's character too.
- The painting evolves deterministically. The paper is generated from `paperSeed`, and every pass is a fixed function of the state. Exports reproduce, and the same script replays byte-identically.
- For the generative-geometry take on watercolor, see [Generators → Watercolor](../Generators/Watercolor.md). That one stacks deformed translucent polygons, runs no simulation, and suits a plotter.
- See the `Simulation/Watercolor` example. It is a scripted painting you can take over with the mouse, running wash, wet-in-wet charge, blot and bloom, dry, and glaze.
