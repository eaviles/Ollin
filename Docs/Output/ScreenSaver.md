#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Output](./README.md) → `Screen saver`</sup>

---

## A sketch as the machine's screen saver

A sketch can run in a window, or it can run as the system's screen saver. A screen saver shows the work without anybody opening anything. It runs on your own machine when you step away, and on somebody else's after you hand it over.

```sh
ollin new Ripple --kind screen-saver
cd Ripple && ./build.sh --install
```

Then open System Settings, go to Screen Saver, and pick it from the list. There is nothing else to do.

### What you get

```
Ripple/
  Package.swift              builds a plug-in rather than a program
  Info.plist                 the name the system asks for
  build.sh                   wraps the built binary in Ripple.saver
  Sources/Ripple/
    Sketch.swift             an ordinary sketch
    SaverView.swift          six lines: the class the system loads
```

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/32-Installations/LivingInTheSystem-dark.jpg">
  <img src="../../Guide/Images/32-Installations/LivingInTheSystem.jpg" alt="A diagram in two columns: on the left, three stacked cards for the files inside Ripple.saver, with an arrow joining the NSPrincipalClass line in the property list to the matching @objc name in the code; on the right, two wide black screens showing a drawing filling one edge to edge and sitting square in the middle of the other" width="680">
</picture>

`SaverView.swift` is all the wiring there is:

```swift
import Foundation
import Ollin

@objc(RippleSaverView)
final class RippleSaverView: SketchSaverView {
    override func makeSketch() -> Sketch { Ripple() }
}
```

`SketchSaverView` is the framework's host. It builds the canvas when the system starts the saver. It then drives the frames from the display's own clock, and releases everything when the saver ends. The only thing you write is the `makeSketch()` override.

### The sketch is an ordinary sketch

Everything you would write in a window works here, including `time`, `frameCount`, `random`, the whole drawing surface, 3D, shaders, and effects. Two things are different, and both come from where the sketch runs rather than from the framework.

**It gets no input.** The system ends a screen saver on any key or click. If the canvas handled that click, the click would never reach the system. The screen saver would then not end, and the person at the machine could not get back to their work. So the canvas stays out of the event path entirely, which means `mouseX`, `mouseY`, `mouseIsPressed`, and `key` keep their starting values.

**It cannot write files.** The system loads a screen saver into a sandbox where it can read anything and write almost nothing. Loading works as usual, so pictures, fonts, meshes, and clips all open. Writing does not work, so `--export`, a recorded take, and a saved checkpoint cannot be used in a saver. None of them makes sense in a screen saver anyway.

### Filling the display, or fitting it

A display is almost never the same shape as a canvas. The sketch's own `windowMode` decides whether the drawing fills the display or fits inside it, exactly as it does in a window:

| The sketch says | On the display |
|---|---|
| `windowMode` is `.resizable` | The canvas *is* the display. `width` and `height` are the screen's, and the drawing fills it. |
| anything else | The canvas keeps its own proportions, as large as fits, centered on black. |

`ollin new` writes `.resizable` into the generated sketch, because most people expect a screen saver to fill the screen. If you remove that line, a square sketch stays square, with black on either side of it.

```swift
final class Ripple: Sketch {
    override var windowMode: WindowMode { .resizable }
    ...
}
```

A fitted canvas goes through the same present pass as a projector. It is scaled once, keeps its own proportions, and is never stretched.

### Working on it

A screen saver is a slow way to check a change, because every change means a build, an install, and a wait. Do the work in a window instead, where the sketch reloads as you save, and install it when it looks right.

```sh
ollin Sources/Ripple/Sketch.swift
```

The window and the saver run the same file.

### Building it again

```sh
./build.sh              # build Ripple.saver here
./build.sh --install    # build it and put it on this machine
```

The script builds the package and wraps the binary in the `.saver` folder. It copies the framework's own files in beside the binary, then signs the result. With `--install`, it also copies the saver to `~/Library/Screen Savers` and tells the host process to release the old one. The next preview then shows the new build.

Three details of that process matter, because each one is a way a saver fails without an error:

- **The framework's files go inside the saver.** Ollin looks for its shader segments, fonts, and tables beside the running program. In a saver, the running program belongs to the system, not to you. So the script copies those files into the saver's own `Resources`.
- **It has to be signed.** The system refuses to load an unsigned plug-in. The script signs it for this machine.
- **The name in `Info.plist` and the `@objc` name have to match.** That name is the only link between the two files. A saver with a mismatch still installs and appears in the list, but it shows the wrong thing or nothing at all.

### Giving it to somebody else

The signature `build.sh` applies is valid only on the machine that made it, so another Mac will refuse it. To run there, the saver needs a Developer ID signature and notarization, the same as any app you hand out:

```sh
codesign --force --sign "Developer ID Application: Your Name (TEAMID)" \
    --timestamp --options runtime Ripple.saver
```

Notarization needs the saver inside a container. Put it in a `.zip` or a `.dmg`, submit that, and staple the result back onto the bundle:

```sh
xcrun notarytool submit Ripple.zip --keychain-profile "AC" --wait
xcrun stapler staple Ripple.saver
```

Then anybody can drop it into `~/Library/Screen Savers`.

### Several displays

The system creates one saver for each display, so each screen runs its own copy of your sketch from its own first frame. The copies do not share a clock, so they are not in step. A piece that has to line up across two screens should be an [installation](./Installation.md) rather than a screen saver. An installation is built for a wall, with the displays laid out and the picture fitted across them.

---

## See also

- [Installation](./Installation.md) - the other way a piece runs unattended, for a wall rather than a desk
- [The project generator](../Tools/ProjectGenerator.md) - the kinds of project `ollin new` writes, including this one
- [Single-file sketches](../Tools/SingleFile.md) - one loose file as a whole sketch
- [Export](./Export.md) - rendering a picture to a file instead
