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
| `mac-app` | A finished piece wrapped as a signed, double-clickable [Mac app](../Output/App.md), icon and all, for a machine without the toolchain. |
| `in-package` | A sketch folder plus one target in the `Package.swift` already above it. |
| `screen-saver` | A sketch wrapped as the machine's [screen saver](../Output/ScreenSaver.md), with the script that builds and installs it. |
| `wallpaper` | A sketch that runs as the [desktop wallpaper](../Output/Wallpaper.md), drawn across every display behind the icons. |
| `menu-bar` | A sketch that runs as a small live strip [in the menu bar](../Output/MenuBar.md), beside the clock all day. |
| `extension` | A library other people's sketches import, named and laid out by the [shared convention](Extensions.md). |

`ollin new --list` shows more kinds than these, and each of the rest carries the reason it is not ready. There is an iPhone app, a Vision app, and an AR effect. They are named rather than hidden, because that is the map of where this goes. Each waits on a platform leg rather than on the generator.

A name ending in `.swift` asks for one loose file; any other name makes a folder. That is the only difference in how you ask.

## When you are already inside a package

A folder of sketches is usually **one package with a target each**, not a package each. The framework then builds once for all of them, and every sketch is a one-file compile. So the generator joins a package you are already inside, rather than making another. It does that whenever the folder you point at sits inside a Swift package that depends on Ollin:

```sh
cd sketchbook/2026/08
ollin new Nightfall          # a sketch folder here, and one target in sketchbook/Package.swift
```

It says so when it does, and `--kind mac-sketch` overrides it for a project of its own. In the window the kind menu gains **Add to this package** whenever there is one to join. The file list names the manifest edit beside the files being created.

This is the only thing the generator does that changes a file you already had, so it is deliberately timid:

- It refuses a package that does not depend on Ollin yet, because a target added there could not import the framework.
- It inserts one target at the end of the existing `targets:` list, matching that list's own brackets rather than the first `]` it finds.
- If it cannot read the target list confidently, it writes the sketch, leaves the manifest untouched, and prints the stanza for you to paste.
- The target's `path:` is wherever your folders actually put the sketch, so any layout works.

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

The copy is yours. The type is renamed after your project, and the libraries it imports are linked. Everything it loads is copied in beside it and declared, whether that is a picture, a mesh, a shader, or a clip. So it builds and runs before you have changed a line.

What is deliberately *not* changed is the file's header comment. For a ported sketch or a homage that comment is where the credit lives, so it travels with the code. Keep it there if you keep the lineage, and rewrite it when the piece has become yours.

## The 3D options

3D is the one part of the framework where the pieces genuinely do not all stack. The rule is never obvious from the call itself. A matcap quietly swallows your lighting. Traced reflections quietly do nothing without an environment. A wireframe has no surface to shade at all. The generator surfaces that map, instead of leaving you to find out by rendering.

Pick the `3d` template and a strip appears **under the stage it governs**, laid along the direction of the constraint. First comes **Geometry**, what is on screen. Then comes **Finish**, how its surface is done. Last comes **On top**, everything added over both. They run left to right, with arrows between them. The reading order is the rule. What sits left of a thing can block it, and what sits right cannot. So the shape of the constraint is visible before you click anything.

A blocked chip is dimmed, marked, and **names its cause** on the chip itself. The choice doing the blocking reports its reach (`blocks 3`). Hovering any chip, blocked or not, explains it in the line under the strip.

```sh
ollin new --3d-options                  # every piece and the rule it carries
ollin new MyPiece --template 3d --3d mesh,pbr,environment,shadows,ray-traced,tone-map
```

The rules are a hierarchy, which is what makes the panel navigable. **Geometry is never blocked.** Picking a wireframe settles the finish and drops whatever a wireframe cannot take, rather than refusing the click. What gets refused is a finish its geometry has no surface for, and an extra that its geometry or finish rules out.

That last command is the realism stack from [Combining 3D features](../3D/Combining.md), which is the full map in prose. If the two ever disagree, that page is right and the generator is the bug.

## Naming

With no name given, the generator uses a dated serial. It writes `Sketch2026001`, then `002`, counting past the highest already in the folder. That highest one can be a project folder or a loose file.

```sh
ollin new                  # Sketch2026001.swift, then Sketch2026002.swift
ollin new --kind mac-sketch  # the same name, as a folder
```

It exists because naming a piece before making it is the wrong order, and because a folder of serials sorts by when you made things. Give a name whenever you have one.

## What else to wire in

`--with` adds anything else, and it is the **Wire in** column in the window. It can add a folder to keep pictures or fonts in, a `.metal` file for a shader, or any of the satellite libraries. Each one adds its `import`, its manifest entry, the folder it loads from, and one commented line in `setup()` showing the first call. That line stays a comment, so a freshly made sketch always runs.

```sh
ollin new Listening --with audio,images,params
```

## The window

`ollin generate` opens the same choices, with one addition worth having. The starting point in the middle is **actually running**. It is compiled and instantiated exactly as the examples gallery compiles an example. So what you watch is what you get. A starting point that stopped compiling shows up there, rather than in your new project.

There are three columns, and the window resizes. The stage takes the slack, because watching the thing run is the reason to open a window rather than type the command.

**Left, one list.** Templates sit as a group at the top. Then come the examples, grouped the way the folders already group them. One filter runs over both, and it matches group names as well as sketch names. Ten curated starting points and 350 cataloged ones are a short list and a long one, not two modes.

**Middle, the stage.** The starting point runs here. A line under it says what it is, how fast it is going, and whether it was just built or came from the cache. For the 3D template, the options strip sits under that (see below).

**Right, the project.** Name, where, canvas, and everything else behind one **Wire in** row that still reports what the starting point brought. The file list sits above the fold, with the guarantee under it. Nothing is written until you press Create, and Create refuses rather than overwriting.

The folder you last chose is remembered. The name field *suggests* the next serial in that folder, rather than filling it in. So making several in a row is Create, Create, Create, and naming one properly is typing over a suggestion.

The kind menu lives in the title bar, since it scopes the whole window. The kinds that are not ready sit under a divider inside it, dimmed, each with what it waits on.

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

A generated manifest points at the copy of Ollin the generator was run from, by path. The project then builds straight away, with nothing to fetch. Two flags change that:

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

The catalogs are data. A new template is one value in `ProjectTemplate.all`, carrying its source, the capabilities its code needs, and the kinds it fits. A new capability is one value in `Capability.all`. A new kind is one value in `ProjectKind.all` plus an emitter. Every template is compiled against the framework by the test suite. One that falls behind an API change fails there, rather than in someone's new project.

Two of the lists keep themselves up to date and one does not, which is worth knowing:

- **The examples list is discovered**, not declared. Anything under `Examples/` with a `Sketch.swift` appears, grouped by the folders it sits in, with the libraries it imports read off its own `import` lines. Ship an example and it is a starting point, with nothing to register. A library the capability list has never heard of is still linked, so a brand-new satellite works the day it lands. The scan runs at launch, so a folder added while the window is open needs a relaunch.
- **The 3D options are hand-kept**, because they are a map of which features combine rather than a list of what exists, and only a person can say that. They mirror [Combining 3D features](../3D/Combining.md), so a 3D capability that changes what stacks with what updates both. Once an option is added, the test suite compiles every combination the rules allow, so a rule that permits something impossible fails there.

## See also

- [Single-file sketches](SingleFile.md) for the loose-file workflow the `single-file` kind produces.
- [Live coding](LiveCoding.md) for the performance host.
- [Export](../Output/Export.md) for everything a finished sketch can be turned into.
