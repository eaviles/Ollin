#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Tools](./README.md) → `Checking the machine`</sup>

---

# Checking the machine

Everything Ollin needs is either on this machine or it is not, and when it is not, the failure arrives somewhere else entirely. A shader library that will not compile reads as a window that never opens. A camera nobody granted reads as a black frame. A missing command reads as `command not found`, three directories from where the real problem is.

`ollin doctor` asks each question directly and puts the one line that fixes each answer beside it.

```sh
ollin doctor
```

```
  ok  The system: macOS 27.0
  ok  The Swift compiler: Swift 6.4
        /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc
  ok  The Metal device: Apple M2
        ray tracing, in software on this generation, so a traced frame costs more
        mesh shaders, which the strand fields are drawn with
        temporal scaling, so a sketch can render small and present large
  ok  The shader compiler: compiles on this device
  --  The ollin command: not on your PATH
        without it a sketch is run as: swift run OllinLive <file>
        fix: Scripts/ollin install
  --  Shell completions: not installed
        zsh completes the flags of every ollin command once they are
        fix: Scripts/ollin install
  ok  The camera: not asked for yet
        a sketch that reads a camera or runs the vision tier asks the first time it opens one
  ok  The microphone: allowed
  ok  The screen: allowed
```

`ok` is settled. `--` is worth knowing and nothing is waiting on it. `no` is something that would stop a sketch from running, and the command exits nonzero when there is one, so it can go in a script.

### Contents

- [What it asks](#what-it-asks)
- [Nothing here asks for a permission](#nothing-here-asks-for-a-permission)
- [Completions](#completions)
- [What the sketch itself declares](#what-the-sketch-itself-declares)

---

## What it asks

**The system.** Ollin builds against macOS 26 and later. Below that, nothing else in the report matters.

**The Swift compiler.** A sketch is compiled on every run and again on every save, so `swiftc` has to be findable. The report names the path it found. That is the fastest way to notice that `xcode-select` points at a toolchain you did not mean to use.

**The Metal device.** Its name, then the three things a sketch can ask of it that not every GPU has. Ray tracing, and whether it runs on dedicated hardware or in software. Mesh shaders, which the [strand fields](../3D/Strands.md) are drawn with. Temporal scaling, which lets a sketch [render small and present large](../3D/3D.md#temporal-upscaling). Each is said either way, so the report reads the same on a machine that has them and one that does not.

**The shader compiler.** Asked the only way that settles it, by compiling. Ollin builds its shader library from source when a sketch starts. So what matters is not whether a compiler is findable. It is whether that compile works. If it does not, the fix line names the component to download.

**The command.** Whether there is an `ollin` on your `PATH`, and whether it is this checkout's. Running one clone's command against another clone's sources is the confusing case this exists to name.

**Three permissions.** The camera, the microphone, and screen recording: the three the framework itself can read. Each is only a problem for a sketch that wants it, so a refusal is a note carrying the System Settings pane that undoes it.

## Nothing here asks for a permission

The three permission reads are the preflight forms, which report a decision already made. Running the report can never raise a dialog on somebody's screen. That matters: a doctor is the kind of thing people run on a machine that is projecting.

`not asked for yet` is the ordinary state on a fresh machine and is not a problem. The sketch that wants the camera asks the first time it opens one.

## Completions

zsh can complete the `ollin` command: its subcommands, and the flags of whichever one you are typing, each with the line that says what it does.

```
$ ollin piece.swift --export-<TAB>
--export-dxf       -- write a DXF for a cutter
--export-embroidery -- write a stitch file
--export-gif       -- write an animated GIF
--export-grid      -- write a contact sheet of seeds
...
```

`ollin install` puts them in place along with the command itself. It links the completion file into the first zsh completions folder your shell already reads. If there is none, it tells you what to add to your `~/.zshrc`.

```sh
Scripts/ollin install
```

Open a new shell afterwards, or reload zsh's completions where you are:

```sh
autoload -Uz compinit && compinit
```

The file is generated rather than kept by hand. A flag added to the framework reaches your prompt with a `git pull` and nothing to re-run. To put it somewhere yourself, print it:

```sh
ollin completions > ~/.zsh/completions/_ollin
```

## What the sketch itself declares

The doctor asks about the machine. The other half of the question is what a particular sketch expects. `--list-params` answers that one: every [`@Param`](../Helpers/Parameters.md) it declares, its kind, what it accepts, and what it holds right now.

```sh
ollin Rings.swift --list-params
```

```
7 parameters, as --param takes them

  radius  Double  120      20...300
  rings   Int     5        1...12
  paper   Color   #FFFFFF
  style   menu    dots     Dots, Rings, Mesh Lines
  sheet   menu    a4       A0, A1, A2, A3, A4, A5, A6, Letter, Legal, Tabloid
  rate    menu    24 fps   23.98 fps, 24 fps, 25 fps, 29.97 fps, 30 fps, 50 fps, 59.94 fps, 60 fps, 120 fps

  Paper
  grain   Double  0.35     0...1
```

The values are the ones the first frame would be drawn with. The listing runs the sketch's `setup()` first, and anything given beside it lands too. So `--list-params --param radius=200 --cue dusk` says what that run would hold, not what the file was written with.

Every value is printed in the spelling [`--param`](../Output/Export.md#setting-a-parameter-for-the-run) reads back, so a line can be pasted into a flag. That is exact for every kind but a color, which is said in hex and so comes back to the nearest eight-bit step. A parameter a [show-rule](../Helpers/Parameters.md#show-rules) is currently hiding says so rather than looking like a value nobody is reading.

---

### See also

- [Single-file sketches](./SingleFile.md): the rest of what the `ollin` command does
- [Parameters](../Helpers/Parameters.md): declaring the values a sketch exposes, and the controls they get
- [Export](../Output/Export.md#setting-a-parameter-for-the-run): setting one from the command line, the other half of the listing
- [Checking a shader](./ShaderCheck.md): the same idea for a `.metal` file you are editing on its own
