#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Output](./README.md) → `Windows`</sup>

---

## A second window for a layer

A sketch has one window, and its canvas is what the window shows. Some pieces want a second view beside it: the picture that goes to the projector, and a view of controls on the laptop that the audience never sees. `makeWindow(showing:title:)` gives one of the sketch's [layers](../Drawing/Effects.md) a window of its own.

```swift
import Ollin

final class Stage: Sketch {
    var monitor: RenderTarget!
    var controls: SketchWindow!
    var size = 120.0

    override func setup() {
        monitor = makeRenderTarget(width: 480, height: 270)
        controls = makeWindow(showing: monitor, title: "Controls")
    }

    override func draw() {
        // A press in the controls window sets the size.
        if controls.mouseIsPressed { size = controls.mouseX }

        background(.black)                       // the piece, in the sketch's own window
        fill(.white)
        drawCircle(width / 2, height / 2, size)

        withTarget(monitor) {                    // the controls, in the second window
            background(Color(white: 0.15))
            fill(.orange)
            drawRect(0, 0, size, Double(monitor.height))
        }
    }
}
```

Make the layer and the window once, in `setup()`. Draw the layer every frame with `withTarget`, in the same `draw()` as the piece. Both pictures come from one state, and both windows show the same frame, never one a step behind the other.

`makeWindow(showing:title:)` takes the layer and the window's title, and returns a `SketchWindow`.

### The window

The window is the layer's shape and keeps that shape when resized. It opens beside the sketch's own window. Drag it to another display and use its green button to fill that display, which is how either view gets onto a projector.

A sketch can open several, one for each layer it wants seen.

### `SketchWindow`

| | |
|---|---|
| `layer` | the layer the window shows |
| `title` | the window's title |
| `isOpen` | whether the window is on screen |
| `mouseX`, `mouseY` | the pointer over this window, in the layer's coordinates |
| `mouse` | the same as one `Vector2` |
| `mouseIsPressed` | whether the button is down over this window |
| `close()` | close the window; the layer goes on being drawn |

The pointer is in the layer's own points, from its top left, whatever size the window has been dragged to. The sketch's own `mouseX` and `mouseY` stay with its own window. The keyboard stays with the sketch's own window too: the second window never takes the keys.

When the person closes the window, `isOpen` turns false and it stays closed.

### Where no window opens

In an export there is no second window. `isOpen` stays false, the pointer reads zero, and the layer is drawn all the same, so a sketch needs no special case. The same holds on a surface that takes no input, a [wallpaper](./Wallpaper.md) or a [menu-bar strip](./MenuBar.md).

An export writes the sketch's own canvas. To get the second view into a file, draw the layer onto the canvas (`drawImage(monitor.image, 0, 0)`) in a sketch made for that.

### One camera to a frame

A frame has one 3D camera. A camera set inside the layer's block is the canvas's camera too, so a second window cannot yet show the same 3D world from another place. A flat view suits it today: controls, a plan, a readout, a waveform. Lights are the frame's as well. Set them once, and they light everything the frame draws.

[`Examples/Installation/SecondView`](../../Examples/Installation/SecondView/Sketch.swift) is a stage in the sketch's own window and its plan in a second one, where a drag moves the lamp.

---

## See also

- [Effects](../Drawing/Effects.md) - layers: `makeRenderTarget`, `withTarget`, and what a layer can hold
- [Installation](./Installation.md) - one canvas across several displays, corner pinning, and edge blending
- [Overlay](./Overlay.md) - a sketch floating over the desktop
- [Canvas](../Core/Canvas.md) - the sketch's own window and its modes
