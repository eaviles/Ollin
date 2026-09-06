#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Tools](./README.md) → `Single-file sketches`</sup>

---

## Single-file sketches

One `.swift` file can be a whole sketch, with no package to set up, no target to declare, and no project folder. The `ollin` command runs that file in the live window from any directory. The same command exports the file headlessly, with the same flags a packaged sketch takes. It also writes the starter file, so you never type the boilerplate.

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

`install` symlinks the script into a writable directory that is already on your `PATH`. If it finds none, it uses `~/.local/bin` and tells you what to add to your `PATH`. The link points into the clone, so there is nothing to re-install after a `git pull`, because the next run rebuilds whatever changed. You can also name a directory yourself, as in `Scripts/ollin install ~/bin`.

The requirements are Ollin's own: macOS 26+, a Metal-capable GPU, and the Swift toolchain. The command compiles your sketch, so it needs `swiftc`. The first run builds the framework in release mode, which takes a few minutes. After that, starting a sketch takes seconds, and a save takes less.

### Dash off an idea

```sh
ollin new dots.swift
ollin dots.swift
```

`new` writes a small breathing-circle sketch, names the class after the file, and marks the file executable. `ollin dots.swift` then opens that sketch in the live host. Edit the file and save it, and the window swaps in the change without closing. A save that does not compile shows the error over the canvas, and the last good sketch keeps drawing. Everything the live host offers works here too. You get the `@Param` inspector and the seed card. `--keep-clock` carries the clock across reloads, and `--record` keeps the run as a [movie](../Output/Recording.md) from its first frame.

The file is an ordinary Ollin sketch, so there is nothing single-file-specific to learn:

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

The first line above is a shell hashbang. `new` already set the executable bit on the file, and you run `chmod +x` on a file you wrote by hand. With the hashbang line and that bit in place, the sketch runs as its own command:

```sh
./dots.swift
./dots.swift --export dots.png
```

Ollin treats the hashbang line as a comment, so compile errors still point at the real line numbers in your file. The line is optional, and `ollin dots.swift` runs the sketch either way.

### Exports and flags

Every export flag a packaged sketch takes also works on a loose file, from whatever directory you are in. [Export](../Output/Export.md) covers the full set:

```sh
ollin dots.swift --export frame.png --frame 120
ollin dots.swift --export-video dots.mp4 --seconds 6
ollin dots.swift --export-svg still.svg
ollin dots.swift --export-grid sheet.png --seeds 25
ollin dots.swift --seed 10 --export keeper.png
```

`--debug` as the first flag runs a debug build of the host, which builds faster the first time and renders slower. Every other flag passes through to the sketch host. The sketch file itself compiles optimized either way, and `--no-optimize` compiles it plain so you can debug it.

### Leaving one running

A loose file can also run on a wall, not only on your desk:

```sh
ollin piece.swift --installation
```

The flag gives the sketch a full-screen window of its own, hides the pointer, and keeps the display awake. What the sketch declares in its `Installation` applies there too, from the checkpoint that resumes a run to the corners you line it up by. See [Installation](../Output/Installation.md).

That host does not reload on save, so a piece on a wall runs the code it was started with. Work on the sketch with plain `ollin piece.swift`, then put it up.

`--displays spanning` spreads the canvas over every display the machine drives. `--rehearse 3` lays that wall out as three windows on the desk you are at. Both flags use the same host as `--installation`, because a wall needs the sketch to own its windows.

### Assets and satellite libraries

A file that sits beside the sketch loads the way a packaged example's resources do, and `in: .module` points at the sketch's own folder:

```swift
let texture = Image(resource: "paper", withExtension: "png", in: .module)
```

The satellite libraries are all available. `import OllinAudio`, `import OllinMIDI`, `import OllinPhysics`, and the rest work in a loose file exactly as they do in a package target.

### Growing into a package

The sketch file is the artifact, and it stays portable. When an idea outgrows one file, move that same file into a SwiftPM executable target that depends on `Ollin`. Delete the hashbang line, and the file builds unchanged, because `@main` already makes it the entry point. The single-file form is not a dialect of its own.

### How it works

`ollin` finds its own repository through the symlink, builds the host there if anything changed, and hands your file to that host. The flags decide which host it is. The live host runs the sketch normally, and the host that gives the sketch its own window takes over when you ask for an installation. Only your file is compiled against the built framework, which is what makes a save quick, because your sketch recompiles and the framework never does. A headless flag skips the window entirely.
