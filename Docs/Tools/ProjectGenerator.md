# The project generator

The generator starts a sketch for you, so you do not have to copy boilerplate out of somewhere else. It asks a few questions and hands back a folder that already runs. Use `ollin new` in the terminal, or `ollin generate` in a window.

```sh
ollin new MyPiece                                  # a folder that builds and runs
ollin new MyPiece --template shader --with audio   # wired for a shader and the microphone
ollin new MyPiece --from Basic/HelloCircle          # start from an example, material and all
ollin new Dots.swift                               # one loose file, nothing around it
ollin new Rings --kind ios-app                     # an app for the phone and the tablet
ollin new                                          # one loose file, named by the next serial
ollin new --list                                   # every kind, template, and extra
ollin generate                                     # the same choices, in a window
```

The window and the terminal run the same generator, so a project made either way is the same project.

## What it makes

A **kind** is the sort of thing the generator makes for you.

| Kind | What it is |
|---|---|
| `single-file` | One executable `.swift` file, run with `ollin`. It is the smallest thing that is a whole sketch. |
| `mac-sketch` | A folder with its own manifest, sources, and assets, built with `swift run`. |
| `mac-app` | A finished piece wrapped as a signed, double-clickable [Mac app](../Output/App.md) with its own icon, for a machine without the toolchain. |
| `in-package` | A sketch folder, plus one target in the `Package.swift` that already sits above it. |
| `screen-saver` | A sketch wrapped as the machine's [screen saver](../Output/ScreenSaver.md), with the script that builds and installs it. |
| `wallpaper` | A sketch that runs as the [desktop wallpaper](../Output/Wallpaper.md), drawn across every display behind the icons. |
| `menu-bar` | A sketch that runs as a small live strip [in the menu bar](../Output/MenuBar.md), beside the clock all day. |
| `extension` | A library that other people's sketches import, named and laid out by the [shared convention](Extensions.md). |
| `ios-app` | A sketch wrapped as an app for [the phone and the tablet](OnThePhone.md#in-an-app-of-your-own): an Xcode project spec rather than a package, with the signing team as its one extra question. |

`ollin new --list` shows more kinds than these. The rest are a Vision app and an AR effect, and each one carries the reason it is not ready. They are named rather than hidden, because they show where this goes. Each waits on the work for its platform, not on the generator.

A name that ends in `.swift` asks for one loose file, and any other name makes a folder. That is the only difference in how you ask.

## When you are already inside a package

A folder of sketches is usually **one package with a target each**, rather than one package per sketch. The framework then builds once for all of them, so every sketch is a one-file compile. That is why the generator joins a package you are already inside instead of making another one. It does that whenever the folder you point at sits inside a Swift package that depends on Ollin:

```sh
cd sketchbook/2026/08
ollin new Nightfall          # a sketch folder here, and one target in sketchbook/Package.swift
```

The generator tells you when it joins a package, and `--kind mac-sketch` overrides that for a project of its own. In the window, the kind menu gains **Add to this package** whenever there is one to join. The file list then names the manifest edit beside the files being created.

Joining a package is the only thing the generator does that changes a file you already had, so it is careful about it:

- It refuses a package that does not depend on Ollin yet, because a target added there could not import the framework.
- It inserts one target at the end of the existing `targets:` list. It matches that list's own brackets rather than the first `]` it finds.
- If it cannot read the target list with confidence, it leaves the manifest untouched. It writes the sketch and prints the stanza for you to paste.
- The target's `path:` points at wherever your folders actually put the sketch, so any layout works.

## What it starts from

A **template** is a small, complete sketch that already does something. The first thing you see is motion, rather than an empty `draw()`.

| Template | What it draws |
|---|---|
| `blank` | A circle breathing on white. |
| `motion` | A ring of dots orbiting, with their radius wandering on noise. |
| `pattern` | A grid where every cell decides its own mark, held still. |
| `shader` | A fragment shader of your own, run over every pixel. |
| `effects` | An off-screen layer, filtered on the GPU and composited back. |
| `3d` | A lit solid on a ground plane, with the camera drifting around it. |
| `plotter` | Pen-ready line work on A4, made to be saved as an SVG. |
| `camera` | The webcam as live material, ready for a tracker. |
| `sound` | Bars driven by what the microphone hears. |
| `physics` | A pile of discs settling under gravity. |

A template brings in the libraries its own code needs, so picking `camera` links the vision library without you asking for it.

## Or start from an example

The examples are the largest body of working Ollin code there is, and you can start from any of them:

```sh
ollin new --examples                       # every one, grouped as they are filed
ollin new MyPiece --from Patterns/Marbling
```

The copy is yours. The generator renames the type after your project and links the libraries the sketch imports. It copies everything the sketch loads in beside it and declares it, whether that is a picture, a mesh, a shader, or a clip. So the copy builds and runs before you have changed a line.

The one thing the generator does *not* change is the file's header comment. For a ported sketch or a homage, that comment is where the credit lives, so it travels with the code. Keep it there if you keep the lineage, and rewrite it when the piece has become yours.

## The 3D options

3D is the one part of the framework where the pieces do not all combine. You cannot tell the rule from the call itself. A matcap silently replaces the lighting you set. Traced reflections silently do nothing without an environment. A wireframe has no surface to shade at all. The generator shows you that map, instead of leaving you to find out by rendering.

Pick the `3d` template and a strip appears **under the stage it governs**, laid out along the direction of the constraint. First comes **Geometry**, which is what is on screen. Next comes **Finish**, which is how its surface is done. Last comes **On top**, which holds everything added over both. The three run left to right, with arrows between them. That reading order is the rule. What sits left of a thing can block it, and what sits right cannot. So you can see the shape of the constraint before you click anything.

A blocked chip is dimmed, marked, and **names its cause** on the chip itself. The choice doing the blocking reports how far it reaches (`blocks 3`). Hover any chip, blocked or not, and the line under the strip explains it.

```sh
ollin new --3d-options                  # every piece and the rule it carries
ollin new MyPiece --template 3d --3d mesh,pbr,environment,shadows,ray-traced,tone-map
```

The rules are a hierarchy, which is what keeps the panel easy to move around in. **Geometry is never blocked**. Picking a wireframe settles the finish and drops whatever a wireframe cannot take, rather than refusing the click. What gets refused is a finish its geometry has no surface for, or an extra that its geometry or finish rules out.

That last command is the realism stack from [Combining 3D features](../3D/Combining.md), the page that holds the full map in prose. If the two ever disagree, that page is right and the generator has the bug.

## Naming

If you give no name, the generator uses a dated serial. It writes `Sketch2026001`, then `002`, counting past the highest one already in the folder. That highest one can be a project folder or a loose file.

```sh
ollin new                  # Sketch2026001.swift, then Sketch2026002.swift
ollin new --kind mac-sketch  # the same name, as a folder
```

Serials exist because naming a piece before you make it is the wrong order. They also make a folder sort by when you made things. Give a name whenever you have one.

## What else to wire in

`--with` adds anything else, and it is the **Wire in** column in the window. It can add a folder to keep pictures or fonts in, a `.metal` file for a shader, or any of the satellite libraries. Each one adds its `import`, its manifest entry, the folder it loads from, and one commented line in `setup()` that shows the first call. That line stays a comment, so a freshly made sketch always runs.

```sh
ollin new Listening --with audio,images,params
```

## The window

`ollin generate` opens the same choices, and adds one thing the terminal cannot. The starting point in the middle is **actually running**. It is compiled and instantiated exactly as the examples gallery compiles an example, so what you watch is what you get. A starting point that stopped compiling shows up there, rather than in your new project.

The window has three columns, and it resizes. The stage takes the extra space, because watching the sketch run is the reason to open a window rather than type the command.

**Left, one list.** The templates sit as a group at the top. The examples come below them, grouped the way the folders already group them. One filter runs over both, and it matches group names as well as sketch names. The ten curated starting points and the 350 cataloged ones are a short list and a long one, not two modes.

**Middle, the stage.** The starting point runs here. A line under it says what the sketch is, how fast it is going, and whether it was just built or came from the cache. For the 3D template, the options strip sits under that line (see below). For an extension package, the stage shows source instead (see [below](#an-extension-package-in-the-window)).

**Right, the project.** Name, destination, canvas, and everything else behind one **Wire in** row that still reports what the starting point brought. The file list sits above the fold, with the no-overwrite guarantee under it. Nothing is written until you press Create, and Create refuses to overwrite a file that is already there.

The window remembers the folder you last chose. The name field *suggests* the next serial in that folder, rather than filling it in. So you make several in a row with Create, Create, Create, and you name one properly by typing over the suggestion.

The kind menu lives in the title bar, because it applies to the whole window. The kinds that are not ready sit under a divider inside it, dimmed, and each one shows what it waits on.

### An extension package in the window

Pick **Extension package** in that menu and the window changes shape, because a library has nothing to run.

The list on the left holds the four seams instead of the templates. The stage shows the starter's source instead of a frame, colored and selectable. A strip under the stage switches between the files that will be written. Type a name and the file on the stage renames itself as you type, because what you see is the plan itself.

The starter is checked against the framework on this machine, the way a sketch is compiled. The chip in the title bar says **Compiles** once that check passes. A seam that stopped compiling shows its log over the source, before you press Create. The canvas and the wiring controls go away, because a library declares neither.

`ollin generate --kind extension --seam filter` opens the window already set to a seam.

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

Run it with `swift run MyPiece` from inside the folder. To edit it and see each save land without the window closing, open the same file through the live host instead:

```sh
ollin Sources/MyPiece/Sketch.swift
```

Everything the sketch loads lives beside it in `Sources/MyPiece/`. A folder the generator made is already declared in the manifest. A picture you drop into `Images/` is then reachable by name, with no manifest edit:

```swift
let picture = loadImage(resource: "photo", withExtension: "jpg", in: .module)
```

## Where the framework comes from

A generated manifest points by path at the copy of Ollin the generator was run from. The project then builds straight away, with nothing to fetch. Two flags change that:

```sh
ollin new MyPiece --remote                      # point at the published framework
ollin new MyPiece --framework-path ~/dev/Ollin  # point at a particular copy
```

The path form is the right default on a machine that has the framework, because the project builds with nothing to fetch. Switch to `--remote` for a project you mean to hand to someone who does not have that folder. The manifest then pins the newest tagged release and stays on that minor, because a pre-1.0 minor can break.

## Every option

| Flag | What it does |
|---|---|
| `--kind <id>` | What to make. Defaults to `mac-sketch`, or `single-file` for a `.swift` name. |
| `--template <id>` | Which starting point. Defaults to `blank`. |
| `--from <Group/Name>` | Start from an example instead, with everything it loads. |
| `--examples` | Print every example that can be started from. |
| `--with <a,b>` | Extra libraries and folders. |
| `--canvas <id>` | The canvas size to declare (`a4`, `fhd1080`, `vertical1080`, and the rest). |
| `--seam <id>` | What an extension package is built on, with `--kind extension`. Defaults to `draw-call`. |
| `--team <id>` | The Apple Developer team an iOS app is signed under, with `--kind ios-app`. Defaults to `OLLIN_TEAM`; left off, Xcode asks. |
| `--in <dir>` | Where to put it. Defaults to the current folder. |
| `--remote` | Point the manifest at the published framework. |
| `--framework-path <dir>` | Point it at a particular copy of the framework. |
| `--list` | Print every kind, template, seam, and extra. |

## Adding to it

The catalogs are data. A new template is one value in `ProjectTemplate.all`, carrying its source, the capabilities its code needs, and the kinds it fits. A new capability is one value in `Capability.all`. A new kind is one value in `ProjectKind.all` plus an emitter. The test suite compiles every template against the framework. A template that falls behind an API change fails there, rather than in someone's new project.

Two of the lists keep themselves up to date and one does not, which is worth knowing:

- **The examples list is discovered**, not declared. Anything under `Examples/` with a `Sketch.swift` appears, grouped by the folders it sits in. The libraries it links come from its own `import` lines. Ship an example and it is a starting point, with nothing to register. A library the capability list has never heard of is still linked, so a new satellite works the day it lands. The scan runs at launch, so a folder added while the window is open needs a relaunch.
- **The 3D options are hand-kept**, because they map which features combine rather than list what exists. Only a person can say that. They mirror [Combining 3D features](../3D/Combining.md), so a 3D capability that changes what combines with what updates both. Once an option is added, the test suite compiles every combination the rules allow, so a rule that permits something impossible fails there.

## See also

- [Single-file sketches](SingleFile.md) for the loose-file workflow the `single-file` kind produces.
- [Live coding](LiveCoding.md) for the performance host.
- [Export](../Output/Export.md) for everything a finished sketch can be turned into.
