#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Tools](./README.md) → `Live coding`</sup>

---

## Live coding

OllinLiveCoding is a host for live performance. One window holds the running sketch on a stage, and your code sits over it as translucent text. The audience watches you write the sketch. You edit a full Ollin sketch in Swift, not a limited shader language. Any drawing, effect, 3D scene, or `Visual` chain the framework offers is available. You evaluate when you choose to. ⌘↩ recompiles the buffer and swaps the new sketch in. The previous sketch keeps drawing until the swap happens. The clock carries across the swap, so motion never jumps in the middle of a set.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/31-SharingAndPerforming/StageDiagram-dark.jpg">
  <img src="../../Guide/Images/31-SharingAndPerforming/StageDiagram.jpg" alt="An annotated diagram of the performance host: a dark window with a posterized visual filling the stage, code lines riding over it on translucent strips, an Evaluated toast, and callouts naming each part" width="680">
</picture>

```sh
swift run OllinLiveCoding                                     # untitled buffer, starter sketch
swift run OllinLiveCoding Examples/Basic/HelloCircle/Sketch.swift
Scripts/OllinLiveCoding                                       # release build (performance speed)
```

`Scripts/OllinLiveCoding` builds the host in release mode, which is what you want for a live set. Evaluations are quick either way, because each one recompiles the sketch and never the host. Release mode changes the speed the framework itself renders at. The buffer compiles optimized on every evaluation, whichever way the host was built, and it lands in two speeds: a plain build goes on stage the moment it compiles, and the optimized build replaces it when it is ready. A sketch that moves fifty thousand points on the CPU each frame therefore runs at the speed a release build gets, a moment after the edit shows. [The evaluate loop](#the-evaluate-loop) has the numbers. `--no-optimize` compiles the buffer plain instead, which helps when you are debugging the sketch rather than performing it. Under that build, asserts fire and a crash names every frame. `--single-build` keeps the optimized compile and waits for it alone, for a sketch that should not start over twice.

OllinLiveCoding sits beside `OllinLive` rather than replacing it. OllinLive watches a file you edit in your own editor, which is the development loop. OllinLiveCoding is the performance host, and its editor is inside the window.

### Contents

- [The evaluate loop](#the-evaluate-loop) - ⌘↩, ⌘⇧↩, and what carries across a swap
- [What the edit changed](#what-the-edit-changed) - when the run carries on instead of starting over
- [Completing a name](#completing-a-name) - the list under the caret, and the placeholders it leaves
- [Errors during a set](#errors-during-a-set) - the diagnostics strip
- [Files, saving, and recovery](#files-saving-and-recovery) - evaluate never saves
- [Performance chrome](#performance-chrome) - hide code, fullscreen, the inspector
- [Dragging a shape on the stage](#dragging-a-shape-on-the-stage) - Command-drag through the code
- [The host on a controller](#the-host-on-a-controller) - evaluate, hide the code, and record from MIDI or OSC
- [Keyboard reference](#keyboard-reference)

---

### The evaluate loop

Type your edit, then press **⌘↩ (Sketch ▸ Evaluate)**. The buffer compiles in the background, so the running sketch never pauses. On a successful compile the new sketch swaps in:

- **The clock carries.** `time` and `frameCount` continue across the swap, so an animation driven by phase does not jump. Use **⌘⇧↩ (Evaluate Fresh)** instead when you want the piece to start over, because that resets the clock.
- **Tuned parameters carry.** A `@Param` value you dragged in the inspector is applied again before the new sketch draws. A value bound over MIDI or OSC carries the same way. A parameter you did not touch takes whatever default the code now declares, so editing a default in the source still works.
- **The run carries on when it can.** If the edit moved nothing but the inside of a method, and left `setup()` alone, the piece keeps going: `setup()` does not run again, the canvas keeps whatever is piled on it, and the state you marked `@Saved` comes across. Anything else starts the run over, which is what a swap has always done. [What the edit changed](#what-the-edit-changed) has the whole rule.
- **Two speeds.** The buffer compiles twice at once, plain and optimized, because Swift compiles the code rather than evaluating it directly. The plain build swaps in the moment it compiles, and the optimized build replaces it when it is ready, with the clock carried across that second swap too. An amber chip in the corner reads "Compiling…" until the code is on stage, then "Optimizing…" until the optimized build lands. A green "Evaluated" toast confirms the first swap and gives its time.

Evaluation compiles the buffer exactly as it is on screen, unsaved changes included.

What the second speed buys is the optimizer's share of the compile, which grows with the sketch. The rest is fixed, whatever the file holds: the compiler loads the framework's module and links. Measured on an M2, from the evaluation to the swap:

| Sketch | Plain build on stage | Optimized build in | One optimized build (`--single-build`) |
| --- | --- | --- | --- |
| 20 lines | 0.63 s | 0.68 s | 0.60 s |
| 150 lines | 0.68 s | 0.84 s | 0.76 s |
| 470 lines | 0.78 s | 1.16 s | 1.09 s |

On a small sketch the two builds land together, and the mode costs a few hundredths. On a sketch the size a set grows into, the edit shows about a third sooner than the optimized build alone would show it. That build arrives a few hundredths later than it would alone, since the two compiles share the machine.

Both swaps of one evaluation do the same thing to the run, since they are the same code: an edit that carries the run carries it across both, and an edit that starts it over starts it over twice, a fraction of a second apart. That second case is what `--single-build` is for. Run the host that way and every evaluation waits for the one optimized build.

### What the edit changed

A swap always brings a fresh instance, because the code lives in a new library and there is no way to keep the old object and change what its methods do. What *can* be kept is everything the running instance had become. So each evaluation is read against the text the stage was built from, and the answer decides what the swap does to the run.

**The run carries on** when nothing but the inside of a method moved. Then:

- `setup()` does not run again, so the background it paints does not wipe the canvas.
- The canvas keeps what is piled on it, which is the whole point for a piece drawn with `noClear()`.
- `time` and `frameCount` go on, as they do across any swap.
- `random()` and the noise fields carry on where they were, rather than restarting their sequence.
- The `@Saved` properties come across, matched by name. This is the same mark that carries state across a relaunch, so one annotation covers both.
- The extensions the sketch installed for itself and the automation it wrote come across, since the `extend` and `automate` calls that made them are not going to run again.
- `reloaded()` fires, as it does after any swap.
- Everything else is a fresh instance's declared value: a stored property you did not mark is back where the file puts it.

**The run starts over** in every other case, exactly as it always did. The cases:

- A declaration changed: a property added, removed, renamed, retyped, or given a different initial value; a signature changed; a type renamed.
- `setup()` itself changed, or anything `setup()` calls, however far down. Editing `setup()` is asking for `setup()` to run, and a swap that skips it could never show that.
- `setup()` builds state the swap cannot carry: it names a stored property that is not `@Saved`. A sketch whose particles are made in `setup()` would come back with none of them, so it restarts instead.
- ⌘⇧↩, the first evaluation of a session, and the first after opening another file.

Whitespace, comments and a rewrapped signature are not declaration changes, so writing a note above `draw()` costs nothing.

The green toast names what happened: the block that ran, or "restarted". The editor lights the block the caret was standing in when you pressed ⌘↩, which is where you were working; the whole buffer still compiles, and the whole instance is still replaced.

**To keep more across an edit**, mark it `@Saved`:

```swift
final class Field: Sketch {
    @Saved var walkers: [Vector2] = []

    override func setup() {
        noClear()
        background(.black)
    }

    override func draw() {
        if walkers.isEmpty { walkers = (0..<200).map { _ in Vector2(random(width), random(height)) } }
        ...
    }
}
```

Anything `Codable` can be saved. What cannot is anything living on the GPU, which is why the canvas is carried separately. Note where the walkers are built: filling them in `draw()` rather than `setup()` is what lets the edit carry the run, since `setup()` then names nothing the swap would lose.

### Completing a name

Type the first letters of a name and a list opens under the caret. It holds what the Swift toolchain's own completion service knows at that point: every drawing call on `Sketch`, every value type and its members, and the properties and methods the buffer itself declares. Type more to narrow the list. Up and Down move through it, and Return or Tab takes the row. A call lands with its arguments as placeholders, the first one selected, so what you type replaces it. Tab moves to the next placeholder, and wraps to the first when it reaches the end. A member dot opens the same list: `Color.` lists the palette, and `background(.white)` starts from the same list after its dot, because the call wants a color.

Escape closes the list, and opens it when it is closed. Escape never leaves fullscreen, so a stray press mid-set costs nothing; ⌃⌘F is how the stage leaves it. **View ▸ Complete as You Type** turns the automatic list off, for a set where the code should stay still until you ask. Escape and **Sketch ▸ Complete Name** open it either way. The list takes only the keys it uses, so a space, a bracket, or a comma goes into the code as typed and closes it.

The names come from a check of the buffer against the framework, the same modules ⌘↩ compiles against, which is why the list knows the framework by name whatever the file is called and wherever it lives. A placeholder left in the code is an error on its own line at the next evaluation, reported in the strip like any other error, so nothing is silently wrong. The first list of a session takes a moment while the service reads the framework, and the host pays that in the background at launch. After that a new word answers in a few milliseconds, and narrowing it in about one.

### Errors during a set

A typo never interrupts the show, because the last sketch that compiled keeps playing and the stage is never dimmed. The mistake shows in a small strip along the bottom, one row per compiler error with its line number. The lines at fault turn red in the editor. Click a row to move the caret there, fix the line, then press ⌘↩ again.

A user shader that fails to compile reports through the same strip, at its own file and line. The shader can be an inline `Shader` or a `.metal` resource. The two kinds of error are independent. Fixing the Swift error does not hide a shader error, and fixing the shader error does not hide a Swift one.

### Files, saving, and recovery

The `.swift` file is the artifact, and nothing writes it but you:

- **Evaluate never saves.** ⌘↩ compiles the buffer in memory, so you can improvise during a set without changing the file on disk.
- **Saving is explicit.** **⌘S** saves, **⌘⇧S** saves a copy elsewhere, **⌘N** starts a fresh untitled buffer, and **⌘O** opens any sketch file. A new buffer starts on the starter sketch, and a dot in the window title marks unsaved changes.
- **A crash loses nothing.** The buffer saves itself to a recovery file on every evaluation. It saves again at intervals while it has unsaved changes. If the app stops during a set, the next launch of the *same* document offers to restore what it recovered. A clean save clears the recovery file.

Assets that sit beside the `.swift` file, such as an image or a `.metal` file, resolve against the open file's folder. `OllinLive` resolves them the same way. An untitled buffer has no folder yet, so save it first if the sketch needs assets. A `.metal` file you edit beside the sketch is picked up on the next ⌘↩.

### Performance chrome

- **Hide Code (⌃⇧H)** blanks the editor, so the visuals have the whole stage for a stretch. While the code is hidden, a click on the canvas gives the sketch the keyboard, which is what an interactive sketch needs. Show the code again and the keyboard returns to the editor.
- **Fullscreen (⌃⌘F)** is the projection mode. Put the window fullscreen on the projector, or mirror your display. Whatever shape the window takes, the canvas letterboxes to its true aspect on the black stage.
- **Bigger/Smaller Code (⌘+ / ⌘−)** sets the type size for the room. Use **View ▸ Code Backdrop** to set how dark the strip behind the text looks over bright visuals.
- **The inspector (⌘/)** docks on the right and is hidden by default. Use it to rehearse and to check the sketch before a set. At the top is a live monitor card with the frame rate, the frame time, and the geometry counts. Under the card is one control per `@Param`. The control is a slider, a stepper, a toggle, a menu, or a color well. The **Save parameters to the code** button writes the parameters you adjusted into their own `@Param` lines in the buffer. The code the room reads then matches what it sees. That changes the text on the stage and nothing else, and ⌘S still decides what reaches the disk. See [saving what you turned](../Helpers/Parameters.md#saving).
- The **Camera menu** (⌘0-⌘8) works on any 3D sketch, the same as it does in the other hosts.
- **Record (⌘⇧R)** keeps the set as a movie, with both the picture and the sketch's own sound, written in real time to `~/Movies/Ollin/`. A red chip on the stage counts the take, a toast names the file when it is saved, and the recording continues through every evaluation. See [Recording](../Output/Recording.md).

### Dragging a shape on the stage

Hold Command over the stage, and the shape under the pointer is outlined through the text, with the line that drew it named above the outline. Drag the shape to move it, pull a corner to resize it, or turn the knob above it, and the numbers on that line change in the code on the stage. The host evaluates the buffer for you, the way ⌘↩ does, so the shape stays where you left it after the swap. With a shape outlined, `⌘]` and `⌘[` move its line past its neighbor's, so it draws in front or behind. Nothing here writes the file, so ⌘S still decides what reaches the disk, and ⌘Z in the editor takes a drag back.

The drag edits the text the stage was built from and nothing else. If you have typed since the last evaluation, a drag asks you to evaluate first rather than guess where the line went. See [Dragging a shape](./DragToEdit.md) for what each handle writes and what it refuses.

### The host on a controller

A performer's hands are often on a controller rather than the keyboard, and a second machine may be running the show. The host's own actions answer to MIDI and OSC, beside the `@Param` bindings a sketch makes for itself. This is a host preference and never part of the sketch. The sketch reads its own inputs, and the host reads its own.

**OSC** answers at fixed addresses once a port is set. Open the inspector (⌘/), find the **Controls** card, and type a port. From then on the host listens there:

| Address | What it does |
| --- | --- |
| `/ollin/evaluate` | evaluate the buffer, the way ⌘↩ does |
| `/ollin/evaluate/fresh` | evaluate fresh, with the clock reset |
| `/ollin/code/hidden` | a bare message turns the code over; `1` hides it and `0` shows it |
| `/ollin/code/backdrop` | the strip behind the text, `0` to `1` |
| `/ollin/code/size` | the type size, `0` to `1` across 9 to 32 points |
| `/ollin/record` | a bare message starts or stops a take; `1` and `0` say which |
| `/ollin/cue` | call a [cue](../Helpers/Cues.md) by name (`"night"`) or by number; a second argument sets that call's fade in seconds |
| `/ollin/cue/next`, `/ollin/cue/previous` | step to the next or the previous cue, over the Cues card's fade |

A button in a layout sends its release as well as its press, and only the press counts. Leave the port empty and the host listens to nothing.

A MIDI **program change** calls the cue of that number, on any channel, with nothing to learn; **Next cue** and **Previous cue** are press actions on the Controls card, learned like the others.

**MIDI** has no natural default for a pad, so a control is learned. In the Controls card, press the Learn button on the action, then press the pad or the button, or move the fader. The next control to arrive is the binding. It shows on the row and holds across launches. A pad or key fires an action once per press, on its own channel. A button on a controller sends 127 pressed and 0 released, so it fires once on the way up. A knob or fader rides the backdrop or the code size, and refuses the press actions. The same Learn button binds an OSC address, for a layout that already has its own names. The minus button forgets a control, and a control learned for one action leaves any other it was on.

The card's last line says what the host hears: the OSC port it is listening on, and how many MIDI sources the Mac sees. The sketch side of the same two wires is in [MIDI](../Integration/MIDI.md) and [OSC](../Integration/OSC.md).

### Keyboard reference

| Keys | Action |
| --- | --- |
| ⌘↩ | Evaluate the buffer (clock carries) |
| ⌘⇧↩ | Evaluate fresh (clock resets) |
| Esc | Open the completion list at the caret, or close it |
| ↑ / ↓, then ↩ or ⇥ | Move through the completion list, then take the row |
| ⇥ | Move to the next placeholder, when no list is open |
| ⌘N / ⌘O | New untitled buffer / open a sketch file |
| ⌘S / ⌘⇧S | Save / save as |
| ⌃⇧H | Hide or show the code |
| ⌘-drag on the stage | Move the shape under the pointer, a corner to resize it, the knob to turn it; the code changes and evaluates |
| ⌘] / ⌘[ | Bring the outlined shape forward or send it back (Shift: all the way) |
| ⌘⇧R | Start or stop recording the set |
| ⌃⌘F | Enter or leave fullscreen |
| ⌘+ / ⌘− | Bigger / smaller code |
| ⌘/ | Show or hide the inspector |
| ⌘0-⌘8 | Camera views (3D sketches) |
