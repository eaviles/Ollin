#### <sup>[Ollin](../README.md) → [Documentation](./README.md) → `Images`</sup>

---

## Images

Load a raster image and draw it onto the canvas. An image decodes once on the CPU (via ImageIO, so it reads anything Apple does — PNG, JPEG, HEIC, TIFF, GIF) and uploads to the GPU the first time it's drawn; from then on it's a textured quad like any other shape, so it rides the [transform stack](./Drawing.md#translate) and composites in draw order with the rest of your drawing.

The typical shape: load in `setup()`, keep the result in a property, draw it in `draw()`. Decoding a file every frame is wasteful, and the image holds its GPU texture for as long as you hold the image.

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

- [loadImage](#loadimage) — load from a path or URL
- [drawImage](#drawimage) — draw at native size, scaled, or into a rectangle
- [tint](#tint) — recolor and fade images as you draw them
- [Image](#image) — the value type, and loading from data or a bundle
- [Pixels](#pixels) — author or sample an image pixel by pixel

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

`loadImage` is sugar over [`Image(contentsOf:)`](#image); reach for the initializer directly when you have a `URL`, raw `Data`, or a bundled resource.

<a name="drawimage"></a>

### drawImage

```swift
drawImage(_ image: Image, _ x: Double, _ y: Double)
drawImage(_ image: Image, _ x: Double, _ y: Double, _ width: Double, _ height: Double)
drawImage(_ image: Image, in rect: Rectangle)
```

Draw `image` with its top-left corner at `(x, y)`. The first form uses the image's native pixel size; the second stretches it to fill a `width`×`height` box; the [`Rectangle`](./Geometry.md#rectangle) form is the same, with a value you can pass around.

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

<a name="tint"></a>

### tint

```swift
tint(_ color: Color)
noTint()
```

Tint every following `drawImage` by multiplying each texel by `color`: the RGB recolors the image and the alpha fades it. White at full alpha is the default, which leaves the image unchanged. `noTint()` returns to drawing images as-is.

```swift
tint(Color(red: 1, green: 0.7, blue: 0.3))        // warm wash
drawImage(photo, 0, 0)

tint(Color(white: 1, alpha: 0.4))                 // 40% opacity, no color shift
drawImage(photo, 0, 0)

noTint()                                          // back to unchanged
```

Tint is drawing state like `fill` and `stroke`: it's saved and restored by [`withState { }`](./Drawing.md#withstate), so you can tint one image without leaking the wash onto the next. It only multiplies as the image is drawn — it never edits the image's stored pixels, so [reading them back](#pixels) always returns the original colors.

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
```

`Image` is the typed value `drawImage` takes. It's a reference type: it owns a GPU texture and is identified by who holds it, not by value. The failable initializers return `nil` when the bytes aren't a decodable image.

The last initializer makes a blank `width`×`height` image filled with `color` (transparent by default), so you can [author one from scratch](#pixels) pixel by pixel rather than loading a file.

Load a bundled asset with the `resource:` initializer. `in:` has no default on purpose — a default argument would resolve to *Ollin's* bundle, never yours — so pass `.module` from the target that bundles the file:

```swift
let texture = Image(resource: "paper", extension: "png", in: .module)
```

`Image(cgImage:)` wraps an image you already have in memory (a `CGImage` you rendered yourself, decoded elsewhere, or built procedurally), so anything that can produce a `CGImage` can become drawable.

**Transparency works.** A PNG's alpha is respected — transparent regions let what's behind show through, and the edges composite cleanly.

<a name="pixels"></a>

### Pixels

Read or write a single pixel through the subscript. `(0, 0)` is the top-left corner; coordinates run to `(width - 1, height - 1)`.

```swift
let c = image[x, y]          // read a pixel's Color (a get)
image[x, y] = .red           // write one (a set)
```

Out-of-range access is forgiving so a stray index never crashes a loop: reading off the edge returns `.clear`, and writing off the edge does nothing.

Pair a write with the blank initializer to author an image from scratch — make a transparent canvas, paint it, then draw it:

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

A write shows on the next `drawImage` — the GPU texture rebuilds from the edited pixels — so author in `setup()` when you can rather than rewriting the whole image every frame. Reading is cheap once the first access has decoded the pixels.

Colors pass through the image's premultiplied storage, so round-tripping a translucent color can shift it by a step of `1/255`. Reading is independent of [`tint`](#tint): a get returns the stored color, never the tinted one.

See the **PixelField** example for authoring a field with `set`, sampling it back with `get`, and an animated `tint` over the top.
