#### <sup>[Ollin](../README.md) → [Guide](README.md) → Chapter 20</sup>

---

# 20. Pictures restyled

<img src="Images/20-PicturesRestyled/HandColored.jpg" alt="A street of colonial facades under a warm sky made into a hand-colored print: flat painted color under dark hatched line work, graded warm, grained like film, and pressed into paper" width="560">

One photograph can become a painting, a pen drawing, a colorist's grade, or a print on paper. You learn the filters that do it. Each is one call on a layer, so they chain and take arguments. Five of them, stacked, turn the street photograph above into a hand-colored print. Two more of the stylize shelf follow it, a pen line and flat regions. Filters that stand in for a physical thing, such as chrome, a lens, or tape, are in [Chapter 21](21-GlassChromeAndTape.md).

## Paint that follows the picture: brushwork

The first filter turns the layer into a painting. `.brushwork()` lays the picture on as paint. Detail flattens into patches, edges stay crisp, and the patches run along the picture's own contours.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/20-PicturesRestyled/Brushwork-dark.jpg">
  <img src="Images/20-PicturesRestyled/Brushwork.jpg" alt="Two panels: a photograph of a woman before a wall of marigolds, and the same layer painted as brushwork, each flower flattened into a dab that follows its own edges and the skin into soft patches" width="680">
</picture>

Draw the photograph into a layer, `scene`, the way [Chapter 19](19-LayersAndEffects.md) drew into `art`, and filter it:

```swift
drawImage(scene.filtered(.brushwork()).image, 0, 0)
```

Underneath is a brush divided into eight overlapping sectors, like slices of a pie. For each pixel the filter takes the average color of every sector and measures how much each one varies. The flattest sectors win. So a pixel beside an edge takes its color from the sectors on its own side, and the edge never smears. Away from any edge every sector is much the same, and the pixel becomes a broad average. That is what flattens detail into patches.

The part that makes the patches read as strokes is the shape of the brush. For that, the filter first works out which way the picture runs at each pixel. It measures how the brightness changes in every direction around the pixel and keeps the direction along which it changes least. That direction is the picture's **flow**. Along a blade of grass the flow runs along the blade, and in a flat sky there is no clear flow at all. The table of changes the flow is read from is called the structure tensor, a term you will meet in the papers. Where the flow is clear, the brush is drawn out along it and squeezed across it. It is at most four times as long as it is wide. Along the blade the patch is a stroke along the blade. In the sky the brush stays round. `stretch`, an argument of `.brushwork`, is the most an edge can draw the brush out. Set it to 1 and the brush is always round, which is a useful thing to see once: the picture turns into square dabs.

Three more filters in this chapter read the same flow: hatching, next, and the ink lines and flat regions after the print. `radius` and `sharpness` are the other two dials, and the [effects reference](../Docs/Drawing/Effects.md#filter) describes all three. [`Examples/Effects/Brushwork`](../Examples/Effects/Brushwork/Sketch.swift) paints the photograph of a woman before a wall of marigolds, with every dial on a parameter.

## Strokes that follow the picture: hatching

Brushwork gave the picture its color as paint. The print also needs its line, and the same flow can draw that. `.hatching()` lays strokes along the flow, and lays down as many of them as the tone is dark. So the drawing keeps its light and shade with nothing but line.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/20-PicturesRestyled/Hatched-dark.jpg">
  <img src="Images/20-PicturesRestyled/Hatched.jpg" alt="Three panels: a sphere and a pot on a table drawn in smooth gray, the same layer hatched one way with the strokes ringing the sphere and running down the pot, and the same crossed by a second direction in the darkest places" width="680">
</picture>

```swift
drawImage(scene.filtered(.hatching()).image, 0, 0)
```

Look at where the marks go. They ring the sphere, because every ring of equal light on a sphere is a circle. They run down the pot, because its light changes across it and not along it. They lie flat on the wall and the table. Nothing told them to. The direction comes out of the picture, the way it did for `brushwork`.

The tone is the other half. Under the strokes is a stroke texture, made by combing noise along the flow. The filter inks every mark of that texture that is darker than the pixel under it. Because the texture is even, the share of paper the ink covers comes out as the share the picture is dark. A quarter-dark tone gets a quarter of the page. A picture with light and shade in it arrives with light and shade in the line work.

`spacing`, `length`, and `directions` are the dials, and a transparent `background:` argument leaves the page bare where the picture was empty. The [effects reference](../Docs/Drawing/Effects.md#filter) describes each. [`Examples/Effects/Hatching`](../Examples/Effects/Hatching/Sketch.swift) puts every one on a parameter over an engraved landscape with the sun crossing it.

## A look from a colorist's suite: ColorLUT

Brushwork and hatching change what the picture is made of. A print shop's next step changes its color. The tool for that is a **look**, a table that says, for every color, which color to show instead. Color tools trade them as `.cube` files. A colorist builds one in a grading suite and hands it over. A film stock's character ships as one, and a camera maker publishes one for its footage. Ollin reads that file into a `ColorLUT`, and `.lut` applies it to a layer or to the whole frame.

<img src="Images/20-PicturesRestyled/Look.jpg" alt="Two panels and two strips: a portrait of a young woman in a lace headdress plain on the left and through a warm print look on the right, her skin warmer and the shadows cooler; below them a gray ramp and a sweep of hues, each drawn plain above and through the same look beneath, the ramp's black lifted and its white held short of paper, the hues mostly held, with cyan turned toward teal" width="680">

```swift
var look = ColorLUT.warmPrint                       // the bundled look, a warm print

override func setup() throws {
    look = try ColorLUT(resource: "kodachrome", withExtension: "cube", in: .module)
}

override func draw() {
    drawImage(photo, 0, 0)
    postProcess(.lut(look, amount: 0.8))
}
```

Read the two strips before the portrait. The gray ramp says what the look does to tone. This one lifts black off the floor, holds white short of paper, and bends the middle into a gentle S. It also tints the ramp, warm at the bright end and cool at the dark. The sweep of hues says what the look does to each hue. This one mostly leaves them in place and turns cyan toward teal. Every look is those two things, and a ramp and a sweep through it tell you more than a portrait does.

A word on how the table is read, because it decides whether a neutral stays neutral. A `.cube` holds a color at every node of a lattice. An input between nodes has to be interpolated from the corners of its cell. Ollin cuts the cell into six tetrahedra along its gray diagonal, the way a grading suite does. It then weighs the four corners of the one that holds the point. Every one of those tetrahedra has the cell's black and white corners. So a gray input meets only the two gray corners, and a look that leaves gray alone does so between its nodes too. A plain GPU read between the nodes blends all eight corners of the cell at once, which is called a trilinear read. That would mix the colored corners in and tint a neutral.

Two more things to know. A file that is not a `.cube` is refused with the line that stopped it, so a bad download says where. And the table runs the other way as well. `ColorLUT(size:title:_:)` builds a cube from a function of color, and `write(to:)` saves it as a `.cube` that any grading tool reads. So a look you tune in a sketch can travel out. [`Examples/Color/Look`](../Examples/Color/Look/Sketch.swift) wipes the bundled look across a portrait, beside one written in code, and takes any `.cube` dropped on the window.

## A film look: halation and grain

A look grades the color. Two more filters give a frame the *texture* of film, the two things a stock does to a picture that a sensor does not.

<img src="Images/20-PicturesRestyled/FilmLook.jpg" alt="Two panels and two strips: a night street of lamps over dark facades drawn plain on the left and through halation and film grain on the right, each lamp with a warm ring and the walls carrying a fine grain; below them one lamp magnified four times, plain and halated, its white core unchanged and a deep red fringe around it, and a gray ramp drawn plain above and grained beneath, the grain absent at both ends and heaviest in the middle" width="680">

The first is **halation**, the warm fringe film shows around its brightest highlights. Light that gets through the emulsion reflects off the base and exposes the layers again around the point it entered. The red-sensitive layer sits deepest, so it takes most of that second exposure, and the fringe comes out red. `.halation(threshold:radius:tint:amount:)` builds it the way `.bloom` builds a glow. The pixels above `threshold` are blurred by `radius`, colored by `tint`, and added back. The difference is where the halo lands. Scattered light changes nothing in a layer that is already fully exposed. So each channel takes the halo in proportion to how far it sits below white. A white lamp keeps its white core and gains a ring, where a glow would have tinted the core too. Under the pictures, the same lamp is magnified four times, plain and halated, so you can see the core hold. A frame with nothing above the threshold comes back untouched, byte for byte.

The second is **film grain**. A developed frame is a scatter of grains, each one developed or not, and that is what makes its noise follow the tone. Where nothing developed there is nothing to vary, and where every grain did there is nothing either. The grain lives in the middle, and its spread goes as the square root of the tone times what is left to white. `.filmGrain(amount:size:seed:)` applies that rule to each channel on the displayed picture. `amount` is the spread at mid-gray as a fraction of the way to white. A screen shows 256 levels from black to white, so 0.05 is about twelve of them. `size` is how many pixels across a clump is, and a coarser grain is not a fainter one. The mean of any flat region is kept, so grain never lifts or darkens a picture. The ramp along the bottom shows the rule: nothing at the black end, nothing at white, the most in the middle. Feed `seed` your `frameCount` and every frame gets the fresh grain a film has. The older `.grain` is plain per-pixel noise, the same at every tone. It is still the right call for a static or a signal look.

```swift
override func draw() {
    background(.black)
    fill(.white)
    drawCircle(width / 2, height / 2, 40)
    postProcess(.halation(threshold: 0.8, radius: 24))
    postProcess(.filmGrain(amount: 0.06, size: 2, seed: Double(frameCount)))
}
```

[`Examples/Effects/FilmLook`](../Examples/Effects/FilmLook/Sketch.swift) draws a night street of lamps through both. Every dial is a parameter, and a switch shows the raw frame on the left half.

## The sheet it is printed on: paper, glass, and water

The last thing a print meets is the sheet it is printed on. `.paperTexture` lays a picture onto a sheet of paper with tooth and creases. It belongs to the design filters, which are built to look like the finished graphics on a product page. Two of its neighbors put something else in front of a picture. `.flutedGlass` sets ribbed glass in front of it, and `.water` refracts it through ripples:

<img src="Images/20-PicturesRestyled/PaperGlassWater.jpg" alt="Three tiles of the same photograph of a hillside town: behind angled glass flutes, refracted through rippling water, and pressed into a crumpled paper sheet" width="680">

```swift
drawImage(scene.filtered(.paperTexture(folds: 0.4)).image, 0, 0)
```

`folds` is how deeply the sheet is creased, and `contrast` and `crumples` set how strongly its tooth and its smaller wrinkles show. The paper lights its own creases from one side, so a flat photograph comes back looking pressed into a real sheet.

One practical note for the glass and the water. A strong distortion reads past the layer's edge, and `edges` decides what happens there. On `.flutedGlass` it softens the samples pushed off the layer, and on `.water` it lets the distortion reach the borders. The other half of the design filters builds a whole material from a shape's outline instead. [Chapter 21](21-GlassChromeAndTape.md#a-material-from-a-silhouette-liquidmetal-heatmap-and-gemsmoke) starts there. [`Examples/Effects/FilterCatalog`](../Examples/Effects/FilterCatalog/Sketch.swift) tours the design filters in full.

## Putting it together: the hand-colored print

The hand-colored print turns a photograph into the kind of picture a print shop once sold, an engraving tinted by hand. It stacks five of this chapter's steps. `brushwork` paints the color, and `hatching` draws the line work over it under [Chapter 19](19-LayersAndEffects.md)'s `.multiply`. Then a look grades the frame warm, film grain gives it a texture, and `paperTexture` presses it into a sheet. Make `MySketches/HandColored.swift`:

```swift
import Ollin
import OllinSamplePhotos

final class HandColored: Sketch {
    var photo = Image(width: 1, height: 1)

    override func setup() {
        photo = SamplePhoto.city.load()
    }

    override func draw() {
        // The view drifts across the photograph, which is drawn a little wider
        // than the canvas so the drift never shows an edge.
        let drift = Vector2(sin(time * 0.07) * 40, cos(time * 0.05) * 20)
        let scene = makeRenderTarget()
        withTarget(scene) {
            drawImage(photo, in: Rectangle(center: center + drift, width: width * 1.1,
                                           height: height * 1.1), fit: .cover)
        }

        // The color, painted: detail flattened into patches along the picture.
        drawImage(scene.filtered(.brushwork(radius: 7)).image, 0, 0)

        // The line work, multiplied over the color, so its white paper drops out.
        blendMode(.multiply)
        drawImage(scene.filtered(.hatching(spacing: 4, length: 20,
                                           foreground: Color(hex: 0x3B2A20))).image, 0, 0)
        blendMode(.normal)

        // The finish: a warm grade, the grain of film, and the sheet it is printed on.
        postProcess(.lut(.warmPrint, amount: 0.85))
        postProcess(.filmGrain(amount: 0.04, size: 2, seed: Double(frameCount)))
        postProcess(.paperTexture(folds: 0.4))
    }
}
```

The photograph is one of the bundled sample photographs from [Chapter 9](09-Pictures.md), a hillside town under a warm sky. `try loadImage("/path/to/yours.jpg")` in its place, as [Chapter 9](09-Pictures.md) wrote it, is the whole change for a picture of your own.

One layer feeds everything. The photograph is drawn into `scene` once a frame, and both the color and the line are read from it. `brushwork` flattens the detail into patches that follow the picture's own contours, so the color stays inside the shapes rather than running across them. `hatching` reads the same picture and lays as many strokes as each tone is dark.

The line work goes down under `.multiply`. Multiplying by white changes nothing, so the paper between the strokes drops out and only the brown ink darkens the color under it.

The rest runs on the whole frame through `postProcess`, and each call works on what the calls before it left. The look grades first, and the grain lands on the graded color. The paper comes last, since the sheet is the last thing a print meets.

The frame moves because the view does. `drift` slides the photograph a little each second, and both filters read it afresh every frame. So the strokes re-flow as the picture passes under them, and the grain changes with `frameCount`. The paper holds still, since its texture is static by design.

> **Swift note.** `var photo = Image(width: 1, height: 1)` gives the property a one-pixel placeholder until `setup()` loads the photograph, which is the plain alternative to [Chapter 12](12-FlocksAndSwarms.md)'s `!`. `Rectangle(center:width:height:)` is [Chapter 13](13-GrowingThings.md)'s rectangle placed by its middle, and `center + drift` is [Chapter 10](10-Vectors.md)'s vector addition.

Then make it yours:

- Trade the colorist for a poster printer. `.shock(iterations: 6)`, from the family after this section, in place of `brushwork` flattens the color into bands with crisp edges.
- Ink it instead of hatching it. `.xdog()`, from the same family, in place of `hatching` gives pen lines and solid shadows, and they multiply over the color the same way.
- Grade it with a look of your own. Load a `.cube` file in `setup()` with `ColorLUT(resource:withExtension:in:)`, as the look step did, and hand it to `.lut` in place of `.warmPrint`.

A print is a still, so keep it as one. `swift run OllinLive MySketches/HandColored.swift --export print.png --frame 600` writes the frame ten seconds in. The grain is new on every frame, so try a few frame numbers and keep the one you like.

## More from the shelf: ink lines and flat regions

The print painted its color with brushwork and drew its line with hatching. Both belong to the stylize family, the filters that turn a picture into a drawing or a painting. Two more of that family belong here, and both read the same flow as brushwork. `xdog` draws the picture as pen and ink, and `shock` flattens it into regions with crisp edges. Either can stand in for a step of the print.

### A line where there is an edge: xdog

`.xdog()` draws the layer as pen and ink. A line goes wherever the picture has an edge, solid ink goes where the picture is dark, and everything else is left as paper. It is for a drawing rather than an adjustment, a photograph turned into the kind of line an illustrator would ink. The method is the extended difference of Gaussians that Holger Winnemöller, Jan Eric Kyprianidis, and Sven C. Olsen published in 2012.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/20-PicturesRestyled/InkLines-dark.jpg">
  <img src="Images/20-PicturesRestyled/InkLines.jpg" alt="Two panels: a photograph of an elderly woman in a yellow scarf, and the same layer drawn as pen and ink, with lines along the folds of the scarf and the features of the face, and soft gray where the background is dark" width="680">
</picture>

```swift
drawImage(scene.filtered(.xdog()).image, 0, 0)
```

Underneath is a difference of two blurs. Blur the brightness a little, then blur it a little more. The two agree everywhere except at an edge, where the wider blur reaches across and the narrower one does not. Subtracting them leaves the edges. The filter pushes that difference hard over the picture's own tone, then cuts the result at a threshold: paper above it, ink below. The cut is what puts solid ink into the shadows. A dark region sits under the threshold on its own, with no edge needed.

The part that makes the lines read as drawn rather than detected is the flow. It is the same idea brushwork used, read here from the brightness rather than the color. Before the blur is taken, the filter works out which way each edge runs. It then takes the blur *across* that direction and gathers the response *along* it. A line then runs the length of its edge instead of breaking into the speckle a plain edge detector leaves on a noisy picture. `flow` is how far along the edge it gathers. Setting it to 0 turns that off, so do it once to see what it does.

`radius`, `sharpening`, `threshold`, `softness`, `foreground`, and `background` are the other dials, and the [effects reference](../Docs/Drawing/Effects.md#filter) describes each. [`Examples/Effects/InkDrawing`](../Examples/Effects/InkDrawing/Sketch.swift) puts every one on a parameter over the photograph of the woman in the yellow scarf.

### Regions with crisp edges: shock

`.shock()` smooths the layer along its own flow and sharpens it across that flow, round after round. Soft shading snaps into flat regions with crisp edges. Anything that runs in a direction, grain, hair, or grass, is drawn out into one coherent stroke. It is for a poster or a cel look, a picture reduced to a few flat shapes without losing where its edges were. The method is the coherence-enhancing filtering that Jan Eric Kyprianidis and Henry Kang published in 2011.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/20-PicturesRestyled/FlatRegions-dark.jpg">
  <img src="Images/20-PicturesRestyled/FlatRegions.jpg" alt="Two panels: a photograph of a young woman in a lace headdress, and the same layer through the shock filter, the shading of her face snapped into flat bands with crisp edges and the lace drawn out into smooth strokes" width="680">
</picture>

```swift
drawImage(scene.filtered(.shock()).image, 0, 0)
```

Underneath are two moves, repeated. The first is the flow. At every pixel the filter takes the direction along which the picture changes least, the flow brushwork read. It averages the pixel with its neighbors along that direction only. It walks a curve that follows the picture rather than a straight line. Grain smooths along the grain and an edge along the edge. Nothing is smoothed across.

The second move is the shock. Across that direction the filter reads whether the brightness is bending toward bright or toward dark. On the bright side of a soft edge, each pixel takes the brightest pixel within reach. On the dark side, it takes the darkest. The two sides march toward each other and meet at a step. That is what turns a soft shadow into a flat band with a crisp edge. It is also why the filter never invents a color. Every pixel is either a blend along its own contour or a pixel the layer already had.

`iterations` is how many times the pair runs, and so the level of abstraction, and `flow`, `radius`, `smoothing`, and `threshold` are the other dials. The [effects reference](../Docs/Drawing/Effects.md#filter) describes each, with `smoothing` as the one to raise on a noisy picture. [`Examples/Effects/Coherence`](../Examples/Effects/Coherence/Sketch.swift) puts every one on a parameter over the lace-headdress portrait.

## Where this comes from

The stylizing filters each rebuild a published method. The brushwork is the anisotropic Kuwahara filter of Jan Eric Kyprianidis, Henry Kang, and Jürgen Döllner, from 2009. The hatching walks its strokes by Brian Cabral and Leith Casey Leedom's line integral convolution, from 1993. Its tone follows Georges Winkenbach and David H. Salesin's stroke-density rule, from 1994. The film grain is the stochastic model of Alasdair Newson, Julie Delon, and Bruno Galerne, from 2017. Halation is written from the photographic physics in T. H. James's *The Theory of the Photographic Process*. In the film it describes, the red-sensitive layer lies nearest the base.

A look is read from Adobe's Cube LUT format. The tetrahedral read between its nodes goes back to a 1981 patent by Sakamoto and Itooka. The design filters were cross-read against Paper Shaders, the design-shader library from paper.design with shaders by Ksenia Kondrashova. The fluted glass follows its published parameterization closely, re-expressed in Ollin's own Metal. The paper texture is Jim Blinn's bump lighting over a height field of noise.

The entries after the print name their own sources. The ink line is the extended difference of Gaussians of Holger Winnemöller, Jan Eric Kyprianidis, and Sven C. Olsen, from 2012. The flat regions are Kyprianidis and Kang's coherence-enhancing filter, from 2011. Full credits are in the project's [attribution notes](../ATTRIBUTION.md).

## Go deeper

- [Layered effects](../Docs/Drawing/Effects.md#filter): the whole filter catalog with every argument, the stylizing, look, film, and design filters among it.
- [Looks](../Docs/Drawing/Looks.md): the `.cube` format in both forms, the reader's refusals, the tetrahedral read, and writing a look of your own.
- [Sample photographs](../Docs/Drawing/SamplePhotos.md): the bundled pictures the chapter's figures and its print start from, and what each one is good for.
- Worked examples: [`Examples/Effects/InkDrawing`](../Examples/Effects/InkDrawing/Sketch.swift) (the scarf photograph as pen and ink), [`Examples/Effects/Brushwork`](../Examples/Effects/Brushwork/Sketch.swift) (the marigolds photograph painted as brushwork, every dial on a parameter), [`Examples/Effects/Coherence`](../Examples/Effects/Coherence/Sketch.swift) (the portrait flattened into regions by the shock filter), [`Examples/Effects/Hatching`](../Examples/Effects/Hatching/Sketch.swift) (an engraved landscape with the sun crossing it), [`Examples/Color/Look`](../Examples/Color/Look/Sketch.swift) (a look from a `.cube` file wiped across a portrait), [`Examples/Effects/FilmLook`](../Examples/Effects/FilmLook/Sketch.swift) (a night street through halation and grain), and [`Examples/Effects/FilterCatalog`](../Examples/Effects/FilterCatalog/Sketch.swift).

---

[Contents](README.md#contents) · Previous: [Chapter 19, Layers and effects](19-LayersAndEffects.md) · Next: [Chapter 21, Glass, chrome, and tape](21-GlassChromeAndTape.md)
