#### <sup>[Ollin](../README.md) → [Documentation](./README.md) → `Text`</sup>

---

## Text

Ollin draws text in three kinds of font, all behind the same `drawText` / `textFont` / `textSize` / `textAlign` surface:

- A **bitmap font** — a glyph is a small grid of pixels, each lit pixel stamped as one square on the same instanced-SDF path the shapes use. No rasterizer, no separate pipeline. The default font is a bitmap font, so text works with zero setup.
- An **outline font** — a real TrueType/OpenType (`.ttf`/`.otf`) face, each glyph stored as vector contours and drawn as a [`Shape`](./Geometry.md#shape). One load draws crisp at *any* size, the type takes both `fill` and `stroke`, and the glyph geometry is yours to manipulate.
- A **stroke font** — a single-line (plotter) face whose glyphs are open pen paths with *no fill*, drawn with the current `stroke`. The kind of letterform a pen plotter draws. Hershey Sans comes bundled.

All three ride the [transform stack](./Drawing.md#translate), composite in draw order with everything else, and stay crisp at any size.

The default font, `BitmapFont.builtin`, is **[Cozette](https://github.com/the-moonwitch/Cozette)**, a 13px pixel font bundled with Ollin, so `drawText` works with zero setup. It covers a wide range: Latin (including the Spanish accents `á é í ó ú`, `ñ`, `ü`, `¿`, `¡`), Cyrillic, Greek, and Japanese kana. Call these bare inside `draw()`; they forward to the `Drawer`. Bitmap text takes the current [`fill`](./Drawing.md#fill) color.

### Contents

- [drawText](#drawtext) — draw a string
- [textFont](#textfont), [textSize](#textsize), [textAlign](#textalign) — text state
- [textWidth](#textwidth) — measure a string
- [Outline fonts](#outlinefont) — `OutlineFont`, loading a `.ttf`/`.otf` from anywhere
- [Rendering at volume](#textmode) — `textMode(.atlas)` for paragraphs and large glyph counts
- [Variable fonts](#variable) — animate weight, width, and other axes
- [Stroke fonts](#strokefont) — `StrokeFont`, single-line / plotter type
- [Per-glyph drawText](#perglyph) — give each letter its own transform and color
- [Text on a path](#onpath) — lay glyphs along a curve
- [Box layout](#box) — wrap a paragraph into a rectangle
- [textToShapes](#texttoshapes) — text as first-class geometry
- [Metrics](#metrics) — `textAscent` / `textDescent` / `textLeading` / `textBounds`
- [BitmapFont](#bitmapfont) — the bitmap font value type, and authoring your own

<a name="drawtext"></a>

### drawText

```swift
drawText(_ string: String, _ x: Double, _ y: Double)
drawText(_ string: String, at position: Vector2)
```

Draw `string` at a point, in the current `fill` color, using the active `textFont` / `textSize` / `textAlign`. `\n` starts a new line. Because each pixel is an SDF square, text rotates and scales with the [transform stack](./Drawing.md#translate) like any other geometry. `noFill()` draws nothing; characters the font doesn't have advance the pen but draw nothing.

```swift
background(.black)
fill(.white)
textSize(120)
textAlign(.center, .middle)
drawText("ollin", width / 2, height / 2)
```

<a name="textfont"></a>

### textFont

```swift
textFont(_ font: BitmapFont)
textFont(_ font: OutlineFont)
textFont(_ font: StrokeFont)
```

Set the active font — a bitmap (pixel-grid), outline (`.ttf`/`.otf`), or stroke (single-line) font. The default is `BitmapFont.builtin` (Cozette); write `textFont(BitmapFont.builtin)` to switch back to it. Like the other drawing state, the active font is part of the [push/pop stack](./Drawing.md#withstate), so `withState { textFont(custom); … }` restores the previous font automatically on exit. (See [BitmapFont](#bitmapfont) to load or build a bitmap font, [Outline fonts](#outlinefont) for a `.ttf`/`.otf`, or [Stroke fonts](#strokefont) for single-line type.)

<a name="textsize"></a>

### textSize

```swift
textSize(_ size: Double)
```

Set the rendered text height in points — the height one line of glyphs occupies on screen. A `BitmapFont` is authored at a native pixel height; `textSize` scales each pixel to a module of `size / font.pixelHeight` points, so `textSize(140)` makes a capital letter 140 points tall whatever the font's grid. Defaults to 24.

<a name="textalign"></a>

### textAlign

```swift
textAlign(_ horizontal: TextAlignH, _ vertical: TextAlignV = .baseline)
```

Set how text is anchored to the `drawText` position.

- Horizontal (`TextAlignH`): `.left` (default) starts the text at the x, `.center` centers it, `.right` ends it at the x.
- Vertical (`TextAlignV`): `.baseline` (default, like p5) sits the first line's baseline on the y; `.top` / `.bottom` align the block's top / bottom edge; `.middle` centers the whole block.

```
  textAlign(h, v): how text anchors to the (x, y) you pass (● = that point).

  Horizontal (● marks the x):
     .left     ●Hello        text starts at the x
     .center    Hel●lo       text is centered on the x
     .right     Hello●       text ends at the x

  Vertical (● marks the y), shown on a two-line block:
     ┌─●─ .top      block's top edge on the y
     │ first line
     ●   .middle    block centered on the y
     │ second line
     └─●─ .bottom   block's bottom edge on the y
     .baseline (default): the first line's baseline sits on the y
```

```swift
textAlign(.center, .top)
drawText("two\nlines", width / 2, 100)   // centered, growing downward from y = 100
```

<a name="textwidth"></a>

### textWidth

```swift
textWidth(_ string: String) -> Double
```

The on-screen width of `string`'s widest line, in points, at the current `textFont` / `textSize` — for laying text out (centering by hand, wrapping, marquees).

```swift
let w = textWidth(label)
drawRect(center: Vector2(x, y), width: w + 24, height: textSize_ + 16)   // a padded backing
```

<a name="outlinefont"></a>

### Outline fonts

```swift
textFont(_ font: OutlineFont)
```

An `OutlineFont` is a real TrueType/OpenType (`.ttf`/`.otf`) face. Unlike a bitmap font it stores each glyph as **vector contours**, so one load draws crisp at *any* `textSize` — you never reload per size. Set it with the same `textFont`; then `drawText`, `textSize`, `textAlign`, and `textWidth` all work exactly as before.

Because an outline glyph is rendered as a [`Shape`](./Geometry.md#shape) — the same vector fill the triangulator draws — outline text takes the current `fill` **and** an active `stroke`, and composites in draw order with everything else. Filled, outlined, and stroke-only text all fall out of that:

```swift
let display = OutlineFont(name: "Avenir Next") ?? .system
textFont(display)
textSize(160)
textAlign(.center, .middle)

fill(.white); noStroke()
drawText("filled", width / 2, 240)

noFill(); stroke(.white); strokeWeight(2)
drawText("outline", width / 2, 480)
```

> [!NOTE]
> Outline text honors `stroke` like every other shape, so the default 1px stroke will outline your glyphs — call `noStroke()` for plain filled text.

**Loading a font, from anywhere:**

```swift
OutlineFont(name: "Helvetica Neue")             // an installed family / PostScript name
OutlineFont(path: "/path/to/Font.otf")          // a file on disk
OutlineFont(url: fileURL)                        // a file:// URL
OutlineFont(data: bytes)                          // raw .ttf/.otf data
OutlineFont(resource: "Font.ttf", in: .module)   // a font bundled beside your sketch

OutlineFont.system        // the system UI font (San Francisco on macOS)
OutlineFont.systemBold
OutlineFont.systemMono
```

`init(name:)` returns `nil` if no installed font matches, so a typo fails loudly instead of silently substituting another face — pair it with a fallback: `OutlineFont(name: "Futura") ?? .system`. A remote `https://` URL needs an asynchronous download, which can't run on the draw thread: fetch it in `setup()` (or ahead of time) and pass the bytes to `init(data:)`.

Ollin ships no `.ttf`/`.otf` of its own — you bring the font (installed, bundled, or fetched). Layout goes through Core Text, so kerning, ligatures, and fallback for missing glyphs come for free.

<a name="textmode"></a>

### Rendering at volume

By default each outline glyph is filled as a vector shape — highest quality, and it takes `fill` *and* `stroke`. That's the right choice for headlines and body text, but a paragraph of thousands of glyphs re-tessellated every frame gets expensive. `textMode(.atlas)` switches outline text to a signed-distance-field atlas instead: each glyph is rasterized once into a shared texture and drawn as a single quad sampling it, so the per-glyph cost drops to a handful of vertex writes. It stays crisp under magnification, and one raster serves every `textSize`.

```swift
textFont(OutlineFont.systemMono)
textSize(18)
textMode(.atlas)              // the default is .outline

for (i, line) in paragraph.enumerated() {
    drawText(line, margin, top + Double(i) * lineHeight)
}
```

`textMode` is drawing state, like `textSize` and `textAlign` — it persists until you change it and scopes with `withState { }`, so you can keep big headlines on the crisp `.outline` path and switch to `.atlas` for the wall of small text:

```swift
textMode(.outline); textSize(120); drawText("Title", x, y)
textMode(.atlas);   textSize(16);  drawText(bodyText, x, y2)
```

Two things to know. The atlas path is **fill-only** (it ignores `stroke` — the volume case is filled text; reach for `.outline` when you want stroked glyphs), and the single-channel field rounds *very* sharp corners at extreme magnification, which is invisible at the body and display sizes this path is for. `textMode` is a no-op for bitmap and stroke fonts, which have no atlas. See the [TextVolume example](../Examples/Text/TextVolume).

<a name="variable"></a>

### Variable fonts

A variable font packs a family's continuous design axes — weight, width, optical size, slant — into one file. `OutlineFont` exposes them: `variation(_:)` returns a copy with axes set, and `variationAxes` lists what a font offers and its ranges.

```swift
let skia = OutlineFont(name: "Skia")!
print(skia.variationAxes)   // [(tag: "wght", name: "Weight", min: 0.48, max: 3.2, default: 1), …]

textFont(skia.variation(["wght": 2.6, "wdth": 1.2]))   // heavy, a touch wide
```

Keys are the 4-character axis tags (`"wght"`, `"wdth"`, `"opsz"`, `"slnt"`); values are in the font's **own** axis units (ranges are font-specific — read them from `variationAxes`). The one-axis conveniences `weight`, `width`, `opticalSize`, and `slant` set a single axis; combine several in one `variation(_:)` call so they don't reset each other.

A varied font is just another `OutlineFont`, so you can animate the axes — a word that breathes from thin to heavy:

```swift
textFont(skia.variation(["wght": map(sin(time), -1, 1, 0.5, 3.1)]))
drawText("ollin", width / 2, height / 2)
```

(A non-variable font ignores variation and returns an empty `variationAxes`.)

<a name="strokefont"></a>

### Stroke fonts

```swift
textFont(_ font: StrokeFont)
```

A `StrokeFont` is a **single-line** font: each glyph is a set of open pen paths with no interior. Where a bitmap font stamps pixels and an outline font fills contours, a stroke font is *stroked* — so it draws with the current `stroke` (weight, join, cap) and **ignores `fill`**, the mirror image of outline text. It's the letterform a pen plotter wants, and it pairs naturally with thin, even line weights.

```swift
textFont(StrokeFont.builtin)        // Hershey Sans, bundled
textSize(160)
textAlign(.center, .middle)
stroke(.white); strokeWeight(2)
strokeCap(.round); strokeJoin(.round)   // a softer, drawn line
drawText("ollin", width / 2, height / 2)
```

The bundled default is **Hershey Sans**, from the public-domain [Hershey vector fonts](https://paulbourke.net/dataformats/hershey/). Because the glyphs are open paths, `textToShapes` hands them back as open contours (stroke or warp them — don't fill), and they flow through the same [per-glyph](#perglyph) and [text-on-a-path](#onpath) surface as the other kinds.

**Loading more single-line fonts:** Ollin reads the Hershey `.jhf` format, so you can drop in any of the many Hershey faces (serif, script, gothic, Cyrillic, Greek):

```swift
let serif = StrokeFont(resource: "rowmans.jhf", in: .module) ?? .builtin
textFont(serif)
```

`StrokeFont(resource:in:)` loads one bundled beside your sketch (pass `.module` for a `swift run` sketch's resources); `StrokeFont(jhfContentsOf:)` takes any file URL, and `StrokeFont(jhf:)` parses `.jhf` text you already have. The Hershey faces live in many public-domain mirrors (e.g. [kamalmostafa/hershey-fonts](https://github.com/kamalmostafa/hershey-fonts)); for the wider world of single-line type, [Golan Levin's single-line-font resources](https://github.com/golanlevin/p5-single-line-font-resources) is a good map (mind the per-font licenses there). Ollin ships only the parser and the one Hershey default.

<a name="perglyph"></a>

### Per-glyph drawText

```swift
drawText(_ string: String, _ x: Double, _ y: Double, perGlyph: (TextGlyph) -> Void)
drawText(_ string: String, at position: Vector2, perGlyph: (TextGlyph) -> Void)
```

A trailing-closure form of `drawText` that hands you each glyph as a `TextGlyph` instead of drawing the string for you. Give each letter its own transform or color, then stamp it with `g.draw()`. It's the hook for per-letter waves, rainbows, and springs — effects p5 and openFrameworks have no direct API for. Single line.

```swift
textAlign(.center, .middle)
drawText("ollin", at: center) { g in
    fill(palette.color(at: g.t))                 // a hue per letter
    withState {
        translate(0, sin(time * 3 - Double(g.index) * 0.7) * 60)   // bob on a wave
        g.draw()
    }
}
```

A `TextGlyph` carries:

- `character` — the source `Character`; `index` and `count` — its place in the run; `t` — the normalized position `0...1` across the run (handy for a gradient or a phase).
- `position` — the pen origin (left edge, on the baseline) in canvas space; `center` — the natural pivot for rotating the glyph in place; `bounds` — its advance box.
- `shapes` — the glyph geometry in canvas space (for text-as-geometry per letter).
- `draw()` — stamp the glyph with the current `fill` / `stroke`, through your transform.

To rotate a glyph about its own center, pivot on `center`:

```swift
withState {
    translate(g.center); rotate(angle); translate(g.center * -1)
    g.draw()
}
```

<a name="onpath"></a>

### Text on a path

```swift
drawText(_ string: String, along path: Path, offset: Double = 0)
```

Lay each glyph along a [`Path`](./Geometry.md#path), rotated to the path's tangent so the baseline follows the curve. Each glyph is centered on the point `offset` plus its distance along the run, measured as arc length from the path's start. Glyphs that fall before the start or past the end are **skipped**, so animating `offset` flows the text on and off the ends. Single line; takes `fill` and `stroke` like `drawText`.

```swift
let path = Path { p in
    p.move(to: Vector2(0, height / 2))
    for i in 1...60 {
        let f = Double(i) / 60
        p.curve(to: Vector2(f * width, height / 2 + sin(f * .pi * 3) * 160))
    }
}
fill(.white)
drawText("text on a curve · ", along: path, offset: -time * 120)   // scrolling
```

(Where a path bends tighter than the text is tall, glyphs crowd on the concave side — that's inherent to text-on-path, so keep curves broad relative to the text size.)

<a name="box"></a>

### Box layout

```swift
drawText(_ string: String, in rect: Rectangle)
```

Wrap `string` into a [`Rectangle`](Geometry.md#rectangle): words break to the next line at the box width, and `textAlign` positions the wrapped block within the box — horizontal `.left`/`.center`/`.right` against the box edges, vertical `.top`/`.middle`/`.bottom`. Explicit `\n`s start new paragraphs. Works for bitmap and outline fonts.

```swift
textSize(42); textAlign(.left, .top)
let box = Rectangle(center: Vector2(width / 2, height / 2), width: 600, height: 700)
fill(.white)
drawText(paragraph, in: box)
```

Measuring and wrapping happen every frame, so the text reflows live if the box (or the size) changes. Text taller than the box overflows below it (no vertical clip yet).

<a name="texttoshapes"></a>

### textToShapes

```swift
textToShapes(_ string: String, _ x: Double, _ y: Double) -> [Shape]
textToShapes(_ string: String, at position: Vector2) -> [Shape]
```

The glyphs of `string` as vector [`Shape`](./Geometry.md#shape)s, positioned exactly where `drawText` would place them (current `textFont` / `textSize` / `textAlign`). This is **text as first-class geometry**: warp it, sample points along it, scatter particles on it, animate the contours — then fill or stroke the result like any other shape. An outline font returns one `Shape` per glyph (a letter with a counter — `o`, `e`, `a` — keeps its hole); a bitmap font returns its lit pixels as squares.

```swift
textSize(300); textAlign(.center, .middle)
for shape in textToShapes("ollin", width / 2, height / 2) {
    // Ripple each letterform with a bounded, smooth field.
    let rippled = Shape(contours: shape.contours.map { c in
        Contour(c.points.map { p in
            p + Vector2(signedNoise(p.x * 0.004, p.y * 0.004, time),
                        signedNoise(p.x * 0.004 + 40, p.y * 0.004, time)) * 14
        }, closed: c.isClosed)
    })
    drawShape(rippled)
}
```

> [!WARNING]
> Displacing outline points by a *large or uneven* amount can fold a contour over itself, which the fill renders as a spike. Keep warps **bounded and smooth** (e.g. `signedNoise`, which stays in `-1...1`) rather than raw `curlNoise`, whose magnitude is unbounded — see the `OutlineText` example.

<a name="metrics"></a>

### Metrics

```swift
textAscent() -> Double      // baseline up to the top of the tallest glyphs
textDescent() -> Double     // baseline down to the bottom of the lowest descenders
textLeading() -> Double     // baseline-to-baseline distance (what `\n` advances by)
textBounds(_ string: String, _ x: Double, _ y: Double) -> Rectangle
textBounds(_ string: String, at position: Vector2) -> Rectangle
```

```
  Type metrics, measured from the baseline (the y you pass to drawText):

        ┌─────────────────────────  ascender line
        │   A b k l d            (tops of the tall glyphs)
   ─────┼─────────────────────────  baseline  ← drawText's y sits here
        │   g p y q             (bottoms of the descenders)
        └─────────────────────────  descender line

   textAscent()   baseline → ascender line    (height above)
   textDescent()  baseline → descender line   (depth below)
   textLeading()  baseline → next baseline    (line spacing; one '\n')
```

All in points at the current `textFont` / `textSize`, for both font kinds. `textBounds` returns the box `string` would occupy if drawn at `(x, y)` with the current alignment — handy for backings, layout, and hit-testing.

<a name="bitmapfont"></a>

### BitmapFont

A `BitmapFont` is a value type: a table of `BitmapGlyph`s (each a small bit grid) plus layout metrics (`pixelHeight`, `baseline`, `lineHeight`). The built-in font is **Cozette** (see above).

Load your own pixel font from a **BDF** file (the standard bitmap-font format, what the X11 catalog and Cozette ship):

```swift
if let mine = BitmapFont(bdfContentsOf: url) {
    textFont(mine)
}
```

BDF fonts are easy to come by: the classic [X11 bitmap fonts](https://github.com/toitlang/pkg-font-x11-adobe) (Adobe/DEC, permissively licensed) and the large [u8g2 font collection](https://github.com/olikraus/u8g2/wiki/fntlistall) are good places to look (check each font's own license). Drop the `.bdf` beside your sketch and load it with `BitmapFont(resource:in:)`.

Or hand-author a fixed-cell font from ASCII art with the grid initializer — `#` marks a lit pixel:

```swift
let blocks = BitmapFont(grid: [
    "A": [".##.", "#..#", "####", "#..#", "#..#"],
    "I": ["###", ".#.", ".#.", ".#.", "###"],
    // …
], pixelHeight: 5)

textFont(blocks)
drawText("AI", width / 2, height / 2)
```

#### Loading a Playdate `.fnt`

Ollin also reads the **Playdate `.fnt`** format — a line-oriented metrics file (per-glyph widths, `tracking`, and kerning pairs) paired with a 1-bit glyph strike, either embedded in the file as base64 or sitting beside it as a `<name>-table-<width>-<height>.png`. It's a common pixel-font format, with a large pool of free community fonts to draw from. Kerning pairs in the file are applied automatically during layout.

```swift
let font = BitmapFont(resource: "MyFont.fnt", in: .module) ?? .builtin
textFont(font)
```

`BitmapFont(resource:in:)` is the easy path for a font bundled beside your sketch: pass the filename (the loader picks BDF or `.fnt` from the extension) and the bundle it lives in — `.module` for a `swift run` sketch's own resources, or the default `.main` for an app. It returns `nil` if the resource is missing, so the `?? .builtin` falls back to the default font.

Under it, `BitmapFont(fntContentsOf:)` takes a file URL and handles both strike forms — it finds the sibling `-table` PNG when the strike is external. If you already have the text (say, fetched over the network), `BitmapFont(fnt:)` parses the self-contained embedded form directly:

```swift
let text = try String(contentsOf: someURL, encoding: .utf8)
if let font = BitmapFont(fnt: text) { textFont(font) }
```

Ollin bundles only the *loader*, not a library of `.fnt` fonts — drop your own beside your sketch (the `PlaydateFont` example does exactly this). Free, redistributable pixel fonts are easy to find; the public-domain set at [playdate-arcade-fonts](https://github.com/idleberg/playdate-arcade-fonts) is one source.

---

Coordinates use a **top-left origin with y increasing downward**, the same as the rest of Ollin's drawing surface.
