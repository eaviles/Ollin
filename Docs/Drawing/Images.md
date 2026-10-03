#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Drawing](./README.md) → `Images`</sup>

---

## Images

Load a raster image and draw it onto the canvas. An image decodes once on the CPU, then uploads to the GPU the first time it is drawn. Ollin reads the formats Apple reads through ImageIO, including PNG, JPEG, HEIC, TIFF, and GIF. After the upload the image is a textured quad like any other shape. It follows the [transform stack](../Drawing/Drawing.md#translate) and composites in draw order with the rest of your drawing.

The usual pattern is to load the image in `setup()`, keep the result in a property, and draw it in `draw()`. Do it that way because decoding a file every frame is wasteful. The image keeps its GPU texture for as long as you hold it, so one load is enough.

```swift
final class Photo: Sketch {
    var photo: Image?

    override func setup() {
        photo = try? loadImage("/path/to/photo.jpg")
    }

    override func draw() {
        background(.black)
        if let photo {
            drawImage(photo, 0, 0, width, height)   // fill the canvas
        }
    }
}
```

### Contents

- [loadImage](#loadimage) - load from a path or URL
- [drawImage](#drawimage) - draw at native size, scaled, or into a rectangle
- [Fitting a picture to a box](#fit) - `.stretch`, `.contain`, `.cover`
- [Part of a picture](#part) - one cell of a sprite sheet, a tile, or a frame of a strip
- [tint](#tint) - recolor and fade images as you draw them
- [Image](#image) - the value type, loading from data or a bundle, `resized`, and `cropped`
- [Pixels](#pixels) - author or sample an image pixel by pixel

<a name="loadimage"></a>

### loadImage

```swift
loadImage(_ path: String) throws -> Image
loadImage(_ url: URL) throws -> Image
```

Decode an image file. The call throws a [`FileError`](../Core/Sketch.md#fileerror) when the file is not there (`missing`) or is not a picture (`unreadable`). Call it in `setup()`: `try!` stops the sketch naming the file and the reason, and `try?` carries on with `nil`.

```swift
photo = try? loadImage("/Users/me/Pictures/leaf.png")
```

`loadImage` is a shorthand for [`Image(contentsOf:)`](#image). Use the initializer directly when you have a `URL`, raw `Data`, or a bundled resource.

<a name="drawimage"></a>

### drawImage

```swift
drawImage(_ image: Image, _ x: Double, _ y: Double)
drawImage(_ image: Image, corner: Vector2)
drawImage(_ image: Image, _ x: Double, _ y: Double, _ width: Double, _ height: Double)
drawImage(_ image: Image, in rect: Rectangle)
```

Draw `image` with its top-left corner at `(x, y)`. You can also pass a `Vector2` you already hold as `corner:`, the same anchor label `drawRect` uses. The first two forms draw the image at its native pixel size. The scalar box form stretches it to fill a `width`×`height` box, and the [`Rectangle`](../Drawing/Geometry.md#rectangle) form does the same with a value you can pass around.

```swift
drawImage(logo, 40, 40)                       // native size, top-left at (40, 40)
drawImage(logo, 40, 40, 200, 200)             // scaled into a 200×200 box
drawImage(logo, in: Rectangle(center: c, width: 200, height: 200))
```

The image follows the transform stack, so `translate` / `rotate` / `scale` move and warp it. The pivot is wherever you have set the origin:

```swift
withState {
    translate(width / 2, height / 2)
    rotate(time * 0.2)
    drawImage(logo, in: Rectangle(center: Vector2(0, 0), width: 300, height: 300))
}
```

The image is recorded in call order with everything else. So a shape drawn after `drawImage` paints over it, and one drawn before sits behind it.

**Drawn smaller than its own size.** A loaded image keeps a set of smaller copies of itself, called a mip chain. When you draw the image smaller than its own size, Ollin samples those copies. So a photograph drawn at a quarter of its size still shows the whole photograph, not one pixel in four picked out of the original. The copies are averaged in linear light, so the tone does not shift. When you draw the image at its own size or larger, nothing changes. Pixels the sketch wrote itself through [`image[x, y]`](#pixels) keep the single level they uploaded with. The details are under [textures](../3D/3D.md#texture-filtering).

<a name="fit"></a>

### Fitting a picture to a box

```swift
drawImage(_ image: Image, in rect: Rectangle, fit: ImageFit)
drawImage(_ image: Image, _ x: Double, _ y: Double, _ width: Double, _ height: Double, fit: ImageFit)
```

A picture and the box you draw it into are rarely the same shape. `fit` says what to do about the difference:

| `ImageFit` | What it does | What it costs |
|---|---|---|
| `.stretch` | squashes the picture to the box | the picture's proportions |
| `.contain` | puts the whole picture inside, centered | part of the box, showing along two edges |
| `.cover` | fills the box completely, centered | the picture's own edges, cropped away |

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/09-Pictures/PictureFit-dark.jpg">
  <img src="../../Guide/Images/09-Pictures/PictureFit.jpg" alt="The same 3:2 photograph of a city street drawn into three 2:3 boxes: stretched, where the round dome of a church goes narrow; contained, where the whole picture sits in a band with the box showing above and below; and covered, where the box is full and only the middle of the width is left" width="680">
</picture>

```swift
drawImage(photo, in: panel, fit: .cover)      // fills the panel, edges lost
drawImage(photo, in: panel, fit: .contain)    // all of it, the panel showing above and below
```

`.stretch` is what the plain `drawImage(_:in:)` has always done, so it is the default. Code that does not pass `fit` draws as before.

A round shape in the picture is the quickest way to tell the three apart. `.stretch` turns it into an ellipse, and the other two leave it round.

`.cover` costs nothing extra to draw. The quad reads a smaller part of the picture instead of being clipped, so a covered picture is still one quad and one texture read.

`Rectangle` offers the same arithmetic when you want the box rather than the drawing. Call [`Rectangle(fitting:in:)`](Geometry.md#rectangle) for the box `.contain` uses, and `Rectangle(covering:in:)` for the box `.cover` uses. Both keep the picture's proportions and both stay centered, but the first sits inside the container and the second runs past it.

Worked example: [`Images/Fit`](../../Examples/Images/Fit/Sketch.swift).

<a name="part"></a>

### Part of a picture

```swift
drawImage(_ image: Image, _ x: Double, _ y: Double, _ width: Double, _ height: Double,
          _ sourceX: Double, _ sourceY: Double, _ sourceWidth: Double, _ sourceHeight: Double)
drawImage(_ image: Image, in rect: Rectangle, source: Rectangle)
```

A sprite sheet keeps many pictures in one image: the frames of an animation in a row, the tiles of a map in a grid. The last four numbers, or the `source` rectangle, name the part to draw, in the image's own pixels measured from its top-left. That part is drawn into the box the first numbers give, at whatever size the box is, and nothing is cropped first.

```swift
let frame = frameCount / 4 % 8                       // eight 64-pixel frames in a row
drawImage(walk, 100, 100, 128, 128, Double(frame) * 64, 0, 64, 64)

let tile = Rectangle(x: Double(column) * 16, y: Double(row) * 16, width: 16, height: 16)
drawImage(tiles, in: Rectangle(x: x, y: y, width: 48, height: 48), source: tile)
```

**The draw reads only inside the part.** Drawing a picture larger than itself blends neighboring pixels to fill the space between them. At the edge of a cell, the neighbor belongs to the next frame, so a magnified sprite would pick up a thin line of the cell beside it. The source rectangle holds the read half a pixel inside its own edges, the way a picture's own edge is held, so a cell drawn at its own size or larger looks exactly like the same cell cropped out with [`cropped(x:y:width:height:)`](#image) and drawn whole. Drawn smaller than itself, a picture reads its [smaller copies](#drawimage), and those average across the edges between cells. A sheet that leaves a few pixels of space around each cell keeps those clean too.

The part of the rectangle that runs off the picture draws nothing, as if the picture were surrounded by empty space. The part that is on it lands where it would have, so a source rectangle half past the right edge fills the left half of the box.

`cropped` makes a new image on the CPU. A source rectangle costs nothing extra: the same quad reads a smaller part of the texture. So a sheet of a hundred frames is one texture however many of them you draw. Any `Image` works as the sheet, a layer's `image` included. A [web page](../Output/Web.md) of the sketch holds each read inside its part the same way.

`.cover` above reads a part of the picture too, but there the picture simply continues past the part it shows, so it blends across that edge as a photograph should.

Worked example: [`Images/SpriteSheet`](../../Examples/Images/SpriteSheet/Sketch.swift).

<a name="tint"></a>

### tint

```swift
tint(_ color: Color)
noTint()
```

`tint` multiplies each texel of every following `drawImage` by `color`. The RGB recolors the image, and the alpha fades it. The default is white at full alpha, which leaves the image unchanged. `noTint()` returns to that default, so images draw as they are.

```swift
tint(Color(red: 1, green: 0.7, blue: 0.3))        // warm wash
drawImage(photo, 0, 0)

tint(Color(white: 1, alpha: 0.4))                 // 40% opacity, no color shift
drawImage(photo, 0, 0)

noTint()                                          // back to unchanged
```

Tint is drawing state like `fill` and `stroke`, so [`withState { }`](../Drawing/Drawing.md#withstate) saves and restores it. That lets you tint one image without the color carrying over to the next. The tint multiplies only as the image is drawn and never edits the image's stored pixels, so [reading them back](#pixels) always returns the original colors.

```swift
withState {
    tint(Color(red: 0.6, green: 0.8, blue: 1.0, alpha: 0.8))
    drawImage(photo, 0, 0, width, height)
}
```

<a name="image"></a>

### Image

```swift
Image(contentsOf url: URL) throws
Image(data: Data) throws
Image(resource name: String, withExtension ext: String?, in bundle: Bundle) throws
Image(cgImage: CGImage)
Image(width: Int, height: Int, color: Color = .clear)
Image(width: Int, height: Int, premultipliedRGBA: [UInt8])
```

`Image` is the typed value `drawImage` takes. It is a reference type that owns a GPU texture, so it is identified by the object itself, not by its contents. The three loading initializers throw a `FileError`: `missing` when the file or resource is not there, `unreadable` when the bytes are not a decodable image. Every image reports its pixel `width` / `height` as `Int`s, and its `size` as the same pair in a `Vector2`. The `Vector2` form works with the geometry helpers, so `Rectangle(fitting: image.size, in: bounds)` letterboxes the image.

`Image(width:height:color:)` makes a blank `width`×`height` image filled with `color`, which is transparent by default. You can then [author it from scratch](#pixels) pixel by pixel instead of loading a file.

`Image(width:height:premultipliedRGBA:)` wraps pixels you have already produced in bulk: `width × height × 4` RGBA bytes with premultiplied alpha, rows top to bottom. The buffer becomes the image's own pixels with no decode or conversion, because the GPU texture uploads straight from it. That makes it the fast path for images you generate every frame. The initializer returns `nil` when the byte count does not match the dimensions.

Load a bundled asset with the `resource:` initializer. `in:` has no default on purpose, because a default argument would resolve to *Ollin's* bundle and never yours. So pass `.module` from the target that bundles the file:

```swift
let texture = try? Image(resource: "paper", withExtension: "png", in: .module)
```

`currentCGImage()` is the pixels as they stand now, edits through the `[x, y]` subscript included, where `cgImage` is always the original decode. It is what interop that must see the live pixels (Vision, Core Image) should ask for. `Image(cgImage:)` goes the other way and wraps a `CGImage` you already have in memory. It can be one you rendered yourself, decoded elsewhere, or built procedurally, so anything that produces a `CGImage` becomes drawable.

`resized(width:height:)` hands back a copy at another pixel size, resampled with high-quality interpolation. It is the call to make before handing a large picture to something that reads every pixel, such as a stipple, a dither, a mosaic, or a string-art winding, which want a copy of a few hundred pixels a side. It reads the CPU pixels, so it applies to a picture decoded from a file or authored pixel by pixel; an image wrapping a live texture comes back as a blank of the requested size. Setup-time work, so keep the result.

```swift
let small = SamplePhoto.scarf.load().resized(width: 300, height: 300)
```

`cropped(x:y:width:height:)` changes what is in the picture rather than how big it is: it hands back a copy of the given rectangle, measured from the top-left corner. The rectangle is clamped to the picture, so a crop that runs off an edge comes back smaller rather than empty. `cropped(toAspect:)` is the common case spelled once, the largest centered piece of a given shape, where the number is width over height. Nothing is scaled either way, so the copy keeps the original's own pixels.

```swift
let wide = SamplePhoto.city.load().cropped(toAspect: 3.0 / 2)   // a 3:2 slice of a square
let corner = photo.cropped(x: 0, y: 0, width: 512, height: 512)
```

For a picture to try any of this on, `import OllinSamplePhotos` bundles [twenty pictures](./SamplePhotos.md) with their credits.

**Transparency works.** Ollin honors a PNG's alpha channel, so transparent regions show what is behind them, and the edges composite cleanly.

<a name="pixels"></a>

### Pixels

The subscript reads or writes a single pixel. `(0, 0)` is the top-left corner, and coordinates run to `(width - 1, height - 1)`.

```swift
let c = image[x, y]          // read a pixel's Color (a get)
image[x, y] = .red           // write one (a set)
```

An out-of-range access does not crash, so a stray index cannot break a loop. Reading off the edge returns `.clear`, and writing off the edge does nothing.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/09-Pictures/PixelSampling-dark.jpg">
  <img src="../../Guide/Images/09-Pictures/PixelSampling.jpg" alt="Left, a small sunset image; right, the same image redrawn as a grid of dots, each dot taking its pixel's color and sized by its brightness" width="680">
</picture>

Pair the subscript write with the blank initializer to author an image from scratch. Make a transparent image, paint it pixel by pixel, then draw it:

```swift
final class PixelArt: Sketch {
    var sprite: Image?

    override func setup() {
        let image = Image(width: 64, height: 64)
        for y in 0..<64 {
            for x in 0..<64 {
                let t = Double(x) / 63
                image[x, y] = Colormap.turbo.color(at: t)
            }
        }
        sprite = image
    }

    override func draw() {
        background(.black)
        if let sprite { drawImage(sprite, 0, 0, width, height) }
    }
}
```

A write shows on the next `drawImage`, because the GPU texture rebuilds from the edited pixels at that point. That rebuild is why you should author in `setup()` when you can, rather than rewriting the whole image every frame. Reading is cheap once the first access has decoded the pixels.

Colors pass through the image's premultiplied storage, so a translucent color that is written and then read back can shift by a step of `1/255`. Reading ignores [`tint`](#tint), so a get returns the stored color, never the tinted one.

Only a picture held in memory has pixels to read. An image the GPU fills, such as a layer's `image` or a compute texture's, reads `.clear` at every point. A write to one is ignored, because what gets drawn is its texture.

The **PixelField** example authors a field with `set`, samples it back with `get`, and animates a `tint` on top of it.
