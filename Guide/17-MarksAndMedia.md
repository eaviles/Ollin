#### <sup>[Ollin](../README.md) → [Guide](README.md) → Chapter 17</sup>

---

# 17. Marks and media

<!-- Hook image: the finished sketch, the monogram over its marbled heart (Figures/17-MarksAndMedia/Monogram.swift). Waiting on its render on the Mac. -->

A line from a machine is one width from end to end. A mark from a hand swells and thins, answers to speed and pressure, and breaks into the prints of a brush. This chapter gives your strokes that life. A profile shapes a finished path's width, and dynamics read the hand while it paints. A brush stamps a tip along the path, and a dash pattern cuts it. Then come two wet media, marbling and watercolor, made from outlines bent and stacked. It all stays vector geometry, so a painted mark exports as the region it covers. The chapter ends by writing your initials into a marbled heart.

## Marks and brushes

The next three tools shape the stroke itself, and each answers a different question. A profile shapes a finished path's width, dynamics respond to the hand mid-gesture, and a brush decides what tip lays the ink down.

### A mark, not a line: strokeProfile

Every stroke so far has been one width from end to end. That is the honest look of a machine drawing a line. It is the wrong look for a hand making a mark. `strokeProfile` gives the width a shape of its own along the path.

The profile is a multiplier, not a width. `strokeWeight` still says how fat the mark gets. The profile says what fraction of that it uses at each point:

```swift
strokeWeight(17)
strokeProfile(.taper())
drawPolyline(curve)
```

`.taper()` is a brush pressed down and lifted: nothing at either end, full width in the middle. Its two arguments are the widths *at* the ends, so `.taper(start: 1)` starts blunt and lifts off at the finish. A straight wedge is `.ramp(from:to:)`, and `.values([...])` takes a width curve you write out yourself. `.nib(angle:)` is the odd one, because it ignores where you are along the path entirely. It holds a flat calligraphy pen at a fixed angle. The mark is fattest where the path runs across the nib, and a hairline where it runs along it. That is why the third panel below is an S-curve: a straight line would only ever show one nib width.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/17-MarksAndMedia/MarkWidth-dark.jpg">
  <img src="Images/17-MarksAndMedia/MarkWidth.jpg" alt="The same S-curve drawn three ways at one stroke weight: an even line, a taper that swells in the middle and vanishes at both ends, and a calligraphic nib that thickens and thins as the curve turns" width="680">
</picture>

Two practical notes. The width is read at every point of the path, measured along the path's length. A shape with four points changes width in four steps. Sample your curves densely enough to give the profile somewhere to go. And the analytic shapes (`drawCircle`, `drawRect`, and the rest of that family) carry a single width by construction, so a profile does nothing to them. Profiles are for paths.

The mark survives the trip out, too. Run the sketch with `--export-svg` and a profiled stroke is written as the region it actually covers, rather than a line with one width attribute. What the plotter draws is what you saw.

### Painting as it happens: stroke dynamics

A profile asks one question at every point: where am I along this path? That works because the path is finished before you draw it. Now think about painting. You drag the mouse, and the stroke has to appear *as it grows*. There is no finished path, so there is no fraction, and the whole idea falls apart.

What is available instead is everything the hand just did: how fast it was moving, how hard it was pressing, which way it was heading. That is what **stroke dynamics** reads.

```swift
var mark = StrokeMark(.speed(fast: 0.15))

override func draw() {
    background(.white)
    if mouseIsPressed { record(into: &mark) }
    stroke(.black)
    strokeWeight(24)
    drawMark(mark)
}
```

Ten lines, and you can paint. `record(into:)` hands the mark where the pointer is and how long this frame took. The mark works out the speed, smooths it, and stores a width for that point. `drawMark` strokes what has been recorded so far, which is why the line appears under the cursor instead of when you let go.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/17-MarksAndMedia/MarkDynamics-dark.jpg">
  <img src="Images/17-MarksAndMedia/MarkDynamics.jpg" alt="One S-curve drawn three times at one stroke weight by a hand that is slow at the ends and fast through the middle: ignoring the pace it is an even line, letting the pace drive width it swells at the ends and narrows to a hairline in the middle, letting the pace drive opacity it stays the same width but fades" width="680">
</picture>

The figure is one curve walked three times by the same pretend hand, nearly still at the ends and flicking through the middle. Only what the pace is allowed to *drive* changes.

Which is the thing to remember here: **width and opacity are separate axes, and you say so.**

```swift
StrokeDynamics(width: .pressure(light: 0.1),      // press for a fat mark
               opacity: .speed(fast: 0.4))        // hurry for a faint one
```

An axis you don't name isn't driven, so nothing moves behind your back. `.speed(fast:)` and `.pressure(light:)` on their own are shorthands for the everyday brush. They drive width only.

`.pressure` needs a device that can feel it. Every MacBook trackpad since 2015 can, and so can a pen tablet. A plain mouse cannot, and reports full force the whole time. So a pressure brush on a mouse comes out at a single weight, rather than not drawing. `pressureIsAvailable` tells you which you have. Ask it in `mousePressed()` rather than `setup()`, because the answer arrives with the first press:

```swift
override func mousePressed() {
    mark = StrokeMark(pressureIsAvailable ? .pressure(light: 0.1) : .speed(fast: 0.15))
}
```

A tablet says more than how hard. `stylus` carries the rest of it: `tilt` is how far it leans, `-1...1` on each axis and zero when it is upright; `twist` is how far an art pen's barrel has been turned; `isEraser` is whether the end on the tablet is the eraser; and `isNearby` is whether it is over the tablet at all, which it is while hovering as well as while drawing. The lean is what a broad-edged nib is made of, since a chisel laid across the direction of the lean draws thick one way and thin the other:

```swift
let angle = stylus.tiltIsAvailable ? atan2(stylus.tilt.y, stylus.tilt.x) + .pi / 2 : .pi / 4
```

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/17-MarksAndMedia/NibAndLean-dark.jpg">
  <img src="Images/17-MarksAndMedia/NibAndLean.jpg" alt="Three panels, each the same looping path drawn with a broad-edged nib at a different lean: the stroke is thick where the path runs across the nib and thin where it runs along it, and the thick and thin fall in different places in each panel" width="680">
</picture>

`stylus.tiltIsAvailable` is the same kind of answer `pressureIsAvailable` is, and it latches on once a pen has been used, so lifting the stylus out of range does not take the pen path away mid-stroke. Under a mouse everything in `stylus` is zero and false, so a sketch written for a stylus still runs. [`Examples/Input/Pen`](../Examples/Input/Pen/Sketch.swift) is a chisel nib that reads all of it, with a panel that says what the tablet is sending.

Three practical notes. A mark is an ordinary value, so finishing one is `strokes.append(mark)` and `mark.clear()`. The `smoothing` parameter matters more than it looks. Raw frame-to-frame speed is far too jumpy to drive a width directly. The default sits where a mark feels deliberate without lagging the pointer. And profiles compose with dynamics rather than competing, so `strokeProfile(.taper(start: 1))` still gives a dynamic mark a clean lift-off at the end.

`Examples/Shapes/Brushwork` is the whole thing to drag around in, and [Marks](../Docs/Drawing/Marks.md) has the rest.

### Stamps along the path: brushes

Both tools so far shape one continuous ribbon. A real brush is not continuous. It is a tip pressed down over and over, close enough that the prints run together. `strokeBrush` works that way too.

```swift
strokeWeight(20)
strokeBrush(.spray())
drawPolyline(points)
```

It is drawing state, like `strokeCap` or a profile, and `noStrokeBrush()` puts the ribbon back. It applies to everything that strokes a path, `drawMark` included.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/17-MarksAndMedia/BrushStamps-dark.jpg">
  <img src="Images/17-MarksAndMedia/BrushStamps.jpg" alt="The same S-curve stamped three ways at one stroke weight: close-packed circles reading as a solid mark, squares turning with the path like a chisel nib, and a loose spray of translucent circles thrown either side of the line" width="680">
</picture>

The first panel is the one to look at. Those are separate circles, spaced a fifth of their own width apart, and they read as one solid stroke. Spacing is the parameter that decides whether a brush is a mark or a scatter. It is measured in *stamp sizes* rather than pixels, so a brush keeps its texture when you change `strokeWeight`. Twice the weight is the same mark, twice as big.

The rest of the parameters are what you would guess. `sizeJitter` and `opacityJitter` vary each print, and `angle` faces it down the path, at a fixed angle, or anywhere. `scatter` throws it off the line, and `count` lays down several at each step. Every one of them is a fraction of the stamp's size. Everything random comes from a `seed`, so a mark stays exactly where it was frame after frame.

The tip does not have to be a circle. `.square` turns with the path, and `.shape` and `.image` take anything you can draw or load. A trail of leaves is a shape tip with a little angle jitter.

Brushes multiply with the two previous tools rather than replacing them. A profile still sizes the stamps along the path, so a spray that fades out at both ends is one more line:

```swift
strokeBrush(.spray())
strokeProfile(.taper())
```

And each stamp is a real shape rather than a stretch of ribbon. So `--export-svg` writes every one of them as a circle or a polygon a plotter can follow. `Examples/Shapes/Brushes` has the family side by side.

### A line with gaps: strokeDash

The last of the stroke tools is the plainest. `strokeDash` cuts the ribbon into dashes:

```swift
strokeWeight(11)
strokeDash([18, 10])
drawPolyline(curve)
```

The list is dash, gap, dash, gap, in the same units as the path, and it repeats. It is drawing state like the rest, and `noStrokeDash()` puts the whole line back. Every dash is a little stroke of its own, so `strokeCap` finishes both ends of each one. That is what makes a dotted line one more line. `.dots(spacing:)` lays down dashes of length zero, and under `strokeCap(.round)` each of those is a dot.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/17-MarksAndMedia/DashPatterns-dark.jpg">
  <img src="Images/17-MarksAndMedia/DashPatterns.jpg" alt="The same S-curve dashed three ways at one stroke weight: an even dash, a row of dots, and a taper whose dashes shrink together toward both ends" width="680">
</picture>

The third panel is the one to notice. The taper from earlier in the chapter is still reading its place on the whole path. So the dashes shrink together toward the ends, rather than each one tapering on its own. The cut happens before any of the other tools see the path, which is why they compose. A brush stamps each dash and skips the gaps, and a gradient runs on through them.

A pattern also has a `phase`, how far it has slid along the path. Give it the clock and the dashes walk:

```swift
strokeDash([18, 10], phase: time * 60)
```

That is the marching outline every selection tool draws, and it costs one argument. The analytic shapes join in while a dash is on. `drawCircle`, `drawRect`, `drawStar`, and the other polygonal ones hand their outline over to the path stroke, so a dashed ring is `strokeDash` followed by `drawCircle`. On the way out, `--export-svg` writes every dash as its own subpath, so a plotter lifts the pen in every gap. `Examples/Shapes/DashedStrokes` has the family moving.


## Ink and paint

Two wet media come next, and neither involves a drop of simulated fluid. Both are dry geometry, bent and stacked until it reads as paint.

### Ink on water

Paper marbling has a few hundred years of craft behind it and a simple physical setup. Ink floats on a bath of thickened water. Because it floats instead of mixing, anything done to the surface moves the ink around without blending it. You drop fresh ink in, and you rake the surface with a stylus or a comb. Then you lay a sheet of paper on top to lift the pattern off.

`Marbling` reproduces that in closed form, which means every move is an exact transform applied to outlines rather than a simulation of fluid. Ink regions are ordinary vector shapes, and each operation bends them. Because the outlines only ever deform, ink never tears and never mixes, exactly as on a real bath.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/17-MarksAndMedia/MarblingSteps-dark.jpg">
  <img src="Images/17-MarksAndMedia/MarblingSteps.jpg" alt="Four panels from one bull's-eye of alternating drops: the drops alone as concentric rings, a single stylus pulled down through them into a heart, a comb of teeth feathering them into a nonpareil, and an off-center vortex curling them" width="680">
</picture>

Nearly every classic pattern starts from the bull's-eye in the first panel. A bull's-eye is just concentric drops of alternating color.

```swift
var bath = Marbling()
for i in 0 ..< 20 {
    bath.drop(at: center, radius: 200 - Double(i) * 9,
              color: i.isMultiple(of: 2) ? navy : cream)
}
```

A drop pushes every floating point straight away from its own center, sending a point at distance `d` out to `sqrt(d * d + r * r)`. That particular rule keeps the area around the drop unchanged. It is why earlier rings thin into crescents rather than getting wiped out. Since paper-colored ink displaces just like any other, dropping the color of your background carves negative space.

Then you rake the bath. Four tools do it, and all of them share one rule for how the pull fades with distance. A point `d` away from the tool moves by `strength · 2^(−d / falloff)`, always parallel to the direction the tool traveled. So `strength` is how far the tool itself drags, and `falloff` is the distance at which the pull halves.

```swift
bath.tine(through: center, direction: .unitY, strength: 120, falloff: 48)
bath.comb(through: edge, direction: .unitY, spacing: 110, strength: 260, falloff: 30)
bath.tine(around: center, radius: 200, strength: 300, falloff: 48)
bath.swirl(at: center, strength: 400, falloff: 96)
```

`tine` pulls one stylus along a line, and that is the stroke that drags a bull's-eye into a heart. `comb` pulls a whole row of teeth spaced `spacing` apart. It feathers rows of drops into the pattern marblers call nonpareil. Keep a comb's `falloff` well under its tooth spacing, or the teeth blur together into one broad shear. The circular `tine` drags the stylus around a ring. `swirl` stirs a vortex that spins hardest at its middle, which is the tight curl at the heart of French-curl papers.

Stirring a vortex at the exact center of a bull's-eye does nothing whatsoever. Know that before you spend an evening wondering why the swirl has no effect. Spinning a set of concentric circles about their shared center maps every circle onto itself. The fourth panel above is stirred slightly off-center, which is what a real hand would have done anyway.

`bath.add(shape, color:)` floats an outline you already have, so text outlines can go into the bath and get combed with their counters intact. Nothing in here is random either, so the same operations always produce the same sheet. Randomize the drop positions with the sketch's seeded `random` and the whole paper still comes back from its seed.

```swift
noStroke()
drawMarbling(bath)      // fills every ink in its own color, oldest first
```

Later drops sit above earlier ones and drawing runs oldest first, so the stack reads exactly as it was poured. Every ink is a plain `Shape`, which means a marbled sheet leaves through `--export-svg` as real paths like everything else in this chapter.

### Pigment from a polygon

A pool of paint on wet paper has a dense middle and an edge that wanders, blooming in some places and staying crisp in others. Ollin gets that look from nothing but polygon deformation and translucency.

Start with one irregular polygon. Split every edge at its midpoint, jump that midpoint a small random distance, and repeat. Each edge carries its own variance and passes a decayed share of it to the two edges it splits into. Some stretches of outline bloom, while others stay nearly straight. That inheritance is what keeps the result from looking like a uniformly fuzzy circle. Paint one such outline at about four percent opacity and almost nothing shows. Stack forty independently deformed copies and the middle saturates while the fringe stays uneven, which is what the eye reads as pigment.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/17-MarksAndMedia/WatercolorLayers-dark.jpg">
  <img src="Images/17-MarksAndMedia/WatercolorLayers.jpg" alt="Three panels: a plain ten-sided irregular polygon, one deformed layer of it painted at four percent opacity showing only a faint wandering outline, and forty layers stacked into a solid blue pool with a ragged fringe" width="560">
</picture>

One call does the whole thing:

```swift
fill(Color(hex: 0x2B5D8A))
drawWatercolor(center: center, radius: 300)
drawWatercolor(center: center, radius: 300, layers: 60, opacity: 0.03, variance: 40)
```

`layers` and `opacity` trade against each other, and more layers at a lower opacity looks smoother and wetter. If a blob reads thin and translucent everywhere, add layers rather than raising opacity. The flat saturated core is most of what sells it as paint. `variance` sets how far the edge is free to wander, and it defaults to a fifth of the radius. All of it rides the sketch's seeded `random`. So `seed(_:)` reproduces a painting exactly, and every variation pours a different one.

This is deliberately heavy drawing, since each layer is a full concave fill. Paint in `setup()` or behind `noLoop()` rather than every frame. The cost is one reason, and the other is that regenerating every frame re-rolls the layers and makes the blob shimmer.

Two more moves open up once the basic pool works. For two pigments that mix instead of one covering the other, build a typed `Watercolor` base per pool. Interleave their layers a few at a time, so overlaps glaze in both directions. And for the grainy look of pigment settling into paper, speckle small translucent circles inside a `withClip` of the pool's own outline.

## Putting it together: the monogram

The monogram writes a pair of initials into the heart of a marbled sheet. The sheet comes first, poured with the bath's own moves. A scatter of stones is dropped and combed down and back up into a feathered ground. A bull's-eye goes over it, with a core of paper color. One `tine` pulled down through the eye bends every ring into a heart. Then the initials are written into that pale core, one pen line at a time. Each line is a `StrokeMark` recorded by a pretend hand and drawn through a broad nib over a spray of gold. A dotted rule frames the sheet. Make `MySketches/Monogram.swift`:

```swift
import Ollin

final class Monogram: Sketch {
    @Param var initials = "OL"

    let paper = Color(hex: 0xEFE7D6)
    let navy = Color(hex: 0x1F2A44)
    let red = Color(hex: 0xA43B2A)
    let gold = Color(hex: 0xC8912F)
    let green = Color(hex: 0x3A6B5C)

    var bath = Marbling()
    var strokes: [StrokeMark] = []
    var written = ""

    var sheet: Rectangle { bounds.inset(by: .all(70)) }

    override func setup() {
        seed(4)
        bath = Marbling()
        let inks = [navy, red, gold, green]

        // The ground: stones scattered over the sheet, combed down and back up.
        for _ in 0 ..< 70 {
            bath.drop(at: randomVector(in: sheet), radius: random(20, 55),
                      color: randomChoice(inks))
        }
        bath.comb(through: Vector2(0, height / 2), direction: .unitY,
                  spacing: 90, strength: 200, falloff: 26)
        bath.comb(through: Vector2(45, height / 2), direction: -.unitY,
                  spacing: 90, strength: 140, falloff: 20)

        // The bull's-eye, with a core of paper color to write in.
        let eye = Vector2(540, 420)
        for ring in 0 ..< 10 {
            bath.drop(at: eye, radius: 330 - Double(ring) * 17, color: inks[ring % 4])
        }
        bath.drop(at: eye, radius: 140, color: paper)

        // One stylus pulled down through the eye makes the heart.
        bath.tine(through: eye, direction: .unitY, strength: 240, falloff: 160)
    }

    // A pretend hand: slow into each stroke and out of it, quick through the
    // middle, so the speed brush swells the ends and thins the run.
    func handwrite(_ path: Contour) -> StrokeMark {
        var mark = StrokeMark(.speed(reference: 1200, fast: 0.45), smoothing: 0.4)
        let points = path.resampled(spacing: 3).points
        for (i, p) in points.enumerated() {
            let t = Double(i) / Double(max(1, points.count - 1))
            let pause = 1 + 3 * (1 - sin(.pi * t))
            mark.record(p, deltaTime: pause / 400)
        }
        return mark
    }

    // The initials as single pen lines, each line written by the hand.
    func letter() {
        textFont(StrokeFont.builtIn)
        textSize(150)
        textAlign(.center, .middle)
        strokes = textToShapes(initials, 540, 620)
            .flatMap { $0.contours }
            .map { handwrite($0) }
        written = initials
    }

    override func draw() {
        if written != initials { letter() }
        background(paper)

        noStroke()
        withClip(sheet) { drawMarbling(bath) }

        // A dotted rule around the sheet.
        noFill()
        stroke(navy)
        strokeWeight(5)
        strokeCap(.round)
        strokeDash(.dots(spacing: 16))
        drawRect(bounds.inset(by: .all(48)))
        noStrokeDash()

        // The hand writes for four seconds, rests for four, and starts again.
        let lap = time.truncatingRemainder(dividingBy: 8)
        let total = strokes.reduce(0) { $0 + $1.samples.count }
        var left = Int(min(1, lap / 4) * Double(total))
        var shown: [StrokeMark] = []
        for mark in strokes where left > 1 {
            let part = StrokeMark(samples: Array(mark.samples.prefix(left)))
            shown.append(part)
            left -= part.samples.count
        }

        // Gold dust first, then the ink through a broad nib.
        stroke(gold.withAlpha(0.6))
        strokeWeight(34)
        strokeBrush(.spray(seed: 7))
        for part in shown { drawMark(part) }
        noStrokeBrush()

        stroke(navy)
        strokeWeight(22)
        strokeProfile(.nib(angle: .pi / 5))
        for part in shown { drawMark(part) }
        noStrokeProfile()
    }
}
```

The bath is poured once in `setup()`, because every drop and every comb bends all the ink already floating. The order is the one a marbler follows: the ground, then the eye, then the stylus. The combs run before the eye goes down, so the stones feather while the heart's rings stay clean.

The letters come from the pen font of [Chapter 8](08-Words.md). With `StrokeFont.builtIn` active, `textToShapes` hands back each letter as open pen lines rather than outlines, which are paths a hand could follow. `handwrite` plays the hand. It records the points at an even spacing and changes only how long each step takes. The steps are slow at both ends of a line and quick through the middle. So the speed brush swells a line where a pen would pause and thins it through the run. `initials` is a parameter, so type your own into the inspector. `draw()` compares it with the letters it last wrote and writes new ones when it changes.

The writing is the motion. Each frame, `draw()` works out how many recorded points the hand has reached. It copies that many into a new mark with `StrokeMark(samples:)` and draws only those. The samples keep the widths they were recorded with, so a half-written letter already swells and thins. Both passes draw the same partial marks. The spray goes first, wider and in gold, and then the ink, narrower and through the nib. The nib multiplies the widths the hand recorded, the way a profile does with any mark.

Then make it yours:

- Float the initials instead of writing them. Take them from an outline font, `bath.add` each shape before the `tine`, and the stylus bends the letters along with the rings.
- Change the tool in the ink pass. `strokeBrush(.chisel())` in place of the nib stamps squares that turn with the path, and the letters read as cut rather than written.
- Pool a watercolor wash in the core. Build forty layers from a typed `Watercolor` in `setup()` and fill them faintly each frame before the gold. Painting the wash inside `draw()` would roll new layers every frame and make it shimmer.

Keep both halves of it. The writing is what moves, so `swift run OllinLive MySketches/Monogram.swift --export-gif monogram.gif --seconds 8 --gif-width 480 --fps 15` keeps one full lap as a GIF. The sheet is what prints, and `--export-svg monogram.svg --frame 420` writes it as paths once the letters are finished. Every ink is a filled shape, each letter the region its width covered, and each speck of gold its own circle.

## Where this comes from

Stroke dynamics follow the brush engines of digital painting, which turn how fast a hand moves into how heavy a mark it leaves. Krita and Procreate offer it as a speed setting, and Steve Ruiz's perfect-freehand library estimates pressure from how far apart the points land. The speed a mark measures here is smoothed by the 1€ filter of Géry Casiez, Nicolas Roussel, and Daniel Vogel. The broad nib a stylus leans across is the calligrapher's edged pen, far older than any tablet. The monogram's letters are Hershey Sans, drawn as single pen lines by Allen Hershey at the U.S. National Bureau of Standards.

The marbling equations are Aubrey Jaffer's closed-form model of a craft that predates all of it. The watercolor recipe is Tyler Hobbs', from a generous written guide to simulating paint with generative art. Full credits are in the project's [attribution notes](../ATTRIBUTION.md).

## Go deeper

- [Stroke profiles](../Docs/Drawing/Drawing.md#strokeProfile): `.taper`, `.ramp`, `.nib` and `.values` with every argument, the by-hand closure form, which primitives honor a profile, and what vector export writes.
- [Dashed strokes](../Docs/Drawing/Drawing.md#strokeDash): the pattern and its phase, dots from zero-length dashes, what the cut does to a profile, a brush, and a gradient, which shapes hand their outline over, and what vector export writes.
- [Marks](../Docs/Drawing/Marks.md): `StrokeMark`, the response and dynamics types, what the smoothing and spacing parameters do, building a mark without a pointer, the brushes, and what survives vector export.
- [The stylus](../Docs/Helpers/Input.md#stylus): the lean, the barrel turn, the eraser end, and hovering, read beside `pressure`.
- [Stroke fonts](../Docs/Drawing/Text.md#strokefont): the single-line pen font the monogram is written in, and loading more of them.
- [Marbling](../Docs/Generators/Marbling.md): the bath, every raking tool, and floating your own outlines as ink.
- [Watercolor](../Docs/Generators/Watercolor.md): the sugar, the typed base, and how the deformation actually runs.
- The Mohamedi homage [`Diagonals`](../Examples/Recreations/NasreenMohamedi/Diagonals/Sketch.swift): a chevron is one polyline through its corner with a `.values` profile, full width at the corner and a fraction of it at each tip. That is the mark a loaded ruling pen leaves as it runs out. Its `--export-svg` writes each chevron as the filled outline of the stroke rather than a line with one width, so the thinning reaches the paper, and every hairline of its wakes and fans as a plain line.
- Worked examples: [`Examples/Shapes/StrokeProfiles`](../Examples/Shapes/StrokeProfiles/Sketch.swift), [`Examples/Shapes/Brushwork`](../Examples/Shapes/Brushwork/Sketch.swift), [`Examples/Input/Pen`](../Examples/Input/Pen/Sketch.swift), [`Examples/Shapes/Brushes`](../Examples/Shapes/Brushes/Sketch.swift), [`Examples/Shapes/DashedStrokes`](../Examples/Shapes/DashedStrokes/Sketch.swift), [`Examples/Patterns/Marbling`](../Examples/Patterns/Marbling/Sketch.swift), and [`Examples/Shapes/Watercolor`](../Examples/Shapes/Watercolor/Sketch.swift).

---

[Contents](README.md#contents) · Previous: [Chapter 16, Curves and figures](16-CurvesAndFigures.md) · Next: [Chapter 18, Your first shader](18-YourFirstShader.md)
