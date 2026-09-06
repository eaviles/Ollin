#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Output](./README.md) → `Menu bar`</sup>

---

## A sketch in the menu bar

The menu bar is on screen for the whole working day. A menu-bar piece puts a small live canvas there, among the status items and beside the clock. That gives you a few points of motion that stay with you through everything else the machine is doing.

```sh
ollin new Pulse --kind menu-bar
cd Pulse && swift run Pulse
```

The strip appears in the menu bar and starts moving. Click it to open its menu, where Quit is the way out. `./build.sh --install` makes it an app in /Applications. Add that app under System Settings, General, Login Items, and the strip is there from login on.

### What you get

```
Pulse/
  Package.swift              an ordinary program
  Info.plist                 the app's name tag, kept out of the Dock
  build.sh                   wraps the built binary in Pulse.app
  Sources/Pulse/
    Sketch.swift             an ordinary sketch
    Main.swift               the program: hands the sketch to the host
```

`Main.swift` holds all of the wiring:

```swift
import Ollin

@main
enum PulseMain {
    @MainActor static func main() {
        if OllinApp.handleCommandLine(makeSketch: { Pulse() }) { return }
        OllinApp.runInMenuBar { Pulse() }
    }
}
```

`OllinApp.runInMenuBar` is the framework's host. It puts up one status item, runs the canvas inside that item's button, and attaches the menu that quits the piece. The first line keeps the shared command-line surface, so `--export` and the flags beside it work on this program too. That line is also how `build.sh` renders the app's icon from a frame of the piece.

### The strip

The strip is 56 points wide by default, and as tall as the menu bar itself. You set the width with an argument to the host's call:

```swift
OllinApp.runInMenuBar(width: 90) { Pulse() }
```

What the sketch sees follows its own `windowMode`, the same as everywhere else:

| The sketch says | In the strip |
|---|---|
| `windowMode` is `.resizable` | The canvas is the strip itself. `width` and `height` are those few points, so the drawing fills the strip. |
| anything else | The canvas keeps its own proportions, however small that makes it, centered on black. |

`ollin new` writes `.resizable` into the generated sketch, so the starter draws at the strip's real size. A canvas works the same way at any size. `width / 2` is still the middle, so a sketch written against `width` and `height` needs no changes to live here.

Two things are decided for you, and both come from where the piece runs:

- **It draws at 30 frames a second.** A strip beside the clock is up all day. That is worth a moving picture, not a whole display's worth of frames.
- **It takes no input.** A click falls through to the button, which opens the menu. That is what a click in the menu bar means. The strip never takes the keyboard, so `mouseX`, `mouseY`, `mouseIsPressed`, and `key` hold whatever they started at.

### Working on it

A strip is a small place to judge a change. Open the same sketch in a window instead, where it reloads as you save. Remember that the proportions go back to the strip's when the piece returns there:

```sh
ollin Sources/Pulse/Sketch.swift
```

The file is the same file either way.

### The app

`build.sh` is the same wrapper the [Mac app](./App.md) kind writes. It builds the package, wraps the binary in the `.app` folder, and signs the result for this machine. The icon is a frame the sketch renders of itself. `--sign` and `--notarize` make an app you can hand to someone else, exactly as that page describes. The one difference here is a single line in `Info.plist`. It keeps the app out of the Dock, since the strip is the app's whole face.

---

## See also

- [Wallpaper](./Wallpaper.md) - the same idea at the other size, with the whole desktop as the piece
- [Screen saver](./ScreenSaver.md) - the piece that runs when nobody is at the desk
- [Sketch as an app](./App.md) - the wrapper this kind shares, and how to hand an app to someone else
- [The project generator](../Tools/ProjectGenerator.md) - the kinds of project `ollin new` writes, this one among them
