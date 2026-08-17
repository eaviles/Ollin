#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Tools](./README.md) → `Single-file sketches`</sup>

---

## Single-file sketches

One `.swift` file can be a whole sketch, with no package to set up, no target to declare, and no project folder. The `ollin` command runs the file in the live window from any directory, exports it headlessly with the same flags a packaged sketch takes, and writes the starter file so you never type the boilerplate.

```sh
ollin new dots.swift        # write a starter sketch
ollin dots.swift            # run it: live window, hot-reload on save
./dots.swift                # the file is directly executable too
ollin dots.swift --export-gif dots.gif --seconds 4
```

### Contents

- [Install the command](#install-the-command)
- [Dash off an idea](#dash-off-an-idea)
- [Directly executable sketches](#directly-executable-sketches)
- [Exports and flags](#exports-and-flags)
- [Assets and satellite libraries](#assets-and-satellite-libraries)
- [Growing into a package](#growing-into-a-package)
- [How it works](#how-it-works)

---

### Install the command

`ollin` lives in the Ollin repository, so clone it once and link the command onto your `PATH`:

```sh
git clone https://github.com/eaviles/Ollin.git
cd Ollin
Scripts/ollin install
```

`install` symlinks the script into a writable directory already on your `PATH` (or into `~/.local/bin`, telling you what to add if that isn't on it). Because it's a symlink into the clone, there's nothing to re-install after a `git pull`, since the next run rebuilds whatever changed. You can also pass an explicit directory, as in `Scripts/ollin install ~/bin`.

The requirements are Ollin's own: macOS 26+, a Metal-capable GPU, and the Swift toolchain (the command compiles your sketch, so it needs `swiftc`). The first run builds the framework in release mode, which takes a few minutes. After that, starting a sketch takes seconds, and saves take less.

### Dash off an idea

```sh
ollin new dots.swift
ollin dots.swift
```

`new` writes a minimal breathing-circle sketch (the class named after the file) and marks it executable. `ollin dots.swift` opens it in the live host, so edit and save and the window swaps in the change without closing. A save that doesn't compile shows the error over the canvas while the last good sketch keeps drawing. Everything the live host offers is there: the `@Param` inspector, the seed card, `--keep-clock` to carry the clock across reloads, and `--record` to keep the run as a [movie](../Output/Recording.md) from its first frame.

The file is an ordinary Ollin sketch, so there's nothing single-file-specific to learn:

```swift
#!/usr/bin/env ollin
import Ollin

@main
final class Dots: Sketch {
    override func draw() {
        background(.white)
        noFill()
        stroke(.black)
        strokeWeight(3)
        drawCircle(width / 2, height / 2, 120 + sin(time) * 40)
    }
}
```

### Directly executable sketches

The first line above is a shell hashbang. With it, and the executable bit `new` already set (`chmod +x` for a file you wrote by hand), the sketch runs as its own command:

```sh
./dots.swift
./dots.swift --export dots.png
```

Ollin treats the hashbang line as a comment, and compile errors still point at the real line numbers in your file. The line is optional, and `ollin dots.swift` works either way.

### Exports and flags

Every export flag a packaged sketch takes works on a loose file, from whatever directory you're in (see [Export](../Output/Export.md) for the full surface):

```sh
ollin dots.swift --export frame.png --frame 120
ollin dots.swift --export-video dots.mp4 --seconds 6
ollin dots.swift --export-svg still.svg
ollin dots.swift --export-grid sheet.png --seeds 25
ollin dots.swift --seed 10 --export keeper.png
```

`--debug` as the first flag runs a debug build of the host (faster first build, slower rendering); everything else passes through to the sketch host.

### Leaving one running

A loose file can go on a wall, not only on your desk:

```sh
ollin piece.swift --installation
```

The flag hands the sketch a window of its own, full screen, with the pointer hidden and the display kept awake. What the sketch declares in its `Installation` applies there too, from the checkpoint that resumes a run to the corners you line it up by. See [Installation](../Output/Installation.md).

That host does not reload on save. A piece on a wall runs the code it was started with. Work on it with plain `ollin piece.swift`, then put it up.

`--displays spanning` spreads the canvas over every display the machine drives, and `--rehearse 3` lays that wall out as three windows on the desk you are at. Both route to the same host as `--installation`, since a wall needs the sketch to own its windows.

### Assets and satellite libraries

Files sitting beside the sketch load the way a packaged example's resources do, with `in: .module` pointing at the sketch's own folder:

```swift
let texture = Image(resource: "paper", extension: "png", in: .module)
```

The satellite libraries are all available: `import OllinAudio`, `import OllinMIDI`, `import OllinPhysics`, and the rest work in a loose file exactly as they do in a package target.

### Growing into a package

The sketch file is the artifact, and it stays portable. When an idea outgrows one file, move the same file into a SwiftPM executable target that depends on `Ollin`, delete the hashbang line, and it builds unchanged (`@main` already makes it the entry point). Nothing about the single-file form is a dialect.

### How it works

`ollin` finds its own repository through the symlink, builds the host there if anything changed, and hands it your file. Which host depends on the flags. The live one runs it normally. The one that gives the sketch its own window takes over when you ask for an installation. Only that file is compiled against the built framework, which is what makes a save quick: your sketch recompiles and the framework never does. Headless flags skip the window entirely.
