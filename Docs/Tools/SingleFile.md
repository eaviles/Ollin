#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Tools](./README.md) → `Single-file sketches`</sup>

---

## Single-file sketches

One `.swift` file can be a whole sketch, with no package to set up, no target to declare, and no project folder. The `ollin` command runs that file in the live window from any directory. The same command exports the file headlessly, with the same flags a packaged sketch takes. It also writes the starter file, so you never type the boilerplate. When the sketch grows into a package, the same command runs the package, and a save to any of its files reloads the window.

```sh
ollin new dots.swift        # write a starter sketch
ollin dots.swift            # run it: live window, hot-reload on save
./dots.swift                # the file is directly executable too
ollin dots.swift --export-gif dots.gif --seconds 4
ollin MySketch              # a package's folder: its sketch, every file of it
```

### Contents

- [Install the command](#install-the-command)
- [Dash off an idea](#dash-off-an-idea)
- [Directly executable sketches](#directly-executable-sketches)
- [Exports and flags](#exports-and-flags)
- [Assets and satellite libraries](#assets-and-satellite-libraries)
- [Growing into a package](#growing-into-a-package)
- [Code shared between sketches](#code-shared-between-sketches)
- [Where the live route stops](#where-the-live-route-stops)
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

`new` writes a small breathing-circle sketch, names the class after the file, and marks the file executable. `ollin dots.swift` then opens that sketch in the live host. Edit the file and save it, and the window swaps in the change without closing. A save that does not compile shows the error over the canvas, and the last good sketch keeps drawing. A save after the framework was rebuilt under the open window is refused the same way. Its sentence says to relaunch, since the new build would crash the old window. Everything the live host offers works here too. You get the `@Param` inspector and the seed card. `--keep-clock` carries the clock across reloads, and `--record` keeps the run as a [movie](../Output/Recording.md) from its first frame.

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
ollin dots.swift --installation
```

The flag gives the sketch a full-screen window of its own, hides the pointer, and keeps the display awake. What the sketch declares in its `Installation` applies there too, from the checkpoint that resumes a run to the corners you line it up by. See [Installation](../Output/Installation.md).

That host does not reload on save, so a sketch on a wall runs the code it was started with. Work on the sketch with plain `ollin dots.swift`, then put it up.

`--displays spanning` spreads the canvas over every display the machine drives. `--rehearse 3` lays that wall out as three windows on the desk you are at. Both flags use the same host as `--installation`, because a wall needs the sketch to own its windows.

### Assets and satellite libraries

A file that sits beside the sketch loads the way a packaged example's resources do, and `in: .module` points at the sketch's own folder:

```swift
let texture = try? Image(resource: "paper", withExtension: "png", in: .module)
```

The satellite libraries are all available. `import OllinAudio`, `import OllinMIDI`, `import OllinPhysics`, and the rest work in a loose file exactly as they do in a package target.

### Growing into a package

The sketch file is the artifact, and it stays portable. When an idea outgrows one file, `ollin new MySketch` writes a package around a sketch (see [the project generator](ProjectGenerator.md)). You can also move the same file into a SwiftPM executable target that depends on `Ollin`. Delete the hashbang line, and the file builds unchanged, because `@main` already makes it the entry point. The single-file form is not a dialect of its own.

The live window comes along. Name the sketch file, the package's folder, or nothing at all from inside the folder:

```sh
ollin MySketch/Sources/MySketch/Sketch.swift   # the sketch file
ollin MySketch                                 # the package's folder
cd MySketch && ollin                           # the package this directory is in
```

All three run the same sketch. A sketch in a package target compiles with every `.swift` file of that target. Helpers can move into files of their own, in folders if you like, and a save to any of them reloads the window. A file you add joins the next compile. Naming a helper file runs the target's sketch and says so. When a package holds several sketch targets, the folder form lists them and `--target` picks one:

```sh
ollin . --target Garden
```

The live compile reads `Package.swift` for what the package build does with the target. That covers the files it leaves out or names, the language mode, the defines and features in its Swift settings, and its resources. A folder the manifest processes is laid out the way the package's bundle lays it out. `Image(resource:withExtension:in:)` with `.module` then finds a picture in `Images/` on the live route, as it does under `swift run`. A target that declares no resources keeps the loose file's arrangement, where `.module` is the sketch's own folder.

A folder of loose sketches, each with its own `@main`, stays a folder of loose files. Only a file inside a target's folder compiles with its neighbors. A sketch kept loose inside a package, outside every target, still compiles alone.

### Code shared between sketches

A package can hold more than the sketch's own target. Code that several sketches use often moves into a library target beside them, and the manifest says which sketch depends on it:

```swift
// Package.swift
targets: [
    .target(name: "Petals", dependencies: [.product(name: "Ollin", package: "Ollin")]),
    .executableTarget(name: "Garden", dependencies: [
        "Petals",
        .product(name: "Ollin", package: "Ollin"),
    ]),
]
```

The sketch in `Garden` writes `import Petals`, and `ollin` runs it live like any other sketch. The live window reads the manifest, compiles `Petals` itself, and then compiles the sketch against it. It watches both folders:

- A save to the sketch compiles the sketch alone. The library is already built, so the save costs what it costs in a project of one target.
- A save to a file of `Petals` rebuilds that library, anything else that imports it, and the sketch.

A library can import another library, and the manifest gives the order they build in. On a small project with two libraries under the sketch, the first compile took between two and three seconds. A save to the sketch took 0.7 seconds, and a save to a library 1.3.

Another package works the same way when it is written in Swift. That covers a package you name by its path, and one SwiftPM fetches, such as an [extension](Extensions.md):

```swift
dependencies: [
    .package(path: "../Ollin"),
    .package(url: "https://example.com/ollinx-ribbons", from: "1.0.0"),
],
```

A package named by a path is watched like a target of your own. A fetched package is read from the project's `.build/checkouts` folder. When it is not there yet, or `Package.swift` was saved after the last fetch, the live window runs `swift package resolve` once to get it. That step needs the network the first time, and it waits while a `swift build` runs in the same folder.

Three things differ from `swift run`, and each follows from the live window building the library itself:

- **Every library is compiled against the Ollin the window is running.** The version of Ollin a fetched package asks for in its own manifest is not consulted, and neither is the one in yours.
- **A library keeps its stored values across a save to the sketch.** It stays loaded until one of its own files changes, so a `static var` inside it holds its value when the sketch reloads. A save to the library starts it over. The sketch's own state starts over on every save, as it always has.
- **Each build of a library has a longer name of its own.** It is the target's name and a short code, so that an edited library can load beside the one it replaces. The compiler's messages show the name you wrote. A type name the running sketch prints with `String(reflecting:)` shows the longer one.

### Where the live route stops

The live window builds Swift, against the framework it already carries. These cases need `swift run`, and each is refused with a sentence that names the target:

- **A target with C, C++, Objective-C, or assembly in it.** [swift-numerics](https://github.com/apple/swift-numerics) has one under its real-number module, so a package that depends on it is out of reach as well.
- **A system library, a prebuilt binary, a macro, or a plugin.**
- **A product whose modules the manifest renames** with `moduleAliases:`.

Two more differences are smaller:

- **`main.swift` is left out.** A target started by a `main.swift` runs live without that file. The host makes the sketch itself, and top-level code does not compile into the library the host loads. Anything `main.swift` declares for the other files belongs in a file of its own.
- **A target whose entry point is an app** is never offered by its folder. A SwiftUI app with a sketch inside it is that app's target, not a sketch's. Name the file that declares the sketch to run it live.

[Dragging a shape](DragToEdit.md) and saving tuned parameters write the sketch's own file. A shape drawn by a helper in another file is outlined, and a drag on it says which file drew it and leaves it alone.

### How it works

`ollin` finds its own repository through the symlink, builds the host there if anything changed, and hands your file to that host. The flags decide which host it is. The live host runs the sketch normally, and the host that gives the sketch its own window takes over when you ask for an installation. Only your sketch is compiled against the built framework, the one file or the files of its target. That is what makes a save quick: your sketch recompiles and the framework never does. A headless flag skips the window entirely.

For a sketch in a package, the host asks SwiftPM to read `Package.swift` once and keeps the answer until the manifest changes. The read evaluates the manifest and nothing more, so no dependency is fetched. It runs apart from the package's own build folder, so a `swift build` running in the package does not hold a save up.

A library the sketch imports is compiled by the host as well, from its Swift files, into a loadable library of its own. The host does not ask SwiftPM to build it. SwiftPM would build Ollin a second time inside your project, which took 37 seconds and 498 MB when measured. Its library would also be compiled against that second copy, not the one the window runs. The host's own compile of a small library takes under a second and writes nothing into the project.
