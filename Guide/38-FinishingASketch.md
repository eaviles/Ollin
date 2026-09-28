#### <sup>[Ollin](../README.md) → [Guide](README.md) → Chapter 38</sup>

---

# 38. Finishing a sketch

<img src="Images/38-FinishingASketch/ContourChart.jpg" alt="Concentric single-line rings around a still center on cream paper, each ring bent by the same noise field so neighboring rings bend together and the outer ones bend most" width="560">

This chapter takes a sketch from a draft on your screen to files you can keep and share. The practice runs in order. You pick a keeper from a contact sheet and fix its seed and parameters. Then you size it, describe it, export it, and check the recipe the file carries. The steps finish the contour chart above as a poster, a loop, and a plot. After it come finer stills, more kinds of video, and a page that plays in a browser. Then come line work for machines, prints in separate inks, and objects to hold or walk around.

## Every export runs without a window

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/38-FinishingASketch/ExportMap-dark.jpg">
  <img src="Images/38-FinishingASketch/ExportMap.jpg" alt="A diagram with a box labeled your sketch in the middle, arrows fanning left to five file outputs (still, sequence, video, GIF, SVG) and right to three live feeds (the window, Syphon, virtual camera)" width="680">
</picture>

Every file export runs the sketch *headlessly*, with no window. `setup()` runs, the clock advances to the frame you asked for, `draw()` runs, and the result is written. The clock steps by a fixed amount each frame, however long a frame takes to render. So an export repeats. The same sketch, seed, and frame make the same file every time. Sources follow the same clock. A video decodes by frame position. An `AudioPlayer` feeds its analyzer the matching slice of its file each frame. So a sketch that reacts to sound exports with its beats in the same places.

The export flags work on any example's executable. A sketch file of your own gets the same flags through the live host. Here and in the commands below, `MySketches/YourSketch.swift` stands for any sketch of yours:

```sh
swift run OllinLive MySketches/YourSketch.swift --export poster.png --frame 200
swift run --package-path Examples Example-Basic-HelloCircle --export-sequence /tmp/out --seconds 5 --fps 60
```

`--export` writes one frame as a PNG, or as HEIC when the file name ends in `.heic`. `--export-sequence` writes every frame as a numbered PNG, ready for a video editor. `--fps` sets how many frames make a second of the file. It takes a number, a fraction such as `30000/1001`, or the name of a broadcast rate, which the [Export reference](../Docs/Output/Export.md#frame-rates) lists. An export draws at the best render quality, `.detail`, since a file has no frame rate to protect. `--render-quality` lowers it when you want a fast draft.

The right side of the map, the window and the feeds that other apps read live, belongs to [Chapter 39](39-Performing.md#live-feeds-into-other-apps).

## Picking a keeper: a contact sheet and a fixed seed

A sketch that uses randomness is many pictures, one for each seed. Finishing it starts with choosing one, the **keeper**, the variation you will finish. [Chapter 4](04-Randomness.md#finding-a-seed-to-keep) made a **contact sheet** for that, many seeds laid out side by side. A photographer prints a whole roll small the same way, before choosing a frame to enlarge. `--seed` sets the seed the sheet starts from:

```sh
swift run OllinLive MySketches/YourSketch.swift --export-grid sheet.png --seeds 25 --seed 4810
```

That sheet shows seeds 4810 to 4834, each tile labeled with its seed. When a tile is the one, write its seed into `setup()`. The contour chart at the end of this chapter was found this way, at 4821:

```swift
override func setup() {
    seed(4821)          // the variation this keeper was found at
}
```

From then on every export draws that same variation. A sketch that sets its own seed ignores the `--seed` flag, so make the contact sheet before you write this line.

The parameters need the same care. A headless export reads the values written in the code, not the ones you last set in the inspector. So once the sliders feel right, press **Save parameters** in the inspector, which writes each tuned value into its `@Param` line ([Chapter 1](01-HelloOllin.md#saving-the-values-you-tuned)). A value you want for one render only can go on the command line instead, which the recipe step shows.

## Sized for the output: fractions of the canvas, and paper sizes

A keeper often leaves at a size you did not draw it at: a poster, a small loop, a sheet for a pen. A sketch whose sizes are all fractions of the canvas draws the same picture at any of them. [Chapter 1](01-HelloOllin.md#placing-things-without-pixels) showed the habit. Take the shorter side of the canvas as the unit, and write every radius and every line weight as a fraction of it.

The canvas can also be a sheet of paper. `CanvasSize` has named sheets, such as `.a4`, `.a3`, and `.usLetter`, and `.landscape` turns one on its side:

```swift
override var canvasSize: CanvasSize { .a4 }
```

A vector export maps one canvas pixel to one PDF point, 1/72 of an inch, so the exported page *is* that sheet. `.a4.dpi(300)` draws the pixels at 300 dots per inch for a raster export, and the PDF page stays A4. [Canvas](../Docs/Core/Canvas.md#export-size) lists every named sheet.

## Motion: video and GIF

A sketch that moves leaves as video or as a GIF, encoded straight from the frames:

```sh
swift run OllinLive MySketches/YourSketch.swift --export-video clip.mp4 --seconds 12
swift run OllinLive MySketches/YourSketch.swift --export-gif loop.gif --seconds 4 --gif-width 540
```

Reach for video first. A **codec** is the method a video file is compressed with, and `h264`, `hevc`, and ProRes are three of them. The default, `h264`, plays everywhere. `--codec hevc` gives better quality for the same size when the file needs to be smaller. The two ProRes codecs are for editing programs rather than for sharing. `--bitrate`, in megabits a second, sets the file size, and a 1080-pixel square looks clean at about 10 to 15 in `h264`.

A GIF suits a short loop. It holds at most 256 colors a frame, and each second weighs a lot. Keep it to a few seconds, and shrink it with `--gif-width`. A sketch where every pixel changes every frame defeats the format's compression, and the file grows large. The palette starts from the first frame's colors, and later colors join it until all 256 are used. `--gif-palette per-frame` chooses a new palette for every frame, for a sketch whose colors keep changing.

A sketch that declares `loopDuration`, as [Chapter 3](03-MotionAndTime.md#putting-it-together-a-loop-that-never-ends) did, exports one lap with `--export-loop`, and no `--seconds` is needed. The file then repeats without a seam.

## Lines for a pen: SVG and PDF

[Chapter 15](15-ShapesAsMaterial.md#how-a-plot-runs) planned a plot: one file per pen, the pen order, hatch spacing from the nib, and a test strip first. The file that carries all that is written by `--export-svg`:

```sh
swift run OllinLive MySketches/Plate.swift --export-svg plot.svg
swift run OllinLive MySketches/Plate.swift --export-svg plot.svg --hatch
```

The exporter records each draw call as geometry, before any pixels exist. Circles become `<circle>`, polylines become `<polyline>`, or `<polygon>` when closed, and shapes and outline text become `<path>`. Transforms and opacity carry over. The file opens in a browser or a vector editor, and a pen plotter's software reads it. A pen cannot fill, so `--hatch` turns solid fills into parallel lines spaced by tone. Add `--cross-hatch`, or set `--hatch-spacing` and `--hatch-angle`. Stroke fonts and stroked lines pass through as the single lines they already are. Ollin leaves images out of a vector file.

The same recording writes as a PDF with `--export-pdf plot.pdf`, and that is the path to a printer. On a paper-sized canvas the PDF is that sheet, sharp at any printer's resolution. Everything the SVG carries, the PDF carries too, hatching included.

## Saying what it shows: describable output

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/38-FinishingASketch/SayingWhatItShows-dark.jpg">
  <img src="Images/38-FinishingASketch/SayingWhatItShows.jpg" alt="Two columns: on the left a small seascape with a yellow sun high on the left, a blue band of water and a dark sailboat; on the right the four lines the sketch says about itself, a summary followed by the sun, the water and the boat" width="680">
</picture>

A finished picture should reach people who cannot see it. Somebody using a screen reader, a program that reads the screen aloud, gets nothing from pixels. They arrive at your window or your exported drawing and find a rectangle with nothing to say. One line gives it something to say:

```swift
describe("A bay at noon, with a small boat crossing the water.")
```

That sentence becomes the canvas's accessible name, the text a screen reader reads for it. Turn on VoiceOver with ⌘F5 and the window reads it out.

A sketch with things in it can name them. Here `sun` and `boat` are the points the two are drawn at, and each box is the rectangle around one:

```swift
let sunBox = Rectangle(center: sun, width: 80, height: 80)
let boatBox = Rectangle(center: boat, width: 60, height: 44)
describe("the sun", as: "a pale yellow disc high on the left", in: sunBox)
describe("the boat", as: "a small dark hull with one sail", in: boatBox)
```

Each named part becomes something a screen reader can move to. The `in:` region is optional. With one, a listener can find a part by where it is, rather than only in order.

**Write the words from the same numbers that draw the picture.** A description written that way cannot fall out of date. Here `x`, `y`, and `r` are the sun's position and radius, and its height places the disc and chooses the word:

```swift
let p = Vector2(x, y)
drawCircle(center: p, radius: r)
describe("the sun", as: "a yellow disc \(p.y < height / 2 ? "high" : "low")")
```

Call `describe` every frame. Naming a part again replaces what you said, so the list never grows. Empty text takes a part out when it leaves the picture. Naming it again puts it back in the same place, so the reading order stays put.

Keep the parts few, and describe what is there rather than how it is made. Say "a red circle drifting left", not "a `drawCircle` driven by `sin(time)`". A texture is not a part, so the glow around the sun is drawn and not named.

The words travel with the work. An exported SVG carries them as `<title>` and `<desc>`, where a browser and a screen reader look. A PDF carries the summary as its document title. PNG, GIF, and video exports do not carry it. Ollin will not write the description for you. It could list your shapes, but only you know which circle is the sun. [Accessibility](../Docs/Helpers/Accessibility.md) has the rest, and `Examples/Basic/Describing` is a day passing over that bay, saying what it shows as it goes.

## The recipe in the file

Every PNG, SVG, PDF, and video Ollin writes carries a small **recipe** in its metadata, the part of a file that describes the file. The recipe holds the seeds the run used, the value of every `@Param`, and which frame at which rate produced it. It also holds the git commit the code was at, marked dirty if you had uncommitted edits. Read it back with a metadata tool such as ExifTool, which reads the recipe out of the file:

```sh
exiftool -Description poster.png
```

Say you find an image from four months ago that you like. You do not remember which variation produced it, and the sketch has changed since. The file tells you the seed, 48213, the parameter values, and the commit. Check out the commit, pass the seed, and you have it back. Ollin writes no recipe into a GIF.

A recipe leads back to the code only if the code still exists, and uncommitted edits often do not. The commit is marked dirty, and the next save overwrites what you rendered. Add `--capture-source` to any export and the code is kept for you:

```sh
swift run --package-path Examples Example-Randomness-Variations --export keeper.png --capture-source
```

Your working files go into the repository as a commit that sits on no branch, and the file is named after it. `keeper.png` becomes `keeper-93ae989.png`. Your branch, your staged changes, and your edits stay where you left them. Months later the file name is enough to get the code back:

```sh
git show 93ae989:Examples/Randomness/Variations/Sketch.swift
```

[Export](../Docs/Output/Export.md#reproducibility-metadata) lists every field the recipe holds, and [captures that know their source](../Docs/Output/Export.md#captures-that-know-their-source) the rest of that flag.

### Passing the parameters back in

Reading a recipe is half of it. The other half is handing its values back to a run, with the `--param` flag that [Chapter 1](01-HelloOllin.md#a-shorter-way-to-run-things) named. `--param name=value` sets one declared parameter for this run, and it repeats, so a run can carry as many as you need:

```sh
swift run --package-path Examples Example-Live-Parameters --export keeper.png --param radius=40 --param paper=#101018
```

Each value is read by its own parameter's kind. A number stays a number, and a color is a hex string. A 2D vector is two numbers with a comma between them, and a 3D one three. A menu choice is its name, spelled loosely, so `easeOut`, `ease-out`, and `"Ease Out"` all find the same one. The [Export reference](../Docs/Output/Export.md#setting-a-parameter-for-the-run) lists every kind.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/38-FinishingASketch/ParametersBackIn-dark.jpg">
  <img src="Images/38-FinishingASketch/ParametersBackIn.jpg" alt="Three square renders of the same rings-on-paper sketch: two small dark rings on cream under the plain export flag, two large dark rings under param radius equals 90, and four pale rings on near-black under radius 90, rings 4, and a dark paper. Under each render a small card labeled the file's recipe lists the seed and the same parameter values" width="680">
</picture>

The three panels are one sketch rendered with three sets of flags. Under each render is the recipe its file would carry, naming the values it was drawn with. A file tells you its parameters, and the flag hands them back.

The value is set on the parameter before `setup()` runs, and set again after it. So what `setup()` builds reads it, it wins over a value the sketch sets for itself, and the new file's recipe names it. Ask for a parameter the sketch does not have, or a value its kind cannot read, and the run stops and says so. It never renders something you did not ask for.

A sketch you wrote last year, or somebody else's file, does not announce its parameters anywhere. `--list-params` asks it. For a sketch file named `Rings.swift` with five parameters, the listing looks like this:

```sh
swift run OllinLive MySketches/Rings.swift --list-params
```

```
5 parameters, as --param takes them

  radius  Double  120      20...300
  rings   Int     5        1...12
  paper   Color   #FFFFFF
  style   menu    dots     Dots, Rings, Mesh Lines

  Paper
  grain   Double  0.35     0...1
```

Each line gives the name, the kind, the value it holds, and what it will take. Every value is printed the way `--param` reads it, so a line can be pasted straight into a flag. The listing runs `setup()` first and honors anything given beside it. So with `--cue dusk` beside it, which applies a cue, a saved look from [Chapter 39](39-Performing.md#a-look-you-come-back-to-cues), the listing says what that cue holds.

## Putting it together: the contour chart

The contour chart is one keeper made ready to leave. Rings of single lines circle a still center. One looping noise field pushes them in and out, so neighboring rings bend together and the outer ones bend most. It leaves three ways, as a poster, a loop, and a plot, and then its recipe is read back to render it again. Make `MySketches/ContourChart.swift`:

```swift
import Ollin

final class ContourChart: Sketch {
    @Param(4...40) var rings = 22
    @Param(0...0.2) var swell = 0.06
    @Param var paper = Color(hex: 0xF2EDE3)
    @Param var ink = Color(hex: 0x1D2A44)

    let lapSeconds = 8.0
    override var loopDuration: Double? { lapSeconds }

    override func setup() {
        seed(4821)          // the variation this keeper was found at
    }

    override func draw() {
        background(paper)
        noFill()
        stroke(ink)
        let unit = min(width, height)       // every size is a fraction of the canvas
        strokeWeight(unit * 0.002)

        let lap = loopProgress(over: lapSeconds)
        for k in 0..<rings {
            let depth = Double(k) / Double(rings)
            let base = unit * (0.04 + 0.36 * depth)
            let ring = (0..<240).map { j -> Vector2 in
                let angle = Double(j) / 240 * .tau
                let push = signedNoise(cos(angle) * 0.8 + depth * 1.5,
                                       sin(angle) * 0.8, loop: lap)
                let r = base + push * unit * swell * (0.3 + depth)
                return center + Vector2(cos(angle), sin(angle)) * r
            }
            drawPolyline(ring, closed: true)
        }

        describe("\(rings) contour lines around a still center, the outer ones bending most, drifting in an eight-second loop.")
    }
}
```

Most of the listing is the drawing. The rest is what makes it ready to leave, and each part is a step of the chapter:

- **The seed** is the keeper from [the contact sheet](#picking-a-keeper-a-contact-sheet-and-a-fixed-seed). The keeper was 4821, so `seed(4821)` fixes it, and every export draws that same chart.
- **The four parameters** hold the values tuned in the inspector and saved into their declarations.
- **The lap** is declared. The noise is read with `loop:` from [Chapter 5](05-Noise.md#coming-home-the-loop-parameter), and `loopProgress(over:)` runs it through once every `lapSeconds`, so the field drifts and comes home. The same number is `loopDuration`, which lets the loop export find its own length.
- **Every size is a fraction of `unit`**, the shorter side of the canvas, as in [Sized for the output](#sized-for-the-output-fractions-of-the-canvas-and-paper-sizes). The radii and the line weight scale together, so the chart draws the same on any canvas. Every line is stroked, so a pen gets the lines it needs with nothing to hatch.
- **The description** is built from `rings`, so it stays true when the count changes.

> **Swift note.** `(0..<240).map { j -> Vector2 in … }` builds a list of 240 points, one for each `j`. `j -> Vector2 in` names the closure's input and says it hands back a `Vector2`, which helps a reader follow a closure several lines long.

Then make it yours:

- Size it for paper. Add `override var canvasSize: CanvasSize { .a3.dpi(300) }`, and the PDF is a true A3 page. The chart stays centered and sized to the shorter side, since every size in it is a fraction of the canvas.
- Put it on a page. `--export-web contours.html` records one lap with no length given, because the sketch declares it, and the page wraps the lap without a seam. [A page that plays it](#a-page-that-plays-it-the-web-export) has the rest.
- Keep the code with the file. Add `--capture-source` to any of the exports below. Each file is then named after a commit of your working files, so even edits you never committed come back.

When it is ready, it leaves as a poster, a loop, and a plot:

```sh
swift run OllinLive MySketches/ContourChart.swift --export-pdf poster.pdf
swift run OllinLive MySketches/ContourChart.swift --export-loop contours.gif --gif-width 540
swift run OllinLive MySketches/ContourChart.swift --export-svg plot.svg
```

The poster is a PDF, because every line in it is geometry, so it prints sharp at any size. The loop is one lap, with no `--seconds` given. The plot is the same polylines as single paths, in the order they were drawn, and the SVG carries the description with it.

Then read the recipe back. Ollin writes no recipe into a GIF, so read it from the poster. A PDF keeps it in its Subject field:

```sh
exiftool -Subject poster.pdf
```

It names seed 4821, the four parameter values, the frame, and the commit the code was at. To render a sibling with one thing changed, hand a parameter back in:

```sh
swift run OllinLive MySketches/ContourChart.swift --export-pdf dusk.pdf --param paper=#14182A --param ink=#E9DCC4
```

The new file's recipe names the new colors, and the sketch on disk is untouched.

## More from a still: code, finer sampling, linear light, and brighter than white

The chart's poster is all lines, and a line prints sharp at any size. A still made of filled shapes, light, and color asks more of the file. You can render stills from your own code and sample each pixel more finely. You can also keep the light from before it is fitted to a screen, or keep light above white for a display that shows it.

### Rendering from code: `OllinApp.image(of:frame:)`

The export flags wrap one function, and you can call it yourself. Use it to render many pictures on your own terms. Thumbnails for a catalog, a batch over a folder of inputs, and a test that checks a render has not changed all work this way. It is how a render farm or a test suite works, with no screen attached. The figure shows one sketch rendered at four frames, each from a new instance, so every render starts from `setup()`:

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/38-FinishingASketch/HeadlessCapture-dark.jpg">
  <img src="Images/38-FinishingASketch/HeadlessCapture.jpg" alt="Four dark square tiles in a row, each showing the same cluster of green-to-orange circles in a different arrangement, labeled frame 0, frame 30, frame 60, and frame 90, above the caption OllinApp.image(of: Pulse(), frame:), four renders, no window" width="680">
</picture>

```swift
if let frame = OllinApp.image(of: MySketch(), frame: 200) {
    // a CGImage, rendered with no window anywhere in sight
}
```

Here `MySketch` stands for your own sketch's class. `OllinApp.image(of:frame:)` takes the sketch you pass it, runs `setup()`, and advances the clock to the frame you asked for. Then it renders and hands back a `CGImage`, the platform's type for a picture in memory. `OllinApp.export` is that call with a file writer after it, which is all `--export` is. Each job is a loop around this one call, and none of them needs a window.

### Drawing finer than you save: supersampling

`--render-scale` sets quality the other way from `--render-quality`. `--render-scale 2` draws the frame at twice the width and twice the height, then averages every block of four drawn pixels back into one. The file comes out the size it always was. Drawing a picture larger than you keep it and averaging it down is called **supersampling**. It is one of the oldest ways to smooth edges in computer graphics.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/38-FinishingASketch/SamplingFiner-dark.png">
  <img src="Images/38-FinishingASketch/SamplingFiner.png" alt="Two magnified pixel grids side by side showing the same fan of blue rays meeting at a point, labeled render scale 1 with one drawn pixel each and render scale 4 with sixteen drawn pixels averaged; the second fan has softer, more graded edges and a cleaner center" width="680">
</picture>

The difference shows along the edges of filled shapes and the letters of outline text. Those reach the screen as triangles, and every pixel along an edge decides how much of one it covers. A drawn pixel already takes several samples of the triangles, and a larger drawing multiplies them, so the decision gets finer. Circles, rectangles, circular arcs short of a full turn, and every stroked line work out their coverage by formula instead. They are already as sharp as they get, so the setting does nothing for them, and the contour chart's poster gains nothing from it.

The cost is four times the pixels at 2 and sixteen times at 4, the highest setting. It is too slow for a window that owes you a frame every sixteen milliseconds, and cheap for a poster:

```sh
swift run OllinLive MySketches/YourSketch.swift --export poster.png --render-scale 2
```

A blur, a flare, and anything else you asked for with `postProcess` still measure in canvas pixels. A `.gaussianBlur(radius: 12)` is twelve pixels wide at every scale, so the setting never changes the look of an effect.

### The frame before the tone map: OpenEXR

A PNG is a frame in its final form. The renderer adds light up in linear light, with numbers proportional to the light itself, and those numbers run past white wherever a highlight is. The last step folds them into the range a screen can show, the tone map of [Chapter 19](19-LayersAndEffects.md#brighter-than-the-screen-tonemap). Then it rounds each color to one of 256 levels. A PNG is the right file to look at. It is the wrong file for a colorist, who adjusts a film's color, because the part above white is already gone.

`--export-exr` writes the frame one step earlier, as an OpenEXR file. OpenEXR is the format compositing programs read, the programs that layer images into one. Industrial Light & Magic made it for film work and released it in 2003. The figure shows one frame three ways, as a screen shows it, darker so the highlights keep their shape, and as depth:

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/38-FinishingASketch/LinearFile-dark.jpg">
  <img src="Images/38-FinishingASketch/LinearFile.jpg" alt="Three panels of the same 3D scene of glossy spheres along a lane: the first as a screen shows it with flat white highlights, the second sixteen times darker, where those highlights have shape and color, the third a gray depth image where nearer is darker and the distance is bright" width="680">
</picture>

Its red, green, and blue hold the light itself, so a highlight ten times brighter than white is still ten times brighter in the file. Its alpha, the fourth number per pixel, holds how opaque each pixel is, the same transparency `background(.clear)` gives a PNG. If the sketch drew through a 3D camera, a fifth channel, `Z`, holds the distance from the eye at every pixel. It is in the sketch's own units.

Export one frame, or a sequence:

```sh
swift run OllinLive MySketches/Plaza.swift --export-exr frame.exr
swift run OllinLive MySketches/Plaza.swift --export-sequence /tmp/frames --seconds 2 --exr
```


A compositing program holding the depth channel can add fog after the render, at a distance it picks, or throw the background out of focus. A grade, an adjustment of exposure and color, can pull the exposure down. It then finds the shape of a highlight that the PNG clipped to a flat white disk. None of it needs a new render.

The cost is size. The file is uncompressed, so a 1080-pixel square frame with depth is about 14 MB, and a sequence of them is large. Export the moments you need rather than every frame. Surface normals and per-object masks are not in the file. Ollin shades in one pass and keeps no buffer of geometry to write them from. `Examples/Export/LinearFrame` is a lane of glossy spheres under one hard lamp. Its highlights reach ten times over white, and its depth runs from about three units to the far plane.

### Brighter than white: HDR output

The EXR keeps the light above white for another program. Some displays can show part of it directly, which is called HDR, for high dynamic range. Tone mapping is what you do when the screen cannot go any higher, and a recent Apple display sometimes can.

That display holds two things back from an ordinary sketch. It can show colors more saturated than sRGB, the standard range of screen colors, can describe. It can also, for a while, make small areas brighter than white. One declared line switches both on:

```swift
final class Lamps: Sketch {
    override var colorOutput: ColorOutput { .extended }
}
```

Now a value of 2.0 is drawn twice as bright as white. White text beside it stays white while the lamp's core glows. Leave `toneMap` off here. `.aces` exists to squash those values back under 1.0, which you no longer want.

The other half is color. `Color` stays an sRGB type, and a color outside that range is named in Display P3, the wider range of recent Apple displays:

```swift
fill(Color(displayP3: 1, green: 0, blue: 0))    // a red sRGB cannot make
```

Its stored components come out slightly outside 0…1, which is how a color says it goes further than sRGB. Nothing clamps it on the way through. On a `.standard` sketch it lands on the nearest sRGB red at the end, so naming one is always safe.

The brightness depends on the display having room to spare at that moment, which it calls headroom. The system gives and takes it as screen brightness changes. Read `displayHeadroom` to see what you got, where 1.0 means none.

An exported PNG keeps the wide color but not the brightness, because PNG stops at white. Two formats keep both. An `.extended` sketch's `--export-video` is written as HDR10, the usual format for HDR video, with no extra flags. A still asked for by name as HEIC, the format iPhone photos use, keeps its highlights:

```sh
swift run --package-path Examples Example-Rendering-ColorOutput --export lamp.heic
# Ollin: exported frame 0 → lamp.heic (1080×1080, highlights to 2.70x white in a gain map)
```

The picture inside that file is the PNG's picture, so any viewer can open it. Beside it sits a record of the light that was clipped away, called a **gain map**. Its form is set out in the standard ISO 21496-1. A display with headroom puts the light back. A page like this one cannot show light above white, so the figure shows the two parts of such a file instead:

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/38-FinishingASketch/WhatTheStillKeeps-dark.jpg">
  <img src="Images/38-FinishingASketch/WhatTheStillKeeps.jpg" alt="Two dark square panels with a plus sign between them. Left, a soft lamp whose center is a flat white plateau, beside a small white bar labeled white. Right, the same frame as a gain map: black everywhere except a small soft gray disc where the lamp's core was, labeled as reaching 2.7 times white" width="680">
</picture>

The left panel is the picture inside the file, clamped at white, and the lamp's flat plateau is where everything above 1.0 went. The right panel is a gain map, drawn in shades of one gray. It is black where the frame stayed in range, and it gets brighter the further above white a pixel went. A display with headroom multiplies the two together, and the plateau turns back into a lamp. Run [`Examples/Rendering/ColorOutput`](../Examples/Rendering/ColorOutput/Sketch.swift) on a recent Mac laptop to see it, and turn the screen brightness down while you look.

## More ways to leave as motion: transparency, broadcast rates, slow motion, and settled frames

The chart leaves as one lap of a GIF, and it could leave as an `h264` video. Other settings change what a video holds. A clip can keep a see-through background, or keep a broadcast's frame rate to the fraction. It can run slower than the sketch did, or wait for a picture to settle before each frame is written.

### Leaving the background behind: transparent video

A canvas that starts with `background(.clear)` leaves its background out of the file. Ed Catmull and Alvy Ray Smith gave computer pictures this fourth channel in the 1970s. Use it for a sketch that goes over a camera feed or another layer rather than over black. That happens in an editing program, or in a VJ program, the software a video jockey performs live visuals with. The PNG gets an **alpha channel**, the fourth number per pixel that says how opaque it is. A video keeps one only when its codec carries one. `--codec proRes4444` is the one for an editing program, and `hevcWithAlpha` makes a file a fraction of that size. `h264` has no alpha channel, so it is drawn over black, and the export says so. The window draws the same frame over black too, so open the file to see the cut.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/38-FinishingASketch/LeavingTheBackground-dark.jpg">
  <img src="Images/38-FinishingASketch/LeavingTheBackground.jpg" alt="One export of a cluster of translucent lobes and a white ring, drawn three times: over the checkerboard an image editor shows behind a see-through file, over a blue and teal layer with soft shapes, and over black" width="680">
</picture>

The figure is one export drawn three times. The first panel is the PNG as an image editor shows it, with a checkerboard standing for the transparency. The second is the same file over another layer, which is what a compositing program does with a `proRes4444` or `hevcWithAlpha` clip. The third is over black, which is what the window showed while you drew it, and what `h264`, `hevc`, and `proRes422` keep.

Look at the edge of the white ring in the first two. A pixel the ring half covers keeps the ring's white at half coverage, rather than turning gray. A blur or another frame filter runs on the frame with each color already multiplied by its coverage, which is called **premultiplied**. So it spreads the coverage along with the color. A live feed keeps the alpha too. In code, `VideoCodec.carriesAlpha` tells the two kinds of codec apart, and `Examples/Export/Cutout` is the cluster of lobes in the figure.

### The grid a broadcast asks for: named frame rates

A clip for a broadcast or an edit has a frame rate somebody else chose. It is often a fraction, such as the 29.97 frames a second of NTSC, the color television standard North America adopted in 1953. The `--fps` flag takes a name for those, and the name is the safer thing to type:

```sh
swift run OllinLive MySketches/YourSketch.swift --export-video spot.mp4 --seconds 30 --fps ntsc
```

`ntsc` is 30000/1001 rather than its decimal. So the frames land where a broadcast editor expects them, however long the clip runs. In code the same parameter is a `FrameRate`, and a plain number still stands in for one. The [Export reference](../Docs/Output/Export.md#frame-rates) has the named rates, the fractions they keep, and what drifts when a decimal is used instead. The live window runs at the display's own rate, and `frameRate` on the sketch reads what it measured.

### Slower than it happened: slow motion

Some sketches move faster than the eye can follow, such as a collision or a burst. On screen you can only watch it again. In a file you can slow it down, the way film does by shooting more frames a second than it plays. The figure shows the frames a slow-motion export adds:

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/38-FinishingASketch/SlowerThanItHappened-dark.jpg">
  <img src="Images/38-FinishingASketch/SlowerThanItHappened.jpg" alt="Two rows of exported frames of a mark crossing a track: a top row of four frames outlined in orange labeled what the sketch drew, 30 a second, and a bottom row of ten frames labeled --slow-motion 3, 90 a second, with hairlines joining each top frame to the bottom frame showing the same moment" width="680">
</picture>

`--slow-motion` renders more frames of the same stretch of time:

```sh
swift run OllinLive MySketches/YourSketch.swift --export-video slow.mp4 --seconds 4 --slow-motion 4
```

That renders four seconds of the sketch's own time and writes sixteen seconds of video. The file still plays at its `--fps`. What changes is how many frames cover the run. The clock steps four times finer, so the sketch is asked for the moments in between. The motion then takes four times as long to play.

`--seconds` still counts the sketch's own time, and the export prints both lengths. The figure uses `--slow-motion 3`, which puts two more frames between each pair the sketch drew at 30 a second.

**Motion measured in seconds slows down, and motion measured in frames does not.** A radius built from `sin(time)` follows the clock, and a finer clock slows it. So does a position moved by `speed * deltaTime`. A position moved by a fixed step once per `draw()`, with no `deltaTime` in it, moves the same amount every frame. The finer clock does not change it. If a slow-motion export comes out at ordinary speed, that is why, and the `deltaTime` of [Chapter 3](03-MotionAndTime.md#when-a-frame-takes-too-long) is the fix.

When a frame is expensive to draw, the GPU can make the frames in between instead:

```sh
swift run OllinLive MySketches/YourSketch.swift --export-video half.mp4 --seconds 4 --slow-motion 2 --made-frames
```

`--made-frames` draws the frames it would have drawn anyway, and asks the GPU to build the ones in between from the pair on either side. It is the interpolator a live window can use ([Chapter 31](31-TracedLight.md#drawing-fewer-frames-frame-interpolation)). The made frames are pictures your sketch never drew, so the export says so on the console and writes `"madeFrames":true` into the file's recipe. It needs a 3D scene under a perspective camera, and it only halves the speed. [Export](../Docs/Output/Export.md#slow-motion) compares the two ways.

### Settled, then written: a running mean in a video

Some pictures are not finished by one draw. A running mean, the `Accumulator` from [Chapter 19](19-LayersAndEffects.md#converging-instead-of-brightening-the-running-mean) or a `LineSpray` through a lens from [Chapter 31](31-TracedLight.md#a-lens-made-of-samples-depth-of-field-from-light), starts grainy and settles as frames pile up. It starts over whenever the camera moves. In a video of a turning scene every frame has a new camera, so every frame is the grainy first one. `--settle N` draws each written frame N times with the clock held, and writes the last:

```sh
swift run --package-path Examples Example-Rendering-LineSpray --export-video turn.mp4 --seconds 10 --settle 40
```

The clock does not move during the held draws. A camera driven by `time` stays put while the mean settles, and then the clock steps on. It costs N times a plain export. The [export reference](../Docs/Output/Export.md#settled-frames) has what it refuses, and why a `noClear` canvas that piles up is the one thing it does not settle.

## A page that plays it: the web export

The chart could also leave as a page. A video carries pixels, and a page can carry what made them. `--export-web` records what the sketch draws over a duration, frame by frame at a fixed rate. Then it writes a page that plays the recording back in a browser, with the motion and the parameters still live:

```sh
swift run OllinLive MySketches/YourSketch.swift --export-web page.html --seconds 6
swift run OllinLive MySketches/YourSketch.swift --export-web page.html --seconds 6 --inline
```

The recorder writes down the shape records the renderer would have received each frame. Nothing is rendered on the Mac, so nothing that depends on the Mac's GPU lands in the file. The page draws those records with the framework's own shape shader, rewritten from Metal to GLSL. GLSL is the shader language of WebGL2, the browser's graphics interface. The GLSL import of [Chapter 18](18-YourFirstShader.md#somebody-elses-shader-glsl-import) does the same kind of rewriting in the other direction. A frame on the page matches the frame `--export` gives, to within a few levels.

A sketch that declares `loopDuration` records one lap with no length given, and the page wraps it without a seam. On a lap, each motion is fitted to the sine waves it is made of. The page then works it out at any moment from a few numbers. A parameter can be driven by a formula, a rule written as text in [Chapter 39](39-Performing.md#writing-the-parameter-as-a-rule-formulas). It crosses as the formula, worked out on the page's own clock. What fits neither travels as samples, and the page blends between them.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/38-FinishingASketch/PageFromRecords-dark.jpg">
  <img src="Images/38-FinishingASketch/PageFromRecords.jpg" alt="Three panels joined by arrows: the frame the Mac renders of a ring of twelve circles; a card listing what the recorder writes, the base stored once, the three moving columns fitted to sines, and the three parameters wired as controls; and the page as a browser window with the same ring on its canvas and a slider and two color wells under it" width="680">
</picture>

The figure follows one ring of circles across. On the left is the frame the Mac renders. In the middle is what the recorder wrote instead of pixels, twelve circles a frame. The parts that never change are stored once, and the three that move are kept as columns. The sketch declared a lap, so each column is fitted to sines. On the right is the page, with the three parameters the exporter could wire, offered as a slider and two color wells. The size on the arrow is the page's measured weight, and most of it is the player and its shaders rather than the ring.

The first form is one file you can open, host, or place in another page with an `iframe`. The second, `--inline`, is the canvas and one script block with no page around them, to paste into a page you already have. The script leaves a handle on the canvas, `canvas.ollin`, that plays, pauses, and seeks. A reader whose system asks for less motion sees the first frame, still.

The sketch's parameters cross as controls. After recording, the exporter tries each `@Param` at a few other values, records again, and checks that what moved changed along a straight line. Each parameter that passes is offered as a slider, a stepper, a checkbox, or a color well. A parameter that changes what is drawn, or moves a number some other way, stays at its recorded value. The exporter says which and why.

Most 2D drawing crosses. It includes the shapes, strokes, fills, and text of the earlier chapters, and the layers and filters of [Chapter 19](19-LayersAndEffects.md). Your own shaders, pictures, and the fields of [Chapter 30](30-SculptingWithFields.md) cross too. A video clip, a mesh, and a few other calls stop the export before a file is written. The message names the call and the frame where it met it. Those sketches leave as video. [Web page](../Docs/Output/Web.md#what-crosses) lists everything that crosses and what the page weighs. [`Examples/Web/BreathingRing`](../Examples/Web/BreathingRing/Sketch.swift) is a sketch to try it on.

## Line work for machines: G-code, embroidery, DXF, and a 3D scene

The chart's SVG goes to a plotter's own software, which plans the moves. Other machines take their instructions more directly. A plotter, laser, or router can run a program of moves, an embroidery machine reads stitches, and a shop opens a drawing sorted into jobs. A 3D scene can become line work too.

### Driving the machine itself: G-code

**G-code** is a program of moves in millimeters, the language many hobby plotters, laser cutters, and CNC routers run. A CNC router is a cutter a computer drives. Use G-code to drive a machine directly, without its own software in between. It grew out of the numerical control of machine tools in the 1950s and was standardized as RS-274. Nearly every computer-driven machine tool reads a version of it. `--export-gcode` writes one from the same recorded frame as the SVG:

```sh
swift run OllinLive MySketches/Plate.swift --export-gcode plot.gcode
swift run OllinLive MySketches/Plate.swift --export-gcode cut.gcode --gcode-machine laser
```

A machine needs real units, so the export asks for a physical width. The flag maps the canvas to 150 mm wide unless `--gcode-width` says otherwise. In code, `GCode(.plotter(), width: 150)` carries the finer settings: the pen lift, a laser's power and passes, a router's depth per pass. A named sheet saves the arithmetic. `GCode(.plotter(), paper: .a4)` fits the drawing inside an A4 page with ten millimeters clear on every side. On the command line, `--gcode-paper a4` does the same. Only line work travels. A stroke is drawn along its centerline, and a fill gives its outline, with `--hatch` shading fills as it does for SVG.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/38-FinishingASketch/OnTheSheet-dark.jpg">
  <img src="Images/38-FinishingASketch/OnTheSheet.jpg" alt="Four sheets of paper drawn to one scale, A3 lying wide, A4, A4 again with a tall canvas holding two roses, and US letter, each with its rose curves planned inside its margin and the millimeters they came to printed under it: 267 by 267, 190 by 190, 156 by 277, and 196 by 196" width="680">
</picture>

The figure plans a drawing of rose curves onto four sheets and prints the size each came to. On A4 with the default margin, the drawing is 190 millimeters square, the sheet's width less ten on each side. The drawing is held to the sheet's height as well as its width. So a canvas much taller than it is wide, 1080 by 1920 here, scales down to the 277 millimeters an A4 leaves for height. It comes out 156 wide. The A3 sheet lies wide with a 15-millimeter margin, which `margin: 15` sets in code and `--gcode-margin 15` sets on the command line. Its square drawing stops at 267 millimeters, the sheet's height less two margins. The drawing starts at the lower-left corner of the margin, one margin in from the corner the machine counts from. So a narrower fit sits at the left of the sheet, and a shorter one sits at the bottom. The [G-code reference](../Docs/Output/GCode.md) lists every named sheet, and `DXF(paper:)` sizes a shop drawing the same way.

The exporter plans the route before it writes a move. Open paths whose ends touch merge, so the pen stays down across them. Then the paths are reordered, each one starting near where the last one ended, to keep the moves with the pen up short:

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/38-FinishingASketch/MachineRoute-dark.jpg">
  <img src="Images/38-FinishingASketch/MachineRoute.jpg" alt="Two panels of the same sun-and-wave line work. In the drawn order the pen-up travels tangle across the page at 991 mm; planned, they walk neatly around the shapes at 390 mm" width="680">
</picture>

The planner is public. `GCode.toolpath(_:in:)` returns the route as plain contours, with the drawn and travel lengths in millimeters. The `Export/Toolpath` example walks a pen along its own route at machine speed. Give any program a dry run first, with the pen out, the laser disarmed, or the cutter above the material. [G-code](../Docs/Output/GCode.md) has the three machine profiles and every setting.

### Thread instead of ink: embroidery

An embroidery machine is a plotter that sews. It moves a hoop under a needle, and every move ends with the needle going down. It puts line work on cloth. Ollin writes a frame as those moves, in the `.dst` format of the Tajima machines, which nearly every machine reads.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/38-FinishingASketch/StitchPlan-dark.jpg">
  <img src="Images/38-FinishingASketch/StitchPlan.jpg" alt="Two panels: a green leaf with pale veins drawn as contours, and the same leaf as its stitches, a dot at every needle penetration along the outline and the veins, rows of stitches filling the leaf, and thin hops where the thread is carried between paths" width="680">
</picture>

In code the call takes an instance of your sketch, here `sketch`, such as `YourSketch()`, and a width. `try?` skips the write if it fails. On the command line the flag works on any sketch:

```swift
try? OllinApp.exportEmbroidery(sketch, to: "leaf.dst", settings: Embroidery(width: 100))
```

```sh
swift run --package-path Examples Example-Export-Embroidery --export-embroidery leaf.dst
```

Three things change on the way from pixels to thread. A stroke becomes a **running stitch**, a line of needle holes no farther apart than `stitchLength`, with every corner hit. A fill becomes rows of running stitch across it, `fillSpacing` apart and joined end to end, so the thread stays down. And every color becomes its own thread, in the order you drew them. A `.dst` file holds no colors, only stitches, jumps, and the stops between threads, so you load each thread when the machine asks for it. What you drew later is sewn later and lies on top.

The width is yours to give, as for G-code, because a hoop has real millimeters. Between two paths the thread is sewn across when the gap is short, and carried over in a jump when it is not. The planner reorders the paths within each thread to keep those jumps short. [Embroidery](../Docs/Output/Embroidery.md) has the settings and what to check before you sew.

### A drawing for the shop: DXF

A laser shop, a waterjet, or a sign maker opens a drawing in its own software and sets up the job there. That software reads **DXF**, the drawing exchange format Autodesk introduced with AutoCAD in 1982. It tells one job from another by the layer a line sits on. Use it when somebody else's machine cuts your work. `--export-dxf` writes the frame as that drawing, with each color on its own layer, as the figure shows:

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/38-FinishingASketch/LayerStack-dark.jpg">
  <img src="Images/38-FinishingASketch/LayerStack.jpg" alt="Two panels: a coaster drawn in three colors, an outline to cut, rings to score, and a rosette to engrave, and the same drawing pulled apart into three layers, one per color, each labeled with its layer name and the entities on it" width="680">
</picture>

From the command line, or in code with `sketch` as before:

```sh
swift run OllinLive MySketches/Plate.swift --export-dxf plate.dxf
```

```swift
try? OllinApp.exportDXF(sketch, to: "plate.dxf", settings: DXF(width: 150))
```

So the sketch's colors sort the work. Draw the outline in one color, the fold lines in another, and the engraving in a third, and the file arrives sorted into three jobs. A layer is named by its color's bytes, such as `color-1B1040`. It also carries the nearest of the few standard colors a DXF names by number, and close colors land on the same one. Here the red and the blue both come out gray, so the layer names are what keep the jobs apart.

The width is yours to give here too. Strokes arrive as lines and polylines along their centerlines, and fills as their outlines, unless hatching turns them into line work. A circle that nothing has skewed stays a circle, which a cutter drilling a hole prefers. Paths whose ends touch merge into one, and a clip cuts the work as it cuts the render. [`Examples/Export/Drafting`](../Examples/Export/Drafting/Sketch.swift) draws a box panel that way and lists its layers. Check the drawing's size against the material in the shop's software before anything moves.

### A 3D scene on the plotter: `lineDrawing(of:)`

A vector file has nowhere to put a lit surface, so everything [Chapter 25](25-3DGently.md) and [Chapter 26](26-Meshes.md) drew stops at the raster. `lineDrawing(of:)` takes the same meshes and the same camera and hands back 2D paths. They are the lines a draftsman would draw, with everything the surfaces hide taken out. Use it to send a 3D scene to a pen. It follows the conventions of technical drawing, where hidden edges are left out or dashed. The figure shows one scene both ways:

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/38-FinishingASketch/SceneAsLines-dark.jpg">
  <img src="Images/38-FinishingASketch/SceneAsLines.jpg" alt="Two panels of the same scene, a slab with a cylinder, a cube and a ball on it: on the left every edge the drawing considers, with the covered ones ghosted in gray, and on the right the drawing with those taken out" width="680">
</picture>

Here `meshes` is a list of meshes, each already placed:

```swift
camera(Camera3D(eye: Vector3(6.4, 4.6, 7.2), target: Vector3(0, 0.7, 0)))
stroke(.black)
noFill()
for line in lineDrawing(of: meshes).paths {
    drawPolyline(line.points, closed: line.isClosed)
}
```

Three kinds of line are kept. The **silhouette** is where a surface turns away from the camera, the outline of a ball or a cylinder. A **crease** is where two faces meet at more than `creaseAngle`, the edge of a cube or the rim of a cap. A **boundary** is where a surface ends. The triangles inside a smooth surface are left out, which is why the ball is a circle rather than a net. Lower the crease angle and gentler ridges show. At 0 every edge is kept, which is a wireframe.

Everything handed to one call hides everything else in it, which is why it takes a list of meshes. `Mesh.transformed(by:)` puts each one where it belongs first, taking the same `MeshInstance` the instanced draws take. Two separate calls are two drawings that know nothing of each other, and the near one will not hide the far one.

The paths are ordinary line work, so `--export-svg`, `--export-gcode`, and `--export-dxf` all take them. They are also paths on the canvas, so a brush or a hand-drawn wobble can go on them. The covered stretches are kept as `lineDrawing(of:).hidden`, and drawing them faint or dashed shows what is behind, as the left panel does. [Line drawing](../Docs/3D/LineDrawing.md) has the rest.

## Printing in inks: separations and proofs

The chart's poster prints on any printer. Some presses print one ink at a time, and every press prints fewer colors than a screen shows. Two tools prepare for that. Separations split a picture into one plate per ink, and a soft proof shows the picture as the press will print it.

### Printing one ink at a time: separations

A risograph, a stencil printer that prints one ink at a time, or a screen-printing press lays down one ink per pass. It needs a separate grayscale plate for each ink, each a **spot ink**, one named ink mixed before printing. Use separations to print a sketch in a few chosen inks. The method is the standard one in prepress, where each ink acts as a colored filter over the paper. Each ink gets a **master**, a grayscale image where black means full ink and white means bare paper. The press runs the paper through once per master, and the inks stack up.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/38-FinishingASketch/Separations-dark.jpg">
  <img src="Images/38-FinishingASketch/Separations.jpg" alt="Four panels: three grayscale masters labeled fluorescent pink, blue, and yellow, each carrying a different part of one photograph of a woman before a wall of marigolds, followed by the color preview of the three overprinted, which reads as the photograph again" width="680">
</picture>

Printing inks are see-through, so overlapping inks mix. Pink over blue makes a purple that neither ink could print alone. So three plain-looking plates make a picture with more than three colors. Read the plates against the photograph. The flowers take nearly all the yellow plate has, and the blue one leaves them bare and goes to the woman instead. The pink one runs mid-gray almost everywhere, which is what a warm picture asks of it.

```swift
override var printInks: [Ink]? { [.fluorescentPink, .blue, .yellow] }
```

Declare that on your sketch and export with `--export-separations`. You get one master per ink, plus a preview with registration marks, the small crosses that line the passes up. Check the preview before committing to paper. In code, `artwork.separated(into:)` does the same to any `Image`, so you can look at the plates while you compose.

For a color no single ink can make, Ollin searches for the mix of ink coverages whose overprint comes closest. It measures closeness the way the eye does, in the same perceptual space [Chapter 2](02-Color.md)'s color mixing uses. Draw in an ink's own color and it separates without loss. Anything else, gradients and photographs included, lands on the nearest mix those inks can reach.

A press cannot hold a dot smaller than about two percent coverage, so anything fainter drops to bare paper. `separation.halftoned(pitch:)` turns each plate into dots `pitch` apart, as in [Chapter 9](09-Pictures.md)'s halftone. It turns each ink's grid of dots to its own angle. The inks then overprint into a small rosette rather than a moiré, the wavy stripes two grids make. `PrintSeparation.screenAngles(for:)` says which angle each ink got, and `separation.dithered()` is the grainier choice. [Print separations](../Docs/Output/PrintSeparations.md) has the ink catalog, with the measured colors of the standard risograph inks, and the screening details.

### Seeing the print before you print it: soft proofs

A screen makes color with light, and a press makes it with ink on paper. The screen reaches colors the ink cannot. A bright screen cyan is not a color four inks can lay down. It comes back from the press as the nearest thing ink can do. A **soft proof** shows that on screen first. Use one before you pay for paper.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/38-FinishingASketch/ProofBeforePrint-dark.jpg">
  <img src="Images/38-FinishingASketch/ProofBeforePrint.jpg" alt="Three panels of one photograph of a woman before a wall of marigolds: as the screen shows it, the same picture proofed for a four-ink press with the orange gone duller, and the gamut check with most of the wall replaced by gray" width="680">
</picture>

A **profile**, an ICC profile, is a file that describes what one device does with color. Its format comes from the International Color Consortium, founded in 1993. Your print shop can give you the one for the press and paper the job will run on. Ollin carries a generic four-ink one for when you have not asked yet:

```swift
var press = SoftProof(.genericCMYK)     // or ICCProfile(contentsOf: theShopsFile)
postProcess(.softProof(press))          // the canvas, as it will print
```

Every color on the canvas is carried into the press's profile and back out again. Whatever comes back changed is what the press will change. It runs on the GPU, so you can leave it on while you work. Two things always move on that trip. Saturated colors come back duller, because ink reaches fewer colors than a lit screen. Blacks come back lighter, because ink on paper is not as dark as a black pixel. Paper color is a third, and you ask for it with `press.simulatesPaper = true`.

The proof shows what changes. The **gamut check** marks what the press cannot reach at all, the gamut being the range of colors a device can make. The third panel paints those colors gray, and the call takes the warning color you choose:

```swift
postProcess(.softProof(press, warning: .magenta, amount: 0))   // flag it, change nothing
artwork.outOfGamutFraction(press)                              // 0…1, how much is at risk
```

Print that fraction while you tune a palette. A few percent is ordinary. A third of the canvas means you are drawing in colors that will not survive the press. The marigolds are past half, because a wall of cempasúchil is the orange four inks reach for and miss.

When the sketch is ready, the same profile splits it into **plates**, one grayscale image per ink:

```swift
override var printProfile: ICCProfile? { .genericCMYK }
```

Declare that, and `--export-plates poster.png` writes the four plates plus the proof, with registration marks, as `--export-separations` does for spot inks. The separation also reports **total ink**, the sum of all four coverages at the heaviest spot. Ask your shop what they will take. Around 300% is usual for coated paper, and newsprint takes less.

The profile tells the two paths apart. Spot separations are for a shop printing named inks one at a time, where no profile exists and Ollin models the overprint. Plates are for a press whose behavior has been measured, where the profile answers directly. [Print color](../Docs/Output/PrintColor.md) has the rest.

## Objects: a 3D print, a model, and spatial video

The chart is flat, and so is every file above. A 3D sketch can leave as something with depth. A mesh can be printed as a solid, and a scene can be handed over as a model to walk around. Motion can be recorded from two eyes at once.

### Something you can hold: a 3D print

A 3D printer builds a `Mesh` as a solid object. Use it to hold a shape your sketch made. Here `sculpture` is a mesh the sketch built, and the call is short:

```swift
try? sculpture.normalized(scale: 60).write(to: "sculpture.3mf")
```

A mesh carries bare numbers, and a printer needs millimeters. `normalized(scale: 60)` centers the shape on the origin, where a build platform wants it, and fits its longest side to 60 mm. The extension picks the file format: STL, OBJ, or 3MF, three common formats for 3D printing. The file records that size, and `try?` skips the write if it fails.

A shape can look finished on screen and still be impossible to print. A printer has to decide, for every point in space, whether it is inside the object or outside. It can only answer if the surface closes. Here are two copies of the same knot, one swept closed and one left open at its ends:

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/38-FinishingASketch/Fabrication-dark.jpg">
  <img src="Images/38-FinishingASketch/Fabrication.jpg" alt="Two gold torus knots side by side; the left is labeled closed and ready to print, the right open at the ends with 36 edges bordering a hole" width="680">
</picture>

On screen an open surface looks as solid as a closed one. So check before you print:

```swift
let check = sculpture.printCheck()
print(check.summary)        // "9360 triangles, 60.00 x 52.50 x 26.02 units: ready to print"
```

`printCheck()` reports whether the surface closes, and whether neighboring triangles agree on which side is outside. It also reports whether the shape is inside out, and how big the file says it is. When something is wrong, `problems` says so in words. A mesh that fails is still written, with a note, because an open surface is fine to draw and only a print needs it sealed.

A shape that closes by construction saves the repair. The metaballs and isosurfaces of [Chapter 30](30-SculptingWithFields.md#the-other-way-out-field-to-mesh) close, since a field has an inside. So do the solid primitives and a tube swept with `closed: true`. A plane, or a lathe without caps, does not.

One more thing happens on the way out. Ollin's mesh generators make flat-shaded meshes, so every triangle carries its own three corners, and neighboring triangles share no corner at all. Read as a solid, that is nothing but holes. The writers merge those duplicate corners first and settle which way each triangle faces against the mesh's own normals. They also stand the model up on the z axis, because Ollin's world has y up and a build platform does not. [Fabrication](../Docs/Output/Fabrication.md) has the details, and `Examples/3D/Geometry/Fabrication` is the knot above, with parameters.

### Something you can walk around: USDZ

**USDZ** is the model format Apple's platforms open without extra software, and it holds a whole 3D scene rather than one mesh. Use it to hand over a scene that the viewer turns and walks around. It packs Pixar's Universal Scene Description into one file, a form Apple and Pixar made together in 2018. A scene leaves as one with `--export-usdz`:

```sh
swift run --package-path Examples Example-3D-Geometry-Solids --export-usdz solids.usdz
```

Double-click the file and Quick Look, the Mac's preview, opens it, and a message shows it too. On an iPhone, tap the AR button, and the camera view shows the scene standing on the floor in front of you. It stands at the size the file gives it. An app for Apple's headset can use it as a model directly. The stills, videos, and drawings above are pictures of the sketch from one camera. A model holds the scene itself, and whoever opens it picks their own angle.

Any `Scene` writes the same way, including one you loaded or built by hand. A frame becomes a scene when you ask for one. Here `scene` is a `Scene` and `sketch` an instance of your sketch, and `try?` skips a failed write:

```swift
try? scene.write(to: "model.usdz")
let frameScene = OllinApp.spatialScene(of: sketch, frame: 120)
```

That hands back an ordinary `Scene`, the kind [Chapter 26](26-Meshes.md#a-scene-with-its-camera-and-lights-loadscene) loaded from a file. You can look at what your own frame is made of, move a node, and write it out. One writer serves both paths, so the file and the frame agree.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/38-FinishingASketch/SpatialExport-dark.jpg">
  <img src="Images/38-FinishingASketch/SpatialExport.jpg" alt="Two arrangements of a yellow sphere, blue rounded box and green torus; the left is surrounded by scattered gray dust motes, the right has none" width="680">
</picture>

The figure shows the rule. On the left is a frame with dust drawn around its solids. On the right is what a model of that frame holds, the solids without the dust. **A model file holds surfaces**. Meshes travel with their transforms, colors, textures, and as much of their finish as the format has room for. The camera and the lights travel too. A point cloud, a GPU particle system, and a raymarched field are not surfaces, so they stay behind. So does 2D drawing, which is why a labeled diagram arrives without its labels. Ollin prints one note for each thing it left.

To send a field or a cloud, give it a surface first. The `isosurface(at:in:field:)` of [Chapter 30](30-SculptingWithFields.md#any-field-as-a-mesh-isosurface) and the `particleSurface(of:radius:)` of [Chapter 33](33-DepthAndThePhone.md) each turn one into a mesh, and a mesh always travels.

One number decides how big the model is when it arrives:

```swift
try? scene.write(to: "model.usdz", metersPerUnit: 0.05)
```

A model file records how big one scene unit is, and nothing is scaled on the way out. At the default of 1, a sphere of radius 1 arrives two meters across. For something someone will set on a table, a value between `0.01` and `0.1` is usually right.

The lights travel, but an [environment](../Docs/3D/3D.md#environment-lighting) does not. A viewer supplies its own, and in AR that is a camera looking at the room the viewer is in. A metal surface exported this way reflects the room it ends up in. [Spatial](../Docs/Output/Spatial.md) has the full list of what travels, and `Examples/3D/Geometry/SpatialExport` is a ring of solids with a save key.

### Something you can look into: spatial video

A model lets someone choose an angle because the scene holds still. Motion is handed over another way, as **spatial video**, recorded from two eyes at once, the way you see the room around you. It is the format Apple's platforms record and play with depth, introduced in 2023 with Apple Vision Pro. Use it for a moving 3D sketch someone watches in a headset. Its two cameras stand side by side and look parallel, the rig that Lenny Lipton's *Foundations of the Stereoscopic Cinema* set out in 1982:

```sh
swift run --package-path Examples Example-3D-Geometry-SpatialVideo --export-spatial colonnade.mov --seconds 8
```

The drive is the export you already know, on the same fixed clock. The difference is that each frame is rendered twice, from two cameras a little way apart, and the two views travel together in one file.

Two numbers decide how the depth looks, and choosing them is part of composing the shot.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/38-FinishingASketch/StereoPair-dark.jpg">
  <img src="Images/38-FinishingASketch/StereoPair.jpg" alt="A plan-view diagram: two eyes at the bottom looking parallel, a horizontal line labeled the screen, and three objects whose sight lines land on the screen as paired marks, crossed for the near object, coincident at the screen, spread apart for the far one" width="680">
</picture>

**Convergence** is the distance at which the two eyes agree. Follow a line from each eye through an object to the screen. The two landing places are where each eye sees it. For something at the convergence distance they land together, so it appears *on* the screen. For something nearer, the lines have already crossed, and the marks come out the wrong way round. Your eyes read that as an object in front of the screen. Farther away, the marks spread apart the ordinary way, and the object sits behind. So choosing the convergence distance chooses what sits on the screen, with nearer things in front of it and farther things behind.

**Interocular** is how far apart the eyes stand, in world units, and it sets the amount of depth. Half reads flatter. Twice reads deeper, and then it starts to hurt. Left alone, Ollin puts the eyes 1% of the frame's width apart, measured at the convergence distance. At that distance the far background separates by 1% of the frame too, which is less than a viewer's own eyes span. So nothing ever asks their eyes to turn outward, which is the one thing stereo must never do.

A sketch declares both the way it declares a loop:

```swift
override var stereoGeometry: StereoGeometry {
    StereoGeometry(interocular: 0.1, convergence: 6)
}
```

Leave either out and it is worked out from the camera. The convergence distance then defaults to what the camera points at, the thing the sketch is about. `--interocular` and `--convergence` override either one for a single export, which is the quickest way to try values.

The frame is **drawn once and rendered twice**. Drawing again would roll the sketch's randomness a second time and step every simulation a second time. Some simulations do not repeat, so the two eyes would see different worlds. One draw with two cameras gives both eyes the same instant. It follows that anything the sketch already flattened while drawing keeps its one answer. A `project(_:)`, a `depth(at:)` placement, and a billboard each land flat on the screen in both eyes, which suits captions and overlays. A 2D sketch comes out flat and says so, and so does an accumulating sketch, because its pile lives in one surface.

The file records how far apart the eyes that shot it were, so a player can scale the depth it shows. `--meters-per-unit` says what a world unit is, as for a model. [Spatial](../Docs/Output/Spatial.md#spatial-video) has the rest, and `Examples/3D/Geometry/SpatialVideo` is a colonnade that recedes far from the camera, with both numbers on parameters.

## Where this comes from

The contact sheet is the photographer's, a whole roll printed small to choose from. The pen-plotter revival that SVG export serves grew around the AxiDraw plotter and the #plottertwitter community. They carry on from the computer-art plotters of the 1960s that this guide's recreations visit. Reading a recipe back uses Phil Harvey's ExifTool, the common reader for the metadata a file carries. Full credits are in the project's [attribution notes](../ATTRIBUTION.md).

## Go deeper

- [Wide gamut & HDR output](../Docs/Drawing/ColorOutput.md): `colorOutput`, colors outside sRGB, and what each export format carries.
- [Export](../Docs/Output/Export.md): every flag, codec advice, GIF timing, SVG mapping, hatching, the named frame rates, and transparent output.
- [Perfect loops](../Docs/Output/Export.md#perfect-loops), [contact sheets](../Docs/Output/Export.md#contact-sheets-proofing-a-variation-space), and [the recipe](../Docs/Output/Export.md#reproducibility-metadata): the lap an export finds for itself, the sheet a keeper is chosen from, and where each format keeps its recipe.
- [Web page](../Docs/Output/Web.md): the flag and its length, what crosses and what stops the export, the two forms, the handle on the canvas, and what the page weighs.
- [Print separations](../Docs/Output/PrintSeparations.md): the spot-ink model, the ink catalog, screening angles, and the overprint preview.
- [Fabrication](../Docs/Output/Fabrication.md): writing a mesh as STL, OBJ, or 3MF, real-world sizing, and what makes a surface printable.
- [G-code](../Docs/Output/GCode.md): the three machines and their parameters, a named sheet, what the planner does, previewing the route, and the dry run.
- [DXF](../Docs/Output/DXF.md): a frame as the drawing a shop program opens, each color on its own layer, with circles kept as circles and touching paths merged.
- [Line drawing](../Docs/3D/LineDrawing.md): a 3D scene as the line work a machine can follow, which edges are kept and why, placing several meshes so they hide each other, and what the hidden set is for.
- [Canvas](../Docs/Core/Canvas.md): the canvas presets, the named paper sheets, and the export size.
- [Print color](../Docs/Output/PrintColor.md): profiles, the soft proof, the gamut check, and the four plates.
- [Spatial](../Docs/Output/Spatial.md): what a USDZ model carries, and spatial video with its two numbers.
- [Accessibility](../Docs/Helpers/Accessibility.md): `describe` and the rest of what makes a sketch readable without sight.
- [Embroidery](../Docs/Output/Embroidery.md): a frame as the stitches a machine sews, with strokes as running stitch, fills as rows, and each color as its own thread.
- Worked examples: [`Examples/Export/`](../Examples/Export/).

---

[Contents](README.md#contents) · Previous: [Chapter 37, Music by rule](37-MusicByRule.md) · Next: [Chapter 39, Performing](39-Performing.md)
