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
- [Image](#image) — the value type, and loading from data or a bundle

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

<a name="image"></a>

### Image

```swift
Image(contentsOf url: URL)
Image(data: Data)
Image(resource name: String, extension ext: String?, in bundle: Bundle)
Image(cgImage: CGImage)
```

`Image` is the typed value `drawImage` takes. It's a reference type: it owns a GPU texture and is identified by who holds it, not by value. The failable initializers return `nil` when the bytes aren't a decodable image.

Load a bundled asset with the `resource:` initializer. `in:` has no default on purpose — a default argument would resolve to *Ollin's* bundle, never yours — so pass `.module` from the target that bundles the file:

```swift
let texture = Image(resource: "paper", extension: "png", in: .module)
```

`Image(cgImage:)` wraps an image you already have in memory (a `CGImage` you rendered yourself, decoded elsewhere, or built procedurally), so anything that can produce a `CGImage` can become drawable.

A few things worth knowing:

- **Transparency works.** A PNG's alpha is respected — transparent regions let what's behind show through, and the edges composite cleanly.
- **No `tint()` or pixel access yet.** Per-image tinting, and reading or writing individual pixels (p5's `pixels[]`), aren't here yet. For now an image draws as-is. Generate a `CGImage` if you need to author pixels before drawing.
