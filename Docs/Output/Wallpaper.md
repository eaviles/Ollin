#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Output](./README.md) → `Wallpaper`</sup>

---

## A sketch as the desktop wallpaper

The desktop is the picture you see most and look at least. A wallpaper piece puts a running sketch there: behind the icons, under every window, moving all day while the machine is used for everything else.

```sh
ollin new Drift --kind wallpaper
cd Drift && swift run Drift
```

The desktop becomes the piece. A small sparkle appears at the right end of the menu bar; click it and pick Quit to get the plain desktop back. `./build.sh --install` makes it an app in /Applications, and adding that app under System Settings, General, Login Items makes it the machine's wallpaper for good.

### What you get

```
Drift/
  Package.swift              an ordinary program
  Info.plist                 the app's name tag, kept out of the Dock
  build.sh                   wraps the built binary in Drift.app
  Sources/Drift/
    Sketch.swift             an ordinary sketch
    Main.swift               the program: hands the sketch to the host
```

`Main.swift` is the whole of the wiring:

```swift
import Ollin

@main
enum DriftMain {
    @MainActor static func main() {
        if OllinApp.handleCommandLine(makeSketch: { Drift() }) { return }
        OllinApp.runAsWallpaper { Drift() }
    }
}
```

`OllinApp.runAsWallpaper` is the framework's host. It opens one borderless window per display at desktop level, and builds a sketch for each from the closure. When monitors come and go, the windows follow. The first line keeps the shared command-line surface, so `--export` and its siblings work on this program too. It is also how `build.sh` renders the app's icon from a frame of the piece.

### Behind the icons, out of the way

The window sits at the system's own desktop level: over the picture the system keeps there, under the icons, under every window. Three rules make it wallpaper rather than a window:

- **It takes no clicks and no keys.** A click on the desktop lands on the desktop. The piece never takes the keyboard, so `mouseX`, `mouseY`, `mouseIsPressed`, and `key` hold whatever they started at.
- **It is on every space.** A swipe to another desktop keeps the piece, and the window cycle never lands on it.
- **The app stays out of the Dock.** There is no window to bring forward, so a Dock icon would read as a hang. Quit lives in the menu-bar sparkle instead.

### Filling the display, or fitting it

A display is almost never the shape of a canvas. Which of the two you get is the sketch's own `windowMode`, exactly as it is in a window:

| The sketch says | On the desktop |
|---|---|
| `windowMode` is `.resizable` | The canvas *is* the display. `width` and `height` are the screen's, and the drawing fills it. |
| anything else | The canvas keeps its own proportions, as large as fits, centered on black. |

`ollin new` writes `.resizable` into the generated sketch, because wallpaper that fills the screen is what people mean by wallpaper. Each display runs a sketch of its own, built by the closure. A canvas that follows its view is the size of its display and no other.

### It runs all day

The piece draws at the display's own rate for as long as the machine is up. That is the point, and it is also a budget: a heavy sketch as wallpaper runs through every meeting and every compile. Calm pieces wear well here, and a still one can call `noLoop()` and cost nothing at all.

### Working on it

The desktop is a slow place to look at a change. Open the same sketch in a window, where it reloads as you save, and put it on the desktop when it looks right:

```sh
ollin Sources/Drift/Sketch.swift
```

The file is the same file either way.

### The app

`build.sh` is the same wrapper the [Mac app](./App.md) kind writes. It builds the package, wraps the binary in the `.app` folder, and signs the result for this machine. The icon is a frame the sketch renders of itself. `--sign` and `--notarize` make one that travels, exactly as that page describes. The one difference is a single line in `Info.plist` that keeps the app out of the Dock.

---

## See also

- [Menu bar](./MenuBar.md) - the same idea at the other size: a live strip beside the clock
- [Screen saver](./ScreenSaver.md) - the piece that runs when nobody is at the desk
- [Sketch as an app](./App.md) - the wrapper this kind shares, and the story for handing one out
- [Installation](./Installation.md) - a piece left running on a wall rather than a desk
- [The project generator](../Tools/ProjectGenerator.md) - the kinds of project `ollin new` writes, this one among them
