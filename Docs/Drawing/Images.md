#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Drawing](./README.md) → `Images`</sup>

---

## Images

Load a raster image and draw it onto the canvas. An image decodes once on the CPU, then uploads to the GPU the first time it is drawn. It reads anything Apple does through ImageIO, which is PNG, JPEG, HEIC, TIFF, and GIF. From then on it is a textured quad like any other shape. It rides the [transform stack](../Drawing/Drawing.md#translate), and composites in draw order with the rest of your drawing.

The typical shape is to load in `setup()`, keep the result in a property, and draw it in `draw()`. Decoding a file every frame is wasteful, and the image holds its GPU texture for as long as you hold the image.

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

Decode an image file. Returns `nil` if the file can't be read or decoded, so unwrap it (or `guard let`) before drawing. Call it in `setup()`.

```swift
photo = loadImage("/Users/me/Pictures/leaf.png")
```

`loadImage` is sugar over [`Image(contentsOf:)`](#image). Reach for the initializer directly when you have a `URL`, raw `Data`, or a bundled resource.

<a name="drawimage"></a>

### drawImage

```swift
drawImage(_ image: Image, _ x: Double, _ y: Double)
drawImage(_ image: Image, _ x: Double, _ y: Double, _ width: Double, _ height: Double)
drawImage(_ image: Image, in rect: Rectangle)
```

Draw `image` with its top-left corner at `(x, y)`. The first form uses the image's native pixel size, and the second stretches it to fill a `width`×`height` box. The [`Rectangle`](../Drawing/Geometry.md#rectangle) form does the same with a value you can pass around.

```swift
drawImage(logo, 40, 40)                       // native size, top-left at (40, 40)
drawImage(logo, 40, 40, 200, 200)             // scaled into a 200×200 box
drawImage(logo, in: Rectangle(center: c, width: 200, height: 200))
```

The image rides the transform stack, so `translate` / `rotate` / `scale` move and warp it, pivoting wherever you've set the origin:

```swift
withState {
    translate(width / 2, height / 2)
    rotate(time * 0.2)
    drawImage(logo, in: Rectangle(center: Vector2(0, 0), width: 300, height: 300))
}
```

Because it's recorded in call order with everything else, a shape drawn after `drawImage` paints over it, and one drawn before sits behind it.

**Drawn smaller than it is**, a loaded image reads through its own smaller copies (a mip chain). A photograph at a quarter size is then a quarter-size photograph, not a quarter of its pixels picked out. The copies are averaged in linear light, so the tone holds. Drawn at its own size or larger nothing changes. Pixels the sketch wrote itself through [`image[x, y]`](#pixels) keep the single level they uploaded with. The full story is under [textures](../3D/3D.md#texture-filtering).

<a name="fit"></a>

### Fitting a picture to a box

```swift
drawImage(_ image: Image, in rect: Rectangle, fit: ImageFit)
drawImage(_ image: Image, _ x: Double, _ y: Double, _ width: Double, _ height: Double, fit: ImageFit)
```

A picture and the box you have for it are rarely the same shape, and `fit` says what to do about it:

| `ImageFit` | What it does | What it costs |
|---|---|---|
| `.stretch` | squashes the picture to the box | the picture's proportions |
| `.contain` | puts the whole picture inside, centered | part of the box, showing along two edges |
| `.cover` | fills the box completely, centered | the picture's own edges, cropped away |

<img src="../../Guide/Images/09-Pictures/PictureFit.jpg" alt="The same 3:2 landscape drawn into three 2:3 boxes: stretched, where the round sun goes oval; contained, where the whole picture sits in a band with the box showing above and below; and covered, where the box is full and the tree on the right has been cropped away" width="680">

```swift
drawImage(photo, in: panel, fit: .cover)      // fills the panel, edges lost
drawImage(photo, in: panel, fit: .contain)    // all of it, the panel showing above and below
```

`.stretch` is what the plain `drawImage(_:in:)` has always done, so it is the default and nothing changes for code that does not ask.

A round shape in the picture is the fastest way to see which one you have. `.stretch` turns it into an ellipse, and the other two leave it round.

`.cover` costs nothing extra to draw. The quad reads a smaller part of the picture rather than being clipped, so a covered picture is still one quad and one texture read.

The same arithmetic is on `Rectangle` when you want the box rather than the drawing: [`Rectangle(fitting:in:)`](Geometry.md#rectangle) is `.contain`'s box and `Rectangle(covering:in:)` is `.cover`'s. Both keep the shape and both stay centered; the first sits inside the container and the second runs past it.

Worked example: [`Images/Fit`](../../Examples/Images/Fit/Sketch.swift).

<a name="tint"></a>

### tint

```swift
tint(_ color: Color)
noTint()
```

Tint every following `drawImage` by multiplying each texel by `color`, so the RGB recolors the image and the alpha fades it. White at full alpha is the default, which leaves the image unchanged. `noTint()` returns to drawing images as-is.

```swift
tint(Color(red: 1, green: 0.7, blue: 0.3))        // warm wash
drawImage(photo, 0, 0)

tint(Color(white: 1, alpha: 0.4))                 // 40% opacity, no color shift
drawImage(photo, 0, 0)

noTint()                                          // back to unchanged
```

Tint is drawing state like `fill` and `stroke`, so [`withState { }`](../Drawing/Drawing.md#withstate) saves and restores it. You can tint one image without leaking the wash onto the next. It only multiplies as the image is drawn, and it never edits the image's stored pixels. So [reading them back](#pixels) always returns the original colors.

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
Image(resource name: String, extension ext: String?, in bundle: Bundle)
Image(cgImage: CGImage)
Image(width: Int, height: Int, color: Color = .clear)
Image(width: Int, height: Int, premultipliedRGBA: [UInt8])
```

`Image` is the typed value `drawImage` takes. It's a reference type, so it owns a GPU texture and is identified by who holds it, not by value. The failable initializers return `nil` when the bytes aren't a decodable image. Every image reports its pixel `width` / `height` as `Int`s, and its `size` as the same pair in a `Vector2`. That is ready for the geometry helpers, so `Rectangle(fitting: image.size, in: bounds)` letterboxes it.

`Image(width:height:color:)` makes a blank `width`×`height` image filled with `color`, which is transparent by default. So you can [author one from scratch](#pixels) pixel by pixel, rather than loading a file.

`Image(width:height:premultipliedRGBA:)` wraps pixels you've already produced in bulk: `width × height × 4` RGBA bytes, premultiplied alpha, rows top to bottom. The buffer becomes the image's own pixels with no decode or conversion, because the GPU texture uploads straight from it. That is the fast lane for per-frame generated images. Returns `nil` when the byte count doesn't match the dimensions.

Load a bundled asset with the `resource:` initializer. `in:` has no default on purpose, because a default argument would resolve to *Ollin's* bundle and never yours. So pass `.module` from the target that bundles the file:

```swift
let texture = Image(resource: "paper", extension: "png", in: .module)
```

`Image(cgImage:)` wraps an image you already have in memory. That can be a `CGImage` you rendered yourself, decoded elsewhere, or built procedurally, so anything that can produce a `CGImage` becomes drawable.

**Transparency works.** A PNG's alpha is respected, so transparent regions let what's behind show through and the edges composite cleanly.

<a name="pixels"></a>

### Pixels

Read or write a single pixel through the subscript. `(0, 0)` is the top-left corner, and coordinates run to `(width - 1, height - 1)`.

```swift
let c = image[x, y]          // read a pixel's Color (a get)
image[x, y] = .red           // write one (a set)
```

Out-of-range access is forgiving, so a stray index never crashes a loop. Reading off the edge returns `.clear`, and writing off the edge does nothing.

<img src="../../Guide/Images/09-Pictures/PixelSampling.jpg" alt="Left, a small sunset image; right, the same image redrawn as a grid of dots, each dot taking its pixel's color and sized by its brightness" width="680">

Pair a write with the blank initializer to author an image from scratch. Make a transparent canvas, paint it, then draw it:

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

A write shows on the next `drawImage`, where the GPU texture rebuilds from the edited pixels. So author in `setup()` when you can, rather than rewriting the whole image every frame. Reading is cheap once the first access has decoded the pixels.

Colors pass through the image's premultiplied storage, so round-tripping a translucent color can shift it by a step of `1/255`. Reading is independent of [`tint`](#tint), so a get returns the stored color, never the tinted one.

See the **PixelField** example for authoring a field with `set`, sampling it back with `get`, and an animated `tint` over the top.
