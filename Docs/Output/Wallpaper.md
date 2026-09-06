#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Output](./README.md) → `Wallpaper`</sup>

---

## A sketch as the desktop wallpaper

You see the desktop more often than any other picture, and you look at it least. A wallpaper piece puts a running sketch there. It draws behind the icons and under every window, and it keeps moving all day while you use the machine for everything else.

```sh
ollin new Drift --kind wallpaper
cd Drift && swift run Drift
```

The desktop becomes the piece. A small sparkle appears at the right end of the menu bar, so click it and pick Quit to get the plain desktop back. To keep the piece, run `./build.sh --install`, which makes it an app in /Applications. Add that app under System Settings, General, Login Items, and it becomes the machine's wallpaper for good.

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

`Main.swift` holds all of the wiring:

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

`OllinApp.runAsWallpaper` is the host the framework provides. It opens one borderless window per display at desktop level, and it builds a sketch for each window from the closure. When you connect or disconnect a monitor, the windows follow. The first line keeps the shared command-line surface, so `--export` and its siblings work on this program too. That line is also how `build.sh` renders the app's icon from a frame of the piece.

### Behind the icons, out of the way

The window sits at the system's own desktop level. That puts it over the picture the system keeps there, under the icons, and under every window. Three rules make it wallpaper rather than a window:

- **It takes no clicks and no keys.** A click on the desktop lands on the desktop. The piece never takes the keyboard, so `mouseX`, `mouseY`, `mouseIsPressed`, and `key` hold whatever they started at.
- **It is on every space.** The piece stays in place when you swipe to another desktop, and the window cycle never lands on it.
- **The app stays out of the Dock.** There is no window to bring forward, so a Dock icon would suggest the app had hung. Quit lives in the menu-bar sparkle instead.

### Filling the display, or fitting it

A display is almost never the shape of a canvas. The sketch's own `windowMode` decides which of the two you get, exactly as it does in a window:

| The sketch says | On the desktop |
|---|---|
| `windowMode` is `.resizable` | The canvas is the display. `width` and `height` are the screen's, and the drawing fills it. |
| anything else | The canvas keeps its own proportions. It is drawn as large as fits, centered on black. |

`ollin new` writes `.resizable` into the generated sketch, because people expect wallpaper to fill the screen. Each display runs a sketch of its own, built by the closure. A canvas that follows its view takes the size of its own display and no other.

### It runs all day

The piece draws at the display's own rate for as long as the machine is up. That is the point of a wallpaper piece, and it is also a cost to plan for. A heavy sketch keeps drawing through every meeting and every compile. Calm pieces work well here, and a still one can call `noLoop()` and cost nothing at all.

### Working on it

The desktop is a slow place to look at a change. Open the same sketch in a window instead, where it reloads as you save, and put it back on the desktop when it looks right:

```sh
ollin Sources/Drift/Sketch.swift
```

It is the same file either way.

### The app

`build.sh` is the same wrapper the [Mac app](./App.md) kind writes. It builds the package, wraps the binary in the `.app` folder, and signs the result for this machine. The icon is a frame the sketch renders of itself. `--sign` and `--notarize` build an app you can hand to someone else, exactly as that page describes. The one difference here is a single line in `Info.plist` that keeps the app out of the Dock.

---

## See also

- [Menu bar](./MenuBar.md) - the same idea at a smaller size, a live strip beside the clock
- [Screen saver](./ScreenSaver.md) - the piece that runs when nobody is at the desk
- [Sketch as an app](./App.md) - the wrapper this kind shares, and how to hand an app to someone else
- [Installation](./Installation.md) - a piece left running on a wall rather than a desk
- [The project generator](../Tools/ProjectGenerator.md) - the kinds of project `ollin new` writes, this one among them
