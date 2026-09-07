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

`Scripts/OllinLiveCoding` builds the host in release mode, which is what you want for a live set. Evaluations are quick either way, because each one recompiles the sketch and never the host. Release mode changes the speed the framework itself renders at. The buffer compiles optimized on every evaluation, whichever way the host was built. A sketch that moves fifty thousand points on the CPU each frame therefore runs at the speed a release build gets. `--no-optimize` compiles the buffer plain instead, which helps when you are debugging the sketch rather than performing it. Under that build, asserts fire and a crash names every frame.

OllinLiveCoding sits beside `OllinLive` rather than replacing it. OllinLive watches a file you edit in your own editor, which is the development loop. OllinLiveCoding is the performance host, and its editor is inside the window.

### Contents

- [The evaluate loop](#the-evaluate-loop) - ⌘↩, ⌘⇧↩, and what carries across a swap
- [Errors during a set](#errors-during-a-set) - the diagnostics strip
- [Files, saving, and recovery](#files-saving-and-recovery) - evaluate never saves
- [Performance chrome](#performance-chrome) - hide code, fullscreen, the inspector
- [Keyboard reference](#keyboard-reference)

---

### The evaluate loop

Type your edit, then press **⌘↩ (Sketch ▸ Evaluate)**. The buffer compiles in the background, so the running sketch never pauses. On a successful compile the new sketch swaps in:

- **The clock carries.** `time` and `frameCount` continue across the swap, so an animation driven by phase does not jump. Use **⌘⇧↩ (Evaluate Fresh)** instead when you want the piece to start over, because that resets the clock.
- **Tuned parameters carry.** A `@Param` value you dragged in the inspector is applied again before the new sketch draws. A value bound over MIDI or OSC carries the same way. A parameter you did not touch takes whatever default the code now declares, so editing a default in the source still works.
- **Instance state resets.** The swap builds a new instance. `setup()` runs again, stored properties start from their initial values, and the accumulation surface clears. `reloaded()` fires after that `setup()` if you need a hook.
- A compile takes a second or two, because Swift compiles the code rather than evaluating it directly. An amber chip in the corner shows that a compile is running. A green "Evaluated" toast then confirms the swap and gives the build time.

Evaluation compiles the buffer exactly as it is on screen, unsaved changes included.

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
- **The inspector (⌘/)** docks on the right and is hidden by default. Use it to rehearse and to check the sketch before a set. At the top is a live monitor card with the frame rate, the frame time, and the geometry counts. Under the card is one control per `@Param`, and above the Save button a field that takes [a look in words](../Helpers/Tuning.md) on a Mac whose model is on. The control is a slider, a stepper, a toggle, a menu, or a color well. The **Save parameters to the code** button writes the parameters you adjusted into their own `@Param` lines in the buffer. The code the room reads then matches what it sees. That changes the text on the stage and nothing else, and ⌘S still decides what reaches the disk. See [saving what you turned](../Helpers/Parameters.md#saving).
- The **Camera menu** (⌘0-⌘8) works on any 3D sketch, the same as it does in the other hosts.
- **Record (⌘⇧R)** keeps the set as a movie, with both the picture and the sketch's own sound, written in real time to `~/Movies/Ollin/`. A red chip on the stage counts the take, a toast names the file when it is saved, and the recording continues through every evaluation. See [Recording](../Output/Recording.md).

### Keyboard reference

| Keys | Action |
| --- | --- |
| ⌘↩ | Evaluate the buffer (clock carries) |
| ⌘⇧↩ | Evaluate fresh (clock resets) |
| ⌘N / ⌘O | New untitled buffer / open a sketch file |
| ⌘S / ⌘⇧S | Save / save as |
| ⌃⇧H | Hide or show the code |
| ⌘⇧R | Start or stop recording the set |
| ⌃⌘F | Enter or leave fullscreen |
| ⌘+ / ⌘− | Bigger / smaller code |
| ⌘/ | Show or hide the inspector |
| ⌘0-⌘8 | Camera views (3D sketches) |
