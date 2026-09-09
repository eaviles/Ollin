#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Drawing](./README.md) → `Sample photographs`</sup>

---

## Sample photographs

Nineteen pictures and one short film travel with Ollin so that an image technique, a filter, or a reader of any kind can be tried on something real before you have one of your own. Four are faces, four are whole figures, two are tables seen from above, four are streets, two are landscapes at dusk, one is a page with the light falling unevenly across it, and two are surfaces to wrap a form in. They live in their own library, `OllinSamplePhotos`, rather than in the framework, so an app that never imports it ships none of them.

```swift
import OllinSamplePhotos

final class Portrait: Sketch {
    var picture = Image(width: 1, height: 1)

    override func setup() {
        picture = SamplePhoto.portrait.load()
    }

    override func draw() {
        drawImage(picture, in: canvasRectangle, fit: .cover)
    }
}
```

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../Images/SamplePhotos-dark.jpg">
  <img src="../Images/SamplePhotos.jpg" alt="Nineteen pictures in five rows. First, four square faces: a young woman in a lace headdress, an elderly woman in a yellow scarf, a woman in profile against a plain tan ground, and a woman before a wall of orange marigolds. Then four whole figures: a dancer reaching up a concrete wall, a masked wrestler with both arms raised, a dancer on white, and a breakdancer upside down on one hand. Then two tables seen from above and two streets, a pastel alley and a street strung with papel picado. Then woven blankets, rooftops running to the hills, and two wide dusk landscapes, a headland over calm water and boats under a pink sky. Last, a book page with shadow across it, a panel of Mexican talavera tilework, and a dry-stone wall. Each is labeled with its name and its photographer" width="680">
</picture>

### Contents

- [The faces](#faces) - four squares, and what each is good for
- [The figures](#figures) - four whole bodies, and what each is good for
- [The tables](#tables) - two from above, for naming things and reading print
- [The streets](#streets) - four whole scenes, and what each is good for
- [The landscapes](#landscapes) - the two wide ones, and why they share a shape
- [The page](#page) - print under uneven light
- [The surfaces](#surfaces) - two textures, and why they are not 1600
- [The film](#film) - thirty seconds of motion, for what a still cannot show
- [SamplePhoto](#samplephoto) - `load`, `credit`, `all`
- [Working copies](#copies) - `resized(width:height:)`, `cropped(x:y:width:height:)`, `cropped(toAspect:)`
- [Terms](#terms) - the licenses the pictures are used under

<a name="faces"></a>

### The faces

Each is a 1600-pixel square, cropped from the original around its subject.

- **`.portrait`** is a young woman in a lace headdress and an embroidered blouse, smiling at the camera. The frontal face, and the widest tonal range, from bare paper to solid ink: what the face and eye trackers, the person matte, the mosaics, the halftone, and the filter catalog read best.
- **`.scarf`** is an elderly woman in a yellow scarf, looking straight at the camera. The face with the most in it, every line of it an edge: what the ink drawing and the dithers show best. Its tones sit in the middle, so a stipple of it comes out nearly even.
- **`.profile`** is a woman in profile against a plain tan ground. The silhouette, bold masses on nothing: what the stipple, the single line, the spanning tree, and the string art read best. The head sits left of center on purpose, the way a profile is framed, and the braid runs to the right edge.
- **`.marigolds`** is a woman before a wall of cempasúchil, the marigolds of Día de Muertos. The color and texture picture: what palette extraction, the color-vision simulation, the shock filter, and the frequency domain show best.

The examples in `Examples/Images`, `Examples/Color`, and `Examples/Effects` read them, and so do the Guide's ink, brushwork, shock, filter-sheet, thread, and photo-mosaic figures.

<a name="figures"></a>

### The figures

Each is 1600 pixels on its long side, framed so that no limb runs off the edge, which is what a body needs if its joints are to be read. Three stand upright, since a square would cut a raised arm or a foot off; the wrestler is square, his arena frame having had the room to crop that way.

- **`.reaching`** is a dancer reaching up the face of a concrete wall, whole body, feet on a paved floor. All nineteen joints read, so it is the straightforward one to start from.
- **`.wrestler`** is a masked luchador with both fists raised over a full arena. Both arms read, and so does the crowd behind him, which makes him a person and a scene at once. The mask leaves the face trackers nothing to find, which is the reason he sits here beside the faces.
- **`.dancer`** is a contemporary dancer on a white ground, one arm reaching up and a long black skirt around the legs. Nothing stands behind her, so she is the cleanest figure to matte.
- **`.handstand`** is a breakdancer upside down on one hand against a stone wall. The hard pose: a body the wrong way up, which the joint model reads as readily as any other, and a good check that a sketch never assumed the head is on top.

Every one of them was read by the joint model before it was bundled. Three give all nineteen joints; the wrestler gives seventeen, since his ankles are behind the ring rope.

<a name="tables"></a>

### The tables

Two squares, both shot from above, for the readers that want a scene rather than a person.

- **`.breakfast`** is an Oaxacan breakfast: plates, bowls, cups, cutlery, a napkin, glasses, a phone. The densest table here for anything that names things. The object detector finds five (two cups, two bowls, a sandwich), where a person in a scene gives it three.
- **`.desk`** is a laptop, earbuds, a plant, a watch, a cup of coffee, and a notebook whose cover is printed. It is the one with text, and the reason it is cropped in as far as it is: at the photograph's full width the recognizer read nothing, and cropped it reads five lines. The rectangle detector finds seven quadrilaterals in it.

Small print needs `TextRecognizer`'s `.accurate` quality rather than the `.fast` a live camera defaults to, and the first accurate pass on a Mac prepares the system's reader, which can take the better part of a minute before anything appears. After that it costs about 140 ms a frame here.

<a name="streets"></a>

### The streets

Four squares, each the largest square its original held, so two of the photographer's own edges are kept. They are for everything that wants a whole scene rather than one subject.

- **`.alley`** is a Guanajuato alley of pastel walls under a wide cloudy sky. Half the frame is sky, which is the low-detail region a seam carver eats first and the band a pixel sorter pours. The walls are flat planes with hard vertical edges between them. Its spectrum is the most directional of the four, a star of rays, one per run of parallel edges.
- **`.street`** is a San Miguel de Allende street under strings of papel picado, with people, a car, and a dog in it. The busy one: fine detail everywhere and no large plain region, so nothing in it is cheap to throw away.
- **`.textiles`** is woven blankets hung side by side at Teotitlán del Valle. Pattern at a scale the eye can follow, and a dozen saturated colors, which makes it the one to point a frequency transform at. It is also the one where red sits next to green oftenest, so it is what a color-vision simulation collapses hardest.
- **`.city`** is Guanajuato seen along a street, rooftops running back to the hills under a warm sky. Depth without a subject: mostly middle distance, which is the awkward case for anything that wants a foreground. A round dome sits in the middle of it, and a round shape is the fastest way to see a picture stretched.

<a name="landscapes"></a>

### The landscapes

Two at dusk, and the only wide pictures here. Everything else is a square or an upright, so a sketch that wants a landscape has to crop one and throw away the frame the photographer chose. These two are three to two, and they are the same shape as each other on purpose: either one drops into the same box, the way any face drops into a square.

- **`.headland`** is a headland at dusk over the water at Loreto, with cardón cacti in silhouette along a dark shore. One hard dark mass and one smooth wide gradient in the same frame, which is the pairing a threshold, an edge finder, or a tone curve reads clearest. It is the only silhouette in the set.
- **`.boats`** is small boats moored off Cozumel under a pink sky, turquoise water below a dead straight horizon. The calm one. Almost none of it is near black and it varies far more in color than in brightness, which is what gradient-domain compositing wants under a patch, and the water is the widest plain band in the whole set.

The `boats` frame is the one thing here chosen by a filter's own requirement rather than by eye. A seamless clone measures its correction around the patch's rim and spreads it inward, so a rim laid across a hard edge drags that edge into the patch. This picture keeps its brightness in a narrow band while its color runs from grey-violet to pink, which is exactly the ground a clone wants.

<a name="page"></a>

### The page

- **`.page`** is a book held open with dappled shadow falling across the right half of it, the type large and crisp underneath. It is here for the case adaptive thresholding exists for: one number for the whole page loses entire bands of the text to black, and reading each pixel against its own neighborhood brings all of it back. The recognizer also takes sixty lines off it at 0.91 confidence, more than anything else here, and it does that straight through the shadow, which is worth knowing before you reach for a threshold to help it.

<a name="surfaces"></a>

### The surfaces

Two textures rather than two pictures, and they are sized as textures: 1024-pixel squares rather than 1600 on the long side. A texture is magnified on a surface and repeated, so it wants clean pixels at a size a GPU mips evenly, and at 1600 neither of these fits the size budget without artifacts a magnified surface would show.

- **`.talavera`** is Mexican tilework, straight on and evenly lit, and it is the one bundled picture that **repeats seamlessly**: the frame is cut to two whole periods of the motif, so laying it edge to edge leaves no join. That matters for a triplanar projection, which tiles whatever it is given whatever the wrap setting says, so a picture that does not join up shows its own grid. The relief in it is painted rather than moulded, so a normal map taken off its light and shade embosses the design.
- **`.stone`** is a dry-stone wall close up under an even sky. The relief one: deep mortar gaps and faceted faces give a height or normal map something to bite on, and it is nearly colorless, so it reads as material rather than as a picture of a thing. Its own brightness is a height map with no work at all, which is what the parallax study reads it as. It does not repeat, so a surface that tiles it wants mirror wrapping or a projection that covers the form once.

<a name="film"></a>

### The film

Some techniques need motion and a still cannot stand in for it: optical flow measures what moved between two frames, a contour tracer is only interesting when the outline changes, and a skeleton or a matte is worth watching rather than looking at. One film ships for those.

- **`SampleClip.dance`** is a man dancing on a plain studio ground, thirty seconds at 960 square and 25 frames a second, 1.5 MB, no sound. The camera is locked off, which is the property that matters: nearly two thirds of the frame never changes, so every vector optical flow reports belongs to the dancer rather than to a moving lens. The body model finds all nineteen joints in every frame sampled across the whole run.

It is vended as a URL rather than as a player, because opening a film belongs to `OllinVideo` and no satellite depends on another:

```swift
let film = VideoPlayer(url: SampleClip.dance.url)
film.loops = true
film.play()
```

A `VideoPlayer` is both a `FrameSource` and a `VideoFeed`, so it goes wherever a camera goes and every tracker reads it unchanged. That is how `Examples/Vision/OpticalFlow` and `Examples/Vision/ContourTrace` run on a Mac with no camera, and `--photo` takes the film even where a camera would have worked.

<a name="samplephoto"></a>

### SamplePhoto

```swift
struct SamplePhoto {
    let name: String            // the file name inside the bundle
    let subject: String         // a few words on what it shows
    let credit: Credit
    func load() -> Image
    static let portrait, scarf, profile, marigolds: SamplePhoto
    static let reaching, wrestler, dancer, handstand: SamplePhoto
    static let breakfast, desk: SamplePhoto
    static let alley, street, textiles, city: SamplePhoto
    static let headland, boats: SamplePhoto
    static let page, talavera, stone: SamplePhoto
    static let all: [SamplePhoto]
}

struct SamplePhoto.Credit {
    let photographer: String
    let place: String
    let source: String          // the page the photograph came from
    let license: String
    let licenseURL: String
    var line: String            // "Photograph by …, … (… License)"
}
```

`load()` decodes the picture through the library's own bundle, so there is no `in:` to pass. Decoding happens on every call, so keep the result in a property rather than calling it from `draw()`.

`credit` is the photographer, the place, the page the picture came from, and the license, carried in code so a sketch can draw the line the photographer is owed:

```swift
drawText(SamplePhoto.scarf.credit.line, 24, height - 24)
// Photograph by Matthew Stephenson, Oaxaca, Mexico (Unsplash License)
```

`all` lists all nineteen: the faces, the figures, the tables, the streets, the landscapes, the page, then the two surfaces.

<a name="copies"></a>

### Working copies

A 1600-pixel square is more than most CPU techniques want. A stipple, a dither, a mosaic, or a string-art winding reads every pixel, and a copy of a few hundred pixels a side is what they were tuned on. [`resized(width:height:)`](./Images.md#image) makes that copy:

```swift
let small = SamplePhoto.profile.load().resized(width: 340, height: 340)
let line = singleLine(of: small, points: 3600, in: canvasRectangle.inset(by: 96))
```

[`cropped(x:y:width:height:)`](./Images.md#image) takes a piece out instead of scaling the whole, and [`cropped(toAspect:)`](./Images.md#image) takes the largest centered piece of a given shape, which is how a square photograph stands in for a wide one:

```swift
let wide = SamplePhoto.city.load().cropped(toAspect: 3.0 / 2)
```

A filter that runs on the GPU reads the full picture as it is: draw it into a layer with `fit: .cover` and filter the layer.

<a name="terms"></a>

### Terms

The scarf, the profile, the desk, the textiles, the city, and the boats come from Unsplash under the [Unsplash License](https://unsplash.com/license); the other thirteen photographs and the film come from Pexels under the [Pexels License](https://www.pexels.com/license/). Both allow free use, commercial use included, and modification, and neither requires attribution, which is given all the same. Both forbid selling unaltered copies and compiling the pictures into a competing stock service, and the Pexels License adds that an identifiable person may not be shown in a bad light or as endorsing anything. The photographs are credited in [`THIRD-PARTY-NOTICES.md`](../../THIRD-PARTY-NOTICES.md), with what was changed: each was resized, converted to sRGB, and re-encoded with its metadata removed, the faces, the tables, and the streets cropped square, two of the figures cropped in, and the headland trimmed from four to three down to three to two by dropping its darkest foreground. The page keeps its whole frame. The talavera is cut to two whole periods of its motif so that it repeats without a join, and the stone to a square; both are 1024 rather than 1600, since they are textures. The film was cut to its first thirty seconds and to a square, the window and the crop chosen together because the dancer leaves a square frame later in the original and never once inside that window; it was scaled to 960, its sound removed, and re-encoded. The desk photograph carries a notebook whose printed cover names its maker, which the text recognizer reads aloud; that is incidental to a photograph of a desk rather than an endorsement. The licenses ride on the photographs, not on Ollin's code, which stays MIT.

---

Example sketches: every sketch in [`Examples/Images`](../../Examples/Images/README.md), plus [`Examples/Color/ColorVision`](../../Examples/Color/ColorVision/Sketch.swift), [`Examples/Color/Dithering`](../../Examples/Color/Dithering/Sketch.swift), [`Examples/Color/PaletteFromImage`](../../Examples/Color/PaletteFromImage/Sketch.swift), [`Examples/Effects/InkDrawing`](../../Examples/Effects/InkDrawing/Sketch.swift), [`Examples/Effects/Brushwork`](../../Examples/Effects/Brushwork/Sketch.swift), [`Examples/Effects/Coherence`](../../Examples/Effects/Coherence/Sketch.swift), [`Examples/Effects/FilterCatalog`](../../Examples/Effects/FilterCatalog/Sketch.swift), [`Examples/Effects/Fourier`](../../Examples/Effects/Fourier/Sketch.swift), and [`Examples/Effects/SeamlessClone`](../../Examples/Effects/SeamlessClone/Sketch.swift), [`Examples/3D/Materials/Triplanar`](../../Examples/3D/Materials/Triplanar/Sketch.swift), and [`Examples/3D/Materials/Parallax`](../../Examples/3D/Materials/Parallax/Sketch.swift). For the figures, see [body pose](../Vision/Vision.md).
