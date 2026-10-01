#### <sup>[Ollin](../README.md) → [Guide](README.md) → Chapter 9</sup>

---

# 9. Pictures and data

<img src="Images/09-Pictures/TypeMosaic.jpg" alt="A portrait of a young woman in a lace headdress built entirely from the word OLLIN repeated in a grid, the letters large and white where the lace is, smaller and warm across the face, and small and dark in the hair and the blouse" width="560">

Pictures and tables arrive from outside your sketch, and you read both the same way, as grids you ask questions of. This chapter reads them one sample at a time and turns each sample into a mark of your own. One photograph, sampled a few thousand times, becomes the portrait at the top, each sample a letter sized and colored by its pixel. Then the chapter fits a picture to its box, answers a pixel other ways, from dithering to a hidden shape, and reads CSV and JSON.

## A picture on the canvas: `loadImage` and `drawImage`

Images follow the habit from [Chapter 4](04-Randomness.md#finding-a-seed-to-keep), where the rolls happened once in `setup()`: load once there, keep the result, draw it in `draw()`.

```swift
final class Photo: Sketch {
    var photo: Image?

    override func setup() {
        photo = try? loadImage("/Users/you/Pictures/leaf.jpg")
    }

    override func draw() {
        background(.black)
        if let photo {
            drawImage(photo, 0, 0, width, height)     // stretched to fill
        }
    }
}
```

`loadImage` reads anything the system can decode (PNG, JPEG, HEIC, and friends). It throws when the path is wrong or the file is not a picture, and `try?` turns that into `nil`. The line `if let photo {` is the short form of [Chapter 2](02-Color.md)'s `if let`. It unwraps the optional under the same name, and it skips the block when there is nothing. `drawImage` places the image by its top-left corner, at native size or scaled into a box. It composites in draw order with everything else and follows the transform stack like a shape. For an image that travels with your sketch, drop the file in the same folder. Load it with `try? Image(resource: "leaf", withExtension: "jpg", in: .module)`, where `.module` names the folder the sketch's own files are read from.

One piece of state changes how images land: `tint`. It multiplies every pixel by a color as the image draws, so the RGB washes the image and the alpha fades it:

```swift
tint(Color(red: 1.0, green: 0.75, blue: 0.4))   // a warm wash
drawImage(photo, 0, 0, width, height)
tint(Color(white: 1, alpha: 0.3))               // ghostly, 30% opacity
drawImage(photo, 60, 60, width, height)
noTint()                                        // back to as-is
```

Tint never edits the image itself, only how it is drawn, and `withState { }` scopes it like any other state.

### A working copy: `resized` and `cropped`

A picture arrives at one size, and the size you work at is the next choice:

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/09-Pictures/WorkingCopy-dark.jpg">
  <img src="Images/09-Pictures/WorkingCopy.jpg" alt="Three panels of the same photograph of a colonial street. Left, the picture as loaded at 1600 by 1600. Middle, its 300 by 300 working copy shown at the same scale as a small square and then up close, with the note that it has 28 times fewer pixels to read. Right, the picture faded to a ghost with its widest 3:2 piece drawn at full strength inside an orange frame, at 1600 by 1067. The credit the picture carries runs along the foot" width="680">
</picture>

A 1600-pixel square is more than a stipple, a dither, or a mosaic needs. Those are three ways of redrawing a picture, and this chapter teaches them after the sketch. Each of those reads every pixel, and they were tuned on a copy a few hundred pixels a side. `resized(width:height:)` makes that copy. `SamplePhoto.city.load().resized(width: 300, height: 300)` is the call, and the copy has twenty-eight times fewer pixels to read. Keep the small copy for the reading and the full picture for the drawing. `cropped(toAspect:)` is the other kind of change. The call `SamplePhoto.city.load().cropped(toAspect: 3.0 / 2)` takes the largest 3:2 piece out of the square and scales nothing. So a square photograph can stand in for a wide one.

`SamplePhoto` is where that street came from. Ollin bundles twenty photographs to try, and `import OllinSamplePhotos` makes them available. The call `SamplePhoto.portrait.load()` hands you a young woman in a lace headdress at 1600 pixels square. The [Sample photographs](../Docs/Drawing/SamplePhotos.md) reference shows all twenty on one page, each under its name, with what it is for. Each one carries its `credit`: the photographer, the place, the page it came from, and the terms it is used under. `SamplePhoto.city.credit.line` is the sentence at the foot of the figure, ready to draw. The terms do not ask for it. The Guide gives it anyway.

## An image you can ask: `image[x, y]`

Drawing a picture is the smaller half of what `Image` does for generative work. The larger half is *reading* it. The subscript `image[x, y]`, the same square brackets that read one entry of a list, returns the color stored at a pixel. So a picture becomes a field of answers, like [Chapter 5](05-Noise.md)'s noise but authored by a camera or by you:

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/09-Pictures/PixelSampling-dark.jpg">
  <img src="Images/09-Pictures/PixelSampling.jpg" alt="Left, a photograph of a woman in profile on a plain tan ground; right, the same picture redrawn as a grid of dots on a dark ground, each dot taking its pixel's color and sized by its brightness, so the ground is large tan dots and the face is small dark ones" width="680">
</picture>

The right panel asks the image one question per grid cell and draws the answer as a dot. The recipe has two small pieces. First, a cell's position maps to a pixel index by fractions. A cell at fraction `u` across the grid reads column `Int(u * Double(image.width - 1))`. Rows work the same way, so any grid samples any image size. Second, call the color a pixel answers with `c`. Its red, green, and blue read back as `c.red`, `c.green`, and `c.blue`, and those are its three channels. Asking "how bright is this pixel" takes one more line than the three suggest, because your eye does not weigh them equally. Green counts most and blue least, and the standard weights are

```swift
let brightness = c.red * 0.2126 + c.green * 0.7152 + c.blue * 0.0722
```

and that single number is the handle generative artists pull most: size by it, choose by it, gate by it. [Appendix B](B-JustEnoughMath.md#perceived-brightness) keeps this one, since averaging the channels instead makes yellows read too dark and blues too bright. Ollin also carries the ask as a property, `c.luminance`. It measures a touch more faithfully, on the channels converted to the light the screen emits, which [Appendix B](B-JustEnoughMath.md#light-and-the-number-stored-for-it-linear-light) draws. The handwritten weights are the idea, and the property is the everyday spelling.

You can also write pixels. The initializer `Image(width:height:)` makes a blank image, and `image[x, y] = color` paints one pixel. So a picture can come out of code as readily as out of a file. Run a double loop over every pixel, color each from a [Chapter 2](02-Color.md) ramp read by height, and add a little [Chapter 5](05-Noise.md) noise. The result is a sky or a field in twenty lines of `setup()`. The [`PixelField`](../Examples/Images/PixelField/Sketch.swift) example builds one this way, reading a colormap along a diagonal wave instead of by height. Every picture tool in this chapter reads an authored image the way it reads a photograph.

## Putting it together: a picture painted with type

This is the sketch from the top of the chapter. It composes the loading and the working copy from [A picture on the canvas](#a-picture-on-the-canvas-loadimage-and-drawimage) with the sampling from [An image you can ask](#an-image-you-can-ask-imagex-y). It answers each sample with words drawn by [Chapter 8](08-Words.md)'s `drawText`, so the picture is *made of* the words. A message repeats across a grid in reading order. Each letter samples the photograph at its own position, takes the pixel's color, and scales by its brightness.

It is a glyph mosaic, a picture made of one character per cell, and this one is built by hand on purpose. The finished glyph mosaic after the sketch does it in one line, with a ramp of characters ordered by how much ink each puts down. But it chooses the character for you, and this sketch needs the characters to spell something. Building the grid yourself is what lets it spell. Make `MySketches/TypeMosaic.swift`:

```swift
import Ollin
import OllinSamplePhotos

final class TypeMosaic: Sketch {
    @Param("Columns", 24...80) var columns = 64
    @Param("Message") var message = "OLLIN "
    @Param("Breathe", 0...1) var breathe = 0.5

    var source: Image?

    override func setup() {
        noiseSeed(3)
        source = SamplePhoto.portrait.load().resized(width: 160, height: 160)
        textFont(OutlineFont.systemBold)
        textMode(.atlas)                   // thousands of glyphs a frame
        textAlign(.center, .middle)
        noStroke()
    }

    override func draw() {
        background(Color(hex: 0x0B0E14))
        guard let source else { return }
        let chars = Array(message.isEmpty ? "OLLIN " : message)
        let cell = width / Double(columns)
        let rows = Int(height / cell)
        var k = 0

        for row in 0..<rows {
            for col in 0..<columns {
                let u = (Double(col) + 0.5) / Double(columns)
                let v = (Double(row) + 0.5) / Double(rows)
                let c = source[Int(u * Double(source.width - 1)),
                               Int(v * Double(source.height - 1))]
                let brightness = c.red * 0.2126 + c.green * 0.7152 + c.blue * 0.0722

                // Bright pixels get big letters; a slow noise field makes the
                // whole picture breathe without changing what it says.
                let sway = 1 + signedNoise(u * 3, v * 3, time * 0.25) * 0.18 * breathe
                textSize(cell * (0.4 + 1.25 * brightness * brightness) * sway)
                fill(Color.mix(c, .white, brightness * 0.22))
                drawText(String(chars[k % chars.count]),
                         (Double(col) + 0.5) * cell, (Double(row) + 0.5) * cell)
                k += 1
            }
        }
    }
}
```

Run it with `swift run OllinLive MySketches/TypeMosaic.swift` and take it apart:

- `resized(width:height:)` makes the 160-pixel working copy the grid reads, the habit from [A working copy](#a-working-copy-resized-and-cropped). Each pixel of the copy is roughly the average of a ten-by-ten patch of the original. So a letter reads the whole of its cell, not whichever single pixel happens to sit under its center.
- The double loop is [Chapter 6](06-GridsAndRepetition.md)'s grid chore done by hand, because what it loops over is the *message*. The index `k % chars.count` deals the letters out in reading order, so the rows spell the message over and over. The `u`/`v` fractions map each cell onto its pixel.
- `brightness * brightness` is contrast shaping, since squaring pushes mid grays down so the lace pops. The `fill` mixes each pixel's color a step toward white in the brightest cells, which makes the lit lace read as light rather than paint.
- Setting `textMode(.atlas)` matters here, because sixty-four columns is a few thousand glyphs per frame. The atlas mode draws each as one cheap textured quad instead of re-tessellating outlines. It is the volume switch for text, one line.
- `Breathe` feeds a slow `signedNoise` into the letter sizes, so the picture shimmers without changing what it says. The `Message` parameter is a text field in the live window, so type into it and the portrait respells itself as you watch.

> **Swift note.** `guard let source else { return }` is the `guard let` from [Chapter 7](07-Tiles.md). Calling `Array(message)` turns a string into a list of its characters. That list lets `chars[k % chars.count]` deal them out like [Chapter 1](01-HelloOllin.md)'s palette cycling.

When a portrait is a keeper, export it as a still:

```sh
swift run OllinLive MySketches/TypeMosaic.swift --export portrait.png
```

Then make it yours:

- Swap the picture. Putting `SamplePhoto.scarf.load()` in place of the portrait's load is the only change. A picture of your own is `try? loadImage("/path/to/yours.jpg")`, unwrapped the way the first listing did. A face reads at 60 to 80 columns, and a street wants more. A picture you author with `Image(width:height:)` reads the same way.
- Change the alphabet. A message of `"·•●"` becomes halftone dots, and `textFont(BitmapFont.builtIn)` in `setup()` makes it a terminal.
- Sample with an offset. Read the pixel at `u + time * 0.01` (wrapped with `fract`) and the picture slides through the words.
- Recolor by replacing the sampled color with `Colormap.magma.color(at: brightness)` for a duotone poster.
- Trade the letters for line work. Feed the same picture to `singleLine(of:points:in:)`, from [A picture as one line](#a-picture-as-one-line-stippling-singleline-and-spanningtree), and the poster becomes one unbroken thread a plotter could draw.

## Getting a picture into place: a drop, `fit`, and seam carving

The portrait loaded a bundled photograph and only read it, never drawing the picture itself. A picture you do draw has to get into the sketch and then into a box, which is rarely its own shape. A drop on the window is the quickest way in, and `fit` and seam carving settle a picture into its box.

### A picture you drop on the window

A path typed into `loadImage` is fine for a picture you keep. For one you want to try, drop it on the window. The sketch is told at the drop by `filesDropped()`, a hook like [Chapter 2](02-Color.md#putting-it-together-a-color-field)'s `mousePressed()`. The paths arrive through `droppedFiles()`, and `mouse` says where the file landed:

```swift
override func filesDropped() {
    for path in droppedFiles() {
        if let picture = try? loadImage(path) { pictures.append((picture, mouse)) }
    }
}
```

Here `pictures` is a list the sketch keeps. Each entry is a pair, a picture with the point it landed at. Swift writes a pair in parentheses, as `(picture, mouse)`. `mouse` is `mouseX` and `mouseY` as one `Vector2`.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/09-Pictures/DroppedOnTheWindow-dark.jpg">
  <img src="Images/09-Pictures/DroppedOnTheWindow.jpg" alt="A diagram of a file tile labeled marigolds.jpg leaving the Finder on a dotted trail that arcs into a dark sketch window, where the picture sits a little turned on a white border under an orange crosshair labeled mouseX, mouseY. An orange line in the window's corner reads not a picture: notes.txt. Callouts say the Finder hands over a path, not a picture, and that a file that is not a picture is still a path to name" width="680">
</picture>

Reading `droppedFiles()` empties the list of dropped paths. So a sketch that would rather poll can call it in `draw()` instead and get each drop once. Anything the Finder can hand over comes through, a clip or a font as readily as a picture. A file the sketch cannot use is still a path it can name, the way the orange line in the figure does. Every host takes the drop wherever the sketch is running: the live window, the gallery, and the performance stage with its code hidden. A drop is live input that a recording does not keep, so a replay from [Chapter 43](43-Performing.md#playing-the-night-again-replay) never repeats one. [`Examples/Images/Dropped`](../Examples/Images/Dropped/Sketch.swift) starts as an empty frame and lands every picture where you drop it.

### The box is never the right shape: `fit`

The chapter's first `drawImage(photo, 0, 0, width, height)` did something quietly: it stretched. A photo is 3:2 or 4:3, your canvas is square or portrait, and squashing is only one of three answers. `fit:` names all three, and every one of them gives something up.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/09-Pictures/PictureFit-dark.jpg">
  <img src="Images/09-Pictures/PictureFit.jpg" alt="The same 3:2 photograph of a city street drawn into three 2:3 boxes: stretched, where the round dome of a church goes narrow; contained, where the whole picture sits in a band with the box showing above and below; and covered, where the box is full and only the middle of the width is left" width="680">
</picture>

- `.stretch` fills the box and gives up the picture's proportions. It is the default, because it is what `drawImage` has always done.
- `.contain` keeps the proportions and puts the whole picture inside, centered. It gives up part of the box, which shows along two edges.
- `.cover` keeps the proportions and fills the box, centered. It gives up the picture's own edges, cropped away.

```swift
drawImage(photo, in: panel, fit: .cover)
```

The `in:` form takes a `Rectangle`, here one called `panel`, and `fit:` says how the picture meets it. Each answer is right for a different loss. A wallpaper covers, because a strip of empty screen would be worse than a missing corner. A photograph in a contact sheet contains, because you are there to see all of it. A texture on a panel stretches, because nobody is checking its proportions.

A round shape in the picture is the fastest way to tell which one you are looking at. Stretched, it is an ellipse. The church dome in the figure gives the game away in all three panels at once.

Cropping costs nothing here. `.cover` does not clip the drawing. It reads a smaller part of the picture instead. So a covered photograph costs the same one quad and one texture read as a stretched one.

### Making it narrower without squashing it: seam carving

The three answers above keep every pixel and change how the picture sits in the box. A fourth changes the picture's own shape, and tries hard to leave the looking alone.

Say a picture is 1200 wide and the space it has to fit is 800. You can squash it with `.stretch`, and everything inside gets a third thinner. You can crop it with `.cover`, and lose whatever was at the edge. **Seam carving** is the fourth answer. Find the path down the picture that carries the least, take it out, and the picture is one pixel narrower. Do that four hundred times. Shai Avidan and Ariel Shamir published the method in 2007 as an answer to a plain engineering problem. A photograph on a web page has to fit whatever window it lands in.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/09-Pictures/CarvedNarrower-dark.jpg">
  <img src="Images/09-Pictures/CarvedNarrower.jpg" alt="A photograph of a Guanajuato alley at its own width, squeezed to 70% where the walls lean in and every window narrows, and carved to 70% where the sky between the walls gives up the most width and the walls narrow less" width="680">
</picture>

```swift
let narrow = picture.seamCarved(toWidth: 800)
```

A *seam* is a run of pixels, one per row, that never steps more than one pixel sideways from the row above. The cheapest one is the one whose removal changes the picture least, and finding it is the whole of the technique.

Here is the rule that decides everything: **texture survives, and flat gives way.** A path down an empty sky costs nothing, because closing that gap puts two pixels beside each other that already matched. A path through a doorway costs a great deal, because closing that gap makes an edge that was not there before. So the sky goes and the doorways keep their width.

That also means a flat thing is not safe. The pastel walls are nearly one color each, so they are cheap too. In the carve above they have already narrowed, though less than the sky has. A mask tells the carve what to leave alone:

```swift
let held = picture.seamCarved(toWidth: 800, protecting: sunMask)
let gone = picture.seamCarved(toWidth: 800, discarding: signMask)
```

A mask is a picture the same size, marked in white. `protecting:` prices those pixels out of reach, so no seam crosses them. `discarding:` does the opposite. It makes them the cheapest thing in the picture, so seam after seam is drawn straight through them. Carve away as many seams as the marked thing is wide and the thing has left. Carve the width back up afterwards and it is gone, at the size you started with. That is the trick the technique is famous for.

Growing works the same way in reverse. Ask for a bigger size and the same cheap seams are duplicated instead of removed. The added pixels spread over the whole picture rather than stretching one part of it.

Two practical notes. One seam is one pass over the picture, so a hundred seams is a hundred passes. Like any heavy work on a picture, that is `setup()` work. If the width has to keep changing while the sketch runs, work the seams out once and read any width back out of the result:

```swift
var seams: SeamMap?   // every seam the picture holds, worked out once

override func setup() {
    seams = picture.seamMap()
}

override func draw() {
    let wanted = Int(300 + sin(time) * 120)
    if let framed = seams?.image(wanted) { drawImage(framed, in: canvasRectangle) }
}
```

> **Swift note.** `seams?.image(wanted)` is optional chaining. When `seams` is `nil` the whole expression is `nil` and the `if let` skips, and when it holds a map the call goes through. `canvasRectangle` is the same rectangle as [Chapter 7](07-Tiles.md)'s `bounds`, the whole canvas.

And carve gently. Taking away a quarter of the width is usually invisible. Taking away three quarters is a different picture, whatever the arithmetic says. At some point the only thing left to take is the thing you wanted.

## The colors read back: palettes and dithering

The portrait read one pixel at a time and answered each with a letter. A palette taken out of the picture and a picture dithered back into fewer colors both read the whole picture at once. The portrait has no use for either. But a palette from a photograph is a palette nobody else has. Dithering is what you reach for when you have fewer colors than a picture needs.

### Palettes from a photograph

Reading one pixel gives you one color. A [`Palette`](02-Color.md#kits-you-carry-palette-and-ramp) can come out of the whole picture at once. It is for a sketch that should take its colors from a photograph you took, and for a poster that reduces one. The grouping is Lloyd's algorithm, the clustering method from 1957. It moves each group's center to the middle of its members until nothing moves. It picks its starting centers the k-means++ way, from a fixed seed, so the same picture gives the same groups. Give `Palette(extractedFrom:count:)` an image and how many colors you want, and it hands back the center of each group:

```swift
let photo = try! loadImage("beach.jpg")
let p = Palette(extractedFrom: photo, count: 5)
fill(p[0])     // the color the photo is mostly made of
```

The `try!` there says the file is there, as [Chapter 2](02-Color.md)'s palette files did, and the block below does it the careful way. The colors come back most-used first, so `p[0]` is the one you would name if someone asked what color the photo is. The grouping happens in OKLab for the same reason [mixing](02-Color.md#mixing-you-can-trust) does. In OKLab it groups colors the way your eye does, rather than the way the numbers do. Ask for fewer colors than the picture holds and it merges the closest ones together instead of dropping any.

Two practical notes. The first is that it gives the same answer every time for the same picture. So a sketch that extracts a palette still reproduces, which matters once you start exporting. The second is that it does enough work that you do not want it running sixty times a second. Load the photo and extract the palette once in `setup()`, keep both in properties, and let `draw()` read what is already there:

```swift
var photo: Image?
var palette = Palette([])

override func setup() {
    photo = try? loadImage("beach.jpg")
    if let photo { palette = Palette(extractedFrom: photo, count: 5) }
}
```

### Fewer colors than the picture needs: dithering

Dithering puts a picture back together in fewer colors than it has. It scatters the colors you do have so that the eye reads the tones in between. It is for a poster in five inks, a screen with a small palette, and the look of old print and old computers. The two families here are Bryce Bayer's ordered matrix of 1973 and the error diffusion Robert Floyd and Louis Steinberg published in 1976. Once you have a palette, one call does it:

```swift
if let photo {
    let poster = photo.dithered(.floydSteinberg, to: palette)
    drawImage(poster, in: bounds)
}
```

Every pixel of the result is one of your five colors, and `bounds` fills the frame as it did in [Chapter 7](07-Tiles.md). The word is the thing to understand, because the problem it answers keeps coming back.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/09-Pictures/Dithering-dark.jpg">
  <img src="Images/09-Pictures/Dithering.jpg" alt="Four panels: a smooth color gradient, then the same gradient reduced to five colors three ways. The first reduction shows wide flat bands, the second a regular crosshatch grain, the third an organic scattered grain, and both of the latter read as the original gradient from a distance" width="680">
</picture>

The first panel is the picture as it came. Snapping each pixel to the nearest available color is the obvious way to fit it into five, and the second panel shows what that costs. Smooth regions turn into flat bands with hard edges, because a whole stretch of subtly different tones all round to the same color. Dithering trades those bands for texture. Where a tone falls between two of your colors, it scatters both of them in the right proportion. At any normal distance your eye blurs them together and reads the tone that was there. The picture keeps its gradients using colors it does not have.

The two families look different on purpose.

**Threshold maps** decide each pixel from its position alone, using a repeating tile. The method `.ordered(size: 8)` uses a Bayer matrix and lays down the regular crosshatch of retro graphics and old newsprint. By contrast, `.blueNoise` uses a tile with no structure in it and gives an even, pattern-free grain. Because the decision is positional, these are cheap and completely local.

**Error diffusion** works differently. It commits to a color for one pixel and measures how far off that was. Then it pushes the leftover error onto neighbors it has not reached yet, so every mistake is corrected nearby. `.floydSteinberg` is the classic, and it gives the organic scattered look in the last panel. `.atkinson` throws away a quarter of the error on purpose, which blows highlights and shadows out to clean white and black. That look has a name because people go looking for it.

A few practical notes. `.none` skips the scattering entirely, which is what the second panel uses and what you reach for to show someone the difference. A second form, `dithered(.atkinson, levels: 2)`, posterizes. It quantizes to evenly spaced steps per channel instead of to a palette. And this is CPU work over every pixel, so do it in `setup()` and hold the result rather than redoing it each frame. [The color reference](../Docs/Drawing/Color.md#dithering) has the full method list, and [`Examples/Color/Dithering`](../Examples/Color/Dithering/Sketch.swift) puts five methods beside the original.

## A picture as marks: glyphs, dots, pictures, lines, and thread

The portrait was a mosaic built by hand, one letter per cell, so that the message could spell something. When the marks need not spell anything, Ollin ships that move finished, along with dots, small pictures, one line, one tree, and a wound thread. Every one descends from the 1880s newspaper halftone: pick a mark, vary it by the brightness underneath, and let the eye rebuild the picture.

### One mark per cell: `drawGlyphMosaic` and `drawHalftone`

A glyph mosaic puts one character in each cell of a grid, and a halftone puts one dot in each cell, grown to the tone. Both are for a picture that reads as texture from a distance and as marks up close, and a pen can draw the halftone. The glyph mosaic is the picture a line printer made in the 1960s, and the halftone is the printing industry's answer from the 1880s. The mosaic grows its mark with brightness and the halftone with darkness, so one of them takes `inverted: true` when both should read alike.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/09-Pictures/PictureAsGlyphs-dark.jpg">
  <img src="Images/09-Pictures/PictureAsGlyphs.jpg" alt="Two dark panels showing the same photograph of an older woman in a scarf: on the left a mosaic of ASCII characters that get denser where the face and the scarf are lit, on the right a halftone screen of dots that grow in the same places" width="680">
</picture>

```swift
textFont(BitmapFont.builtIn)
fill(.white)
noStroke()
drawGlyphMosaic(picture, columns: 72)             // one character per cell
drawHalftone(picture, pitch: 14, inverted: true)  // one dot per cell, light on dark
```

The measured ramp, the sets, the screen angle, and the data forms are on the [glyph mosaic](../Docs/Drawing/GlyphMosaic.md) and [halftone](../Docs/Drawing/Halftone.md) pages, with worked sketches in [`Examples/Images/GlyphMosaic`](../Examples/Images/GlyphMosaic/Sketch.swift) and [`Examples/Images/Halftone`](../Examples/Images/Halftone/Sketch.swift).

### A picture made of pictures

A photo mosaic rebuilds a target out of a library of smaller pictures, one per cell. It is for the picture that rewards a second look. From across the room it is the target, and up close every cell is a picture of its own. Robert Silvers wrote his MIT Media Lab thesis on the photographic mosaic in 1996 and applied for its patent in 1997. The idea of one picture built from many is older than photography. Each cell of the target takes the library picture whose linear-light average is nearest.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/09-Pictures/PicturesFromPictures-dark.jpg">
  <img src="Images/09-Pictures/PicturesFromPictures.jpg" alt="Three panels: a photograph of a young woman in a lace headdress, the same picture rebuilt as a grid of small tiles cut from the bundled photographs, and a block seven cells across enlarged so each is visibly a piece of a real picture" width="680">
</picture>

```swift
let mosaic = target.mosaic(of: library, columns: 32, rows: 32)
drawMosaic(mosaic, of: library, in: bounds, tint: 0.25)
```

The linear-light rule, `tint` and `maxUses`, and the range both sides need are on the [photo mosaic page](../Docs/Drawing/PhotoMosaic.md), with the worked sketch in [`Examples/Images/PhotoMosaic`](../Examples/Images/PhotoMosaic/Sketch.swift).

### A picture as one line: stippling, `singleLine`, and `spanningTree`

Stippling places loose dots whose density reproduces a picture's tone. Then `singleLine` and `spanningTree` join the dots into one closed tour or one branching tree. All three are for the drawings a pen makes, which are dots and lines and never a fill. Stippling with dots of even weight was a hand discipline in scientific illustration long before Adrian Secord gave it an algorithm in 2002. Robert Bosch and Craig Kaplan made the tour popular in the mid-2000s as TSP art, named after the routing problem that finds it.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/09-Pictures/PictureAsLines-dark.jpg">
  <img src="Images/09-Pictures/PictureAsLines.jpg" alt="Three panels: a stipple of the profile photograph, dense in the face and hair and empty on the plain ground, the same dots joined into one maze-like unbroken tour, and the same dots joined into the branching chains of a spanning tree" width="680">
</picture>

```swift
let dots = stipple(of: picture, count: 4000, in: frame)
let tour = singleLine(through: dots)          // one closed loop
let chains = spanningTree(through: dots)      // branching, the fewest pen lifts
let line = singleLine(of: picture, points: 4000, in: frame)   // both steps in one call
```

The settling method, the one-call forms, and `cutoff` are on the [stippling](../Docs/Generators/Stippling.md), [single line](../Docs/Generators/SingleLine.md), and [spanning tree](../Docs/Generators/SpanningTree.md) pages, with worked sketches in [`Examples/Patterns/Stippling`](../Examples/Patterns/Stippling/Sketch.swift), [`Examples/Images/SingleLine`](../Examples/Images/SingleLine/Sketch.swift), and [`Examples/Images/SpanningTree`](../Examples/Images/SpanningTree/Sketch.swift).

### A picture wound from thread: `StringArt`

String art rings the canvas with pins and winds one thread straight across, again and again. Nothing curves and nothing lifts, so the picture comes out of where the crossings pile up. It is for a picture you could wind on a hoop of nails, and the winding order comes with it. Petros Vrellis made it famous as a computational technique in 2016. Each chord is a greedy choice. From the pin the thread is on, `StringArt` winds the chord that still covers the most darkness, subtracts that ink from the picture, and goes again.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/09-Pictures/WoundFromThread-dark.jpg">
  <img src="Images/09-Pictures/WoundFromThread.jpg" alt="Three panels: a photograph of a woman in profile on a plain ground, the first 350 chords of its winding crowding into the dark of the head, and the finished winding where the profile is dense thread and the ground a light veil" width="680">
</picture>

```swift
let art = StringArt(of: picture, center: Vector2(540, 540), radius: 470)
override func setup() { noClear() }                // the chords accumulate
override func draw() {
    if frameCount == 1 { background(.white) }
    stroke(Color.black.withAlpha(0.35))
    for chord in art.step(8) { drawLine(chord.from, chord.to) }
}
```

Two calls in the listing are new. `noClear()` stops the canvas being wiped between frames, so each frame's chords stay and pile up. `withAlpha(0.35)` hands back the same color at 35% opacity. The `ink`, `pins`, and `minSpan` arguments, `thread` and `sequence`, and why bold masses wind better than a soft sky are on the [string art page](../Docs/Generators/StringArt.md), with the worked sketch in [`Examples/Images/StringArt`](../Examples/Images/StringArt/Sketch.swift).

## The picture's own pixels: sorting and a hidden shape

Dithering, glyphs, dots, stipple, and thread each answered a pixel with a mark of their own. Pixel sorting and the autostereogram keep the picture's own pixels. One rearranges them, and the other reads a depth map's pixels to hide a shape in a field of repeats. Neither is in the portrait. Both read pixels on the CPU, like the stipple and the thread above, so each one is `setup()` work. Run it once, hold the result, and let `draw()` replay it.

### Sorting the pixels

Pixel sorting rearranges the pixels a picture already has. It walks each row or column, finds runs of pixels whose brightness falls inside a band you choose, and sorts each run. It is the glitch look, a picture melting in streaks, and it comes from glitch art rather than illustration. It spread from a 2010 sketch by Kim Asendorf.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/09-Pictures/SortedPixels-dark.jpg">
  <img src="Images/09-Pictures/SortedPixels.jpg" alt="A photograph of a Guanajuato alley under a wide sky beside a version with its columns sorted: the clouds fall to the bottom of the sky in vertical streaks, the pastel walls pour downward, and the deepest doorways and the brightest clouds stay where they were" width="680">
</picture>

```swift
let melted = picture.pixelSorted(.vertical, threshold: 0.2 ... 0.75)
let glitched = picture.pixelSorted(.vertical).pixelSorted(.horizontal)
```

The threshold is the whole technique. It decides which pixels take part, and everything outside the band stays where it was. So the deepest doorways and the brightest clouds survive in the picture above while everything between them pours. Sort by `.brightness`, `.hue`, or `.saturation`, and `reversed` flips which end of the run the bright pixels pile up at.

Two notes. The look needs some texture in the source, because run boundaries have to vary from line to line, and a clean gradient sorts almost invisibly. And the direction matters against the picture's own gradient. The alley runs bright at the top and dark at the bottom. An ascending sort piles each run's dark pixels at its top, so it turns the picture inside out. On a picture that already runs dark to bright down the column, that same sort changes nearly nothing. There, `reversed: true` is the direction that changes the picture most.

### A picture that hides a shape

An autostereogram hides its picture instead of drawing it. It is a field of marks that repeats, with the repeat shortened wherever a shape is nearer. So two eyes looking through it see the shape standing out of the page. It is for the poster that holds a secret, and it needs a depth map rather than a photograph. Christopher Tyler and Maureen Clarke made the first single-image random-dot stereogram in 1990. They built on the random-dot stereograms Bela Julesz devised in 1959.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/09-Pictures/DepthInARepeat-dark.jpg">
  <img src="Images/09-Pictures/DepthInARepeat.jpg" alt="Two strips of scattered marks. The top one repeats at a fixed spacing, marked with a bracket underneath. The bottom one repeats at that spacing at its ends and at a shorter spacing through the middle, with both brackets marked and the shorter one in orange" width="680">
</picture>

A pattern that repeats at a fixed spacing gives both eyes the same marks to pair. The eyes read those marks at whatever depth that spacing stands for. **Shorten the repeat and the pair reads as nearer.** That one rule means a depth map can be turned into a picture. Shorten the repeat wherever the shape is closer.

```swift
if let hidden = depthMap.autostereogram(Autostereogram(repeatWidth: 120, relief: 0.22)) {
    drawImage(hidden, in: rect)
}
```

Hand it a picture where bright means near, and you get back a field of noise with a shape buried in it. When the map cannot be used, it hands back `nil`. Look *through* the picture, at something behind the screen, until the repeats double up. Crossing your eyes instead reads the same picture inside out, so the shape sinks rather than stands.

Four things decide whether one works, and only the first is code.

**Draw it at its own pixel size.** Scaling resamples the repeats the eyes have to pair, and a stereogram at half size cannot be fused. **Keep the relief under about a third** of the repeat, which is where the eyes give up. **Use hard edges**, because a soft gradient gives them nothing to lock onto. And expect a shimmer along every edge of the shape. Within one repeat of a depth step, neither depth is the answer. The shimmer comes from the technique rather than from the picture.

## Numbers you didn't type: CSV and JSON

Words and pictures are material you bring in, and numbers come the same way, read once in `setup()` and asked one row at a time. The portrait has no use for them, but a spreadsheet, a sensor log, and a public archive all export as one of two formats. Once a sketch reads such a file, the drawing changes when the file does and you never touch the sketch.

### Reading a table: `loadTable`

A comma-separated file is the format every spreadsheet exports, one row per line and one cell per comma. `loadTable` reads one, guesses the separator and whether the first row names the columns, and hands you each row's cells by name. A cell is text, so `row.number(_:)`, `row.int(_:)`, `row.bool(_:)`, and `row.color(_:)` convert it when you ask, and each answers `nil` for a gap, not a zero. The format's published description is RFC 4180 (Yakov Shafranovich, 2005), and the reader follows it, quoted cells included.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/09-Pictures/DataAsMaterial-dark.jpg">
  <img src="Images/09-Pictures/DataAsMaterial.jpg" alt="Left, five lines of a CSV file in a pixel font, the header and one quoted row picked out in dark ink. Right, the four data rows as colored horizontal bars labeled Oslo, Bath Maine, Kyoto, and Lima, each sized by its number" width="680">
</picture>

```swift
let table = try loadTable(resource: "visits", withExtension: "csv", in: .module)
for (index, row) in table.enumerated() {
    fill(row.color("tint") ?? .gray)
    drawRect(corner: Vector2(80, 100 + Double(index) * 60), width: row.number("visits") ?? 0, height: 22)
}
```

The [Data](../Docs/Helpers/Data.md#loadTable) page has the separator and header guesses, the quoting rules, and every read by row and column; [`Examples/Data/Readings`](../Examples/Data/Readings/Sketch.swift) reads a year from one.

### From numbers to marks

A file gives you rows and columns, and a drawing wants marks. Each mark asks which column, which of its properties, and over what range. Any property will do, because a length, a radius, a hue, and a turn are all numbers. The range should come from the file, through `numbers(_:)`, `min()`, `max()`, and `map` from [Chapter 3](03-MotionAndTime.md). The bar, the scatter, and the line are the charts a reader already knows, and each is one such answer.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/09-Pictures/MarksFromNumbers-dark.jpg">
  <img src="Images/09-Pictures/MarksFromNumbers.jpg" alt="One table of twelve monthly readings drawn three ways in three panels. Left, a bar per month for rain, tall in winter and short in summer. Middle, a dot per month placed by rain across and high temperature up, each dot labeled with its month, the summer months high on the left and the winter months low on the right. Right, one line through the months in order for the daily high, rising to a plateau in July and August and falling again." width="680">
</picture>

```swift
let rain = table.numbers("rain")
guard let most = rain.max() else { return }
for (index, row) in table.enumerated() {
    let height = map(row.number("rain") ?? 0, 0, most, 0, 250)
    drawRect(corner: Vector2(60 + Double(index) * 30, 300 - height), width: 20, height: height)
}
```

The [Data](../Docs/Helpers/Data.md#mapping) page has the range rule for each kind of mark, and [`Examples/Data/Readings`](../Examples/Data/Readings/Sketch.swift) draws a year from such a table.

### Documents with a shape: `loadJSON`

JSON is the format a web service answers in, nesting named values and lists to any depth rather than rows. `loadJSON` reads one and hands back a value you reach through by name or index. At the end of the path you ask for the kind you want: `.text`, `.number`, `.int`, `.bool`, `.color`, or `.array`. A key that is not there answers null rather than stopping, so a path of any length is safe to write in one line. A document you would rather decode into a type of your own is `Codable`'s job. `Codable` is Swift's built-in way of reading a file straight into a type you declare.

```swift
let doc = try? loadJSON(resource: "places", withExtension: "json", in: .module)
for point in doc?["points"].array ?? [] {
    fill(point["tint"].color ?? .gray)
    drawCircle(point["x"].number ?? 0, point["y"].number ?? 0, 20)
}
```

The [Data](../Docs/Helpers/Data.md#reaching) page has every kind you can ask for, the `Codable` route, and what a written null does; [`Examples/Data/Places`](../Examples/Data/Places/Sketch.swift) draws a JSON survey.

## Where this comes from

Turning a photograph into marks is older than the computer that does it now. Newspapers were printing halftones by the 1880s, rebuilding a photograph out of dots that vary in size. Each way this chapter turns a picture into marks descends from that one idea. In São Paulo in 1969, Waldemar Cordeiro and the physicist Giorgio Moscati turned a photograph of a young couple into line-printer characters. Then they printed its derivative. That is the glyph mosaic's own lineage and the source of the homages linked below. Seam carving is much younger. Shai Avidan and Ariel Shamir published it in 2007. Its demonstration video was watched around the world, mostly because of the part where a mask makes something disappear.

The families after the sketch name their own sources, from Secord's stipple to Asendorf's sorted pixels. Full credits are in the project's [attribution notes](../ATTRIBUTION.md).

## Go deeper

- [Images](../Docs/Drawing/Images.md): the complete `Image` surface, including `Image(resource:withExtension:in:)` for a picture bundled with a sketch, `resized` for a working copy, the sampling helpers, and authoring an image in code.
- [Sample photographs](../Docs/Drawing/SamplePhotos.md): all twenty bundled pictures, what each is good for, the credit each carries, and the terms they are used under.
- [Input](../Docs/Helpers/Input.md): the drop hook and the draining read beside the mouse and keyboard reads, and which host surfaces take a drop.
- [Glyph mosaic](../Docs/Drawing/GlyphMosaic.md) and [halftone](../Docs/Drawing/Halftone.md): the measured coverage behind the glyph ramp, the dot shapes and screen angles, and the `colored` form of each.
- [Photo mosaic](../Docs/Drawing/PhotoMosaic.md): `averageColor` and its linear-light rule, the match, the tint and repeat arguments, and drawing the placements yourself.
- [Autostereogram](../Docs/Drawing/Autostereogram.md): the repeat and relief settings, the pattern, and why a scaled one stops working.
- [Stippling](../Docs/Generators/Stippling.md), [single line](../Docs/Generators/SingleLine.md), and [spanning tree](../Docs/Generators/SpanningTree.md): every argument to the even scatter, the closed tour through it, and the branching tree over the same dots.
- [String art](../Docs/Generators/StringArt.md): the pins and the ink dial, and `inverted` for a pale thread on a dark ground.
- [Pixel sorting](../Docs/Drawing/PixelSorting.md): every key and direction, and how to get each of the classic looks.
- [Seam carving](../Docs/Drawing/SeamCarving.md): both energies, the two masks, growing rather than shrinking, and the `SeamMap` that hands back any width at once.
- [Data](../Docs/Helpers/Data.md): `loadTable` and `loadJSON` in full, including the separator and header guesses, the two ways a column reads back, and what a missing key does.
- Appendix B draws this chapter's math, one picture per idea: [Fractions, mapping, and wrapping](B-JustEnoughMath.md#sampling-one-grid-with-another), [Shaping a value](B-JustEnoughMath.md#reading-a-shaping-curve), [Color and light as numbers](B-JustEnoughMath.md#color-and-light-as-numbers).
- Worked examples: [`Examples/Images/GlyphMosaic`](../Examples/Images/GlyphMosaic/Sketch.swift), [`Halftone`](../Examples/Images/Halftone/Sketch.swift), [`PixelSort`](../Examples/Images/PixelSort/Sketch.swift), [`SingleLine`](../Examples/Images/SingleLine/Sketch.swift), [`SpanningTree`](../Examples/Images/SpanningTree/Sketch.swift), [`StringArt`](../Examples/Images/StringArt/Sketch.swift), [`SeamCarve`](../Examples/Images/SeamCarve/Sketch.swift), and [`PixelField`](../Examples/Images/PixelField/Sketch.swift) (authoring an image pixel by pixel and reading it back).
- Worked examples for data: [`Examples/Data/Readings`](../Examples/Data/Readings/Sketch.swift) (a CSV as a range chart) and [`Examples/Data/Places`](../Examples/Data/Places/Sketch.swift) (a JSON survey).
- The Cordeiro homages in [`Examples/Recreations/WaldemarCordeiro/`](../Examples/Recreations/WaldemarCordeiro/): a picture read into levels by arithmetic you can see. `Derivadas` averages each block with `averageColor(in:)` and cuts the tones into seven levels. It prints them as characters, then takes the difference between neighbors, which turns shading into contours. `Gente` multiplies the same kind of levels by a degree and holds them at black, so a crowd loses its middle tones sheet by sheet.

---

[Contents](README.md#contents) · Previous: [Chapter 8, Words](08-Words.md) · Next: [Chapter 10, Vectors, gently](10-Vectors.md)
