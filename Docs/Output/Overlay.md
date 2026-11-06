#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Output](./README.md) → `Overlay`</sup>

---

## A sketch over the desktop

A wallpaper runs behind everything. An overlay runs in front of it. The sketch floats above every other window, see-through wherever its canvas is clear, while you go on using the machine underneath. A click lands on the piece only where it drew something. Anywhere else, the click goes to whatever is below.

Any sketch runs this way with one flag:

```sh
swift run Example-Installation-OverDesktop --overlay
```

The sketch clears its canvas with `background(.clear)`. What it leaves clear is the desktop showing through. A small sparkle appears at the right end of the menu bar, and its menu holds Quit, since a piece with no window frame has nowhere else to be closed from.

### In code

A program of its own calls the host directly, the way a [wallpaper](./Wallpaper.md) does:

```swift
import Ollin

final class Fireflies: Sketch {
    override var windowMode: WindowMode { .resizable }

    override func draw() {
        background(.clear)
        noStroke()
        fill(.yellow)
        drawCircle(mouseX, mouseY, 12)
    }
}

@main
enum FirefliesOverlay {
    @MainActor static func main() {
        if OllinApp.handleCommandLine(makeSketch: { Fireflies() }) { return }
        OllinApp.runAsOverlay { Fireflies() }
    }
}
```

`handleCommandLine` first keeps every export flag working. `runAsOverlay` then opens the piece over the main display.

### How large it is

A sketch whose canvas follows its view (`windowMode` `.resizable`) covers the main display. One that states a `canvasSize` floats at that size, fitted to the screen, in the middle of the display. Either way the canvas is the piece's whole area, and `width` and `height` are its size.

### Where a click lands

The piece is wherever the last frame it drew is not clear. Ollin reads every other frame back at the canvas size and keeps its coverage. When the pointer moves, it looks up the coverage under it. Above a twentieth, the window takes the click. Below that, the click passes through. A soft edge's last faint pixels do not take clicks.

A canvas with an opaque background is the piece everywhere, so it takes every click on its area.

A press that began on the piece stays the piece's until the button comes up, however the picture moves under it. A drag does not fall through halfway.

A sketch can decide for itself instead. `hitTest:` takes the sketch and a point in canvas coordinates, and returns whether that point belongs to the piece:

```swift
import Ollin

final class Badge: Sketch {
    override func draw() {
        background(.clear)
        fill(.white)
        drawCircle(width / 2, height / 2, 80)
    }
}

@MainActor func runBadge() {
    OllinApp.runAsOverlay(hitTest: { sketch, point in
        (point - sketch.center).length < 80       // only the disk takes clicks
    }) { Badge() }
}
```

With `hitTest:` given, no frame is read back.

### What the sketch gets

- **The pointer, everywhere on the display.** `mouseX` and `mouseY` follow the pointer whether or not the window is taking clicks, so a piece can lean toward the pointer while the click goes through to the window below.
- **Presses, where the piece is.** `mousePressed()`, `mouseIsPressed`, and the other pointer hooks arrive when the press lands on the piece.
- **No keys.** The window never takes the keyboard. Whatever was being typed in keeps it.

### What it costs

The piece draws at the display's rate for as long as it runs, like a wallpaper. Reading the coverage back costs one copy of every other frame at the canvas size. A canvas the size of a display is several megabytes a copy, which a calm sketch does not notice and a heavy one may. `hitTest:` removes that cost.

The overlay stays above other windows, on every space, and over a program that is full screen. It is on the main display only.

---

## See also

- [Wallpaper](./Wallpaper.md) - the same piece behind the desktop instead of over it
- [Menu bar](./MenuBar.md) - a live strip beside the clock
- [Windows](./Windows.md) - a second window that shows one of the sketch's layers
- [Export](./Export.md) - `background(.clear)` also leaves a PNG or a video see-through
- [Installation](./Installation.md) - a sketch left running on a wall rather than a desk
