#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Drawing](./README.md) → `Images`</sup>

---

## Images

Load a raster image and draw it onto the canvas. An image decodes once on the CPU, then uploads to the GPU the first time it is drawn. Ollin reads the formats Apple reads through ImageIO, including PNG, JPEG, HEIC, TIFF, and GIF. After the upload the image is a textured quad like any other shape. It follows the [transform stack](../Drawing/Drawing.md#translate) and composites in draw order with the rest of your drawing.

The usual pattern is to load the image in `setup()`, keep the result in a property, and draw it in `draw()`. Do it that way because decoding a file every frame is wasteful. The image keeps its GPU texture for as long as you hold it, so one load is enough.

```swift
final class Photo: Sketch {
    var photo: Image?

    override func setup() {
        photo = loadImage("/path/to/photo.jpg")
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
- [tint](#tint) - recolor and fade images as you draw them
- [Image](#image) - the value type, and loading from data or a bundle
- [Pixels](#pixels) - author or sample an image pixel by pixel

<a name="loadimage"></a>

### loadImage

```swift
loadImage(_ path: String) -> Image?
loadImage(_ url: URL) -> Image?
```

Decode an image file. The call returns `nil` if the file cannot be read or decoded, so unwrap the result (or `guard let` it) before drawing. Call it in `setup()`.

```swift
photo = loadImage("/Users/me/Pictures/leaf.png")
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
  <img src="../../Guide/Images/09-Pictures/PictureFit.jpg" alt="The same 3:2 landscape drawn into three 2:3 boxes: stretched, where the round sun goes oval; contained, where the whole picture sits in a band with the box showing above and below; and covered, where the box is full and the tree on the right has been cropped away" width="680">
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
Image(contentsOf url: URL)
Image(data: Data)
Image(resource name: String, withExtension ext: String?, in bundle: Bundle)
Image(cgImage: CGImage)
Image(width: Int, height: Int, color: Color = .clear)
Image(width: Int, height: Int, premultipliedRGBA: [UInt8])
```

`Image` is the typed value `drawImage` takes. It is a reference type that owns a GPU texture, so it is identified by the object itself, not by its contents. The failable initializers return `nil` when the bytes are not a decodable image. Every image reports its pixel `width` / `height` as `Int`s, and its `size` as the same pair in a `Vector2`. The `Vector2` form works with the geometry helpers, so `Rectangle(fitting: image.size, in: bounds)` letterboxes the image.

`Image(width:height:color:)` makes a blank `width`×`height` image filled with `color`, which is transparent by default. You can then [author it from scratch](#pixels) pixel by pixel instead of loading a file.

`Image(width:height:premultipliedRGBA:)` wraps pixels you have already produced in bulk: `width × height × 4` RGBA bytes with premultiplied alpha, rows top to bottom. The buffer becomes the image's own pixels with no decode or conversion, because the GPU texture uploads straight from it. That makes it the fast path for images you generate every frame. The initializer returns `nil` when the byte count does not match the dimensions.

Load a bundled asset with the `resource:` initializer. `in:` has no default on purpose, because a default argument would resolve to *Ollin's* bundle and never yours. So pass `.module` from the target that bundles the file:

```swift
let texture = Image(resource: "paper", withExtension: "png", in: .module)
```

`Image(cgImage:)` wraps a `CGImage` you already have in memory. It can be one you rendered yourself, decoded elsewhere, or built procedurally, so anything that produces a `CGImage` becomes drawable.

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

The **PixelField** example authors a field with `set`, samples it back with `get`, and animates a `tint` on top of it.
