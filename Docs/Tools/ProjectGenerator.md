# The project generator

Starting a sketch should not begin with copying boilerplate out of somewhere else. The generator asks a few questions and hands back a folder that already runs: `ollin new` in the terminal, `ollin generate` in a window.

```sh
ollin new MyPiece                                  # a folder that builds and runs
ollin new MyPiece --template shader --with audio   # wired for a shader and the microphone
ollin new MyPiece --from Motion/Breathing          # start from an example, material and all
ollin new Dots.swift                               # one loose file, nothing around it
ollin new                                          # one loose file, named by the next serial
ollin new --list                                   # every kind, template, and extra
ollin generate                                     # the same choices, in a window
```

Both faces run the same generator, so a project made in the window and one made in the terminal are the same project.

## What it makes

A **kind** is what the thing you get *is*.

| Kind | What it is |
|---|---|
| `single-file` | One `.swift` file, executable, run with `ollin`. The smallest thing that is a whole sketch. |
| `mac-sketch` | A folder with its own manifest, sources, and assets, built with `swift run`. |

`ollin new --list` shows more kinds than these two, each carrying the reason it is not ready: an iPhone app, a Vision app, a screen saver, an AR effect. They are named rather than hidden because that is the map of where this goes, and each waits on a platform leg rather than on the generator.

A name ending in `.swift` asks for one loose file; any other name makes a folder. That is the only difference in how you ask.

## What it starts from

A **template** is a whole small sketch that already does something, so the first thing you see is motion rather than an empty `draw()`.

| Template | What it draws |
|---|---|
| `blank` | A circle breathing on white. |
| `motion` | A ring of dots orbiting, their radius wandering on noise. |
| `pattern` | A grid where every cell decides its own mark, held still. |
| `shader` | A fragment shader of your own, run over every pixel. |
| `effects` | An off-screen layer, filtered on the GPU and composited back. |
| `3d` | A lit solid on a ground plane, the camera drifting around it. |
| `plotter` | Pen-ready line work on A4, made to leave as an SVG. |
| `camera` | The webcam as live material, ready for a tracker. |
| `sound` | Bars driven by what the microphone hears. |
| `physics` | A pile of discs settling under gravity. |

A template brings the libraries its own code needs, so picking `camera` links the vision library without you asking for it.

## Or start from an example

The examples are the largest body of working Ollin code there is, and any of them can be the thing you start from:

```sh
ollin new --examples                       # every one, grouped as they are filed
ollin new MyPiece --from Patterns/Marbling
```

The copy is yours: the type is renamed after your project, the libraries it imports are linked, and everything it loads (a picture, a mesh, a shader, a clip) is copied in beside it and declared, so it builds and runs before you have changed a line.

What is deliberately *not* changed is the file's header comment. For a ported sketch or a homage that comment is where the credit lives, so it travels with the code. Keep it there if you keep the lineage, and rewrite it when the piece has become yours.

## The 3D options

3D is the one part of the framework where the pieces genuinely do not all stack, and the rule is never obvious from the call itself: a matcap quietly swallows your lighting, traced reflections quietly do nothing without an environment, a wireframe has no surface to shade at all. The generator surfaces that map instead of leaving you to find out by rendering.

Pick the `3d` template and the options appear as three groups: **Geometry** (what is on screen), **Finish** (how its surface is done), and **On top** (everything added over both). Anything that cannot be combined is greyed out and says why.

```sh
ollin new --3d-options                  # every piece and the rule it carries
ollin new MyPiece --template 3d --3d mesh,pbr,environment,shadows,ray-traced,tone-map
```

The rules are a hierarchy, which is what makes the panel navigable: **geometry is never blocked**. Picking a wireframe settles the finish and drops whatever a wireframe cannot take, rather than refusing the click. What gets refused is a finish its geometry has no surface for, and an extra that its geometry or finish rules out.

That last command is the realism stack from [Combining 3D features](../3D/Combining.md), which is the full map in prose. If the two ever disagree, that page is right and the generator is the bug.

## Naming

With no name given, the generator uses a dated serial: `Sketch2026001`, then `002`, counting past the highest already in the folder, whether that one is a project folder or a loose file.

```sh
ollin new                  # Sketch2026001.swift, then Sketch2026002.swift
ollin new --kind mac-sketch  # the same name, as a folder
```

It exists because naming a piece before making it is the wrong order, and because a folder of serials sorts by when you made things. Give a name whenever you have one.

## What else to wire in

`--with` (the **Wire in** column in the window) adds anything else: a folder to keep pictures or fonts in, a `.metal` file for a shader, or any of the satellite libraries. Each one adds its `import`, its entry in the manifest, the folder it loads from, and one commented line in `setup()` showing the first call, left as a comment so a freshly made sketch always runs.

```sh
ollin new Listening --with audio,images,params
```

## The window

`ollin generate` opens the same choices with one addition worth having: the starting point in the middle is **actually running**. It is compiled and instantiated exactly as the examples gallery compiles an example, so what you watch is what you get, and a starting point that stopped compiling shows up there rather than in your new project.

Templates and examples are the two tabs on the left, and the preview works the same for both, so an example can be chosen by watching it rather than by remembering what it was called.

The right column previews the file list before anything is written. Nothing is written until you press Create, and Create refuses rather than overwriting a file that is already there.

The folder you last chose is remembered, and the suggested name is the next serial in *that* folder, so making several in a row is Create, Create, Create.

## What a project folder looks like

```
MyPiece/
  Package.swift
  README.md
  .gitignore
  Sources/MyPiece/
    Sketch.swift
    effect.metal          # with --with shaders
    Images/               # with --with images
```

Run it with `swift run MyPiece` from inside the folder. To edit it and watch each save land without the window closing, open the same file through the live host instead:

```sh
ollin Sources/MyPiece/Sketch.swift
```

Everything the sketch loads lives beside it in `Sources/MyPiece/`. A folder made by the generator is already declared in the manifest, so a picture dropped into `Images/` is reachable by name with no manifest edit:

```swift
let picture = loadImage(resource: "photo", withExtension: "jpg", in: .module)
```

## Where the framework comes from

A generated manifest points at the copy of Ollin the generator was run from, by path, so the project builds straight away with nothing to fetch. Two flags change that:

```sh
ollin new MyPiece --remote                      # point at the published framework
ollin new MyPiece --framework-path ~/dev/Ollin  # point at a particular copy
```

The path form is the right default while the framework is unpublished. Switch to `--remote` for a project you mean to hand to someone who does not have that folder.

## Every option

| Flag | What it does |
|---|---|
| `--kind <id>` | What to make. Defaults to `mac-sketch`, or `single-file` for a `.swift` name. |
| `--template <id>` | Which starting point. Defaults to `blank`. |
| `--from <Group/Name>` | Start from an example instead, material and all. |
| `--examples` | Print every example that can be started from. |
| `--with <a,b>` | Extra libraries and folders. |
| `--canvas <id>` | The canvas size to declare (`a4`, `fhd1080`, `vertical1080`, and the rest). |
| `--in <dir>` | Where to put it. Defaults to the current folder. |
| `--remote` | Point the manifest at the published framework. |
| `--framework-path <dir>` | Point it at a particular copy of the framework. |
| `--list` | Print every kind, template, and extra. |

## Adding to it

The catalogs are data. A new template is one value in `ProjectTemplate.all` carrying its source, the capabilities its code needs, and the kinds it fits; a new capability is one value in `Capability.all`; a new kind is one value in `ProjectKind.all` plus an emitter. Every template is compiled against the framework by the test suite, so one that falls behind an API change fails there rather than in someone's new project.

## See also

- [Single-file sketches](SingleFile.md) for the loose-file workflow the `single-file` kind produces.
- [Live coding](LiveCoding.md) for the performance host.
- [Export](../Output/Export.md) for everything a finished sketch can be turned into.
