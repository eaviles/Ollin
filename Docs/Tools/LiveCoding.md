#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Tools](./README.md) → `Live coding`</sup>

---

## Live coding

OllinLiveCoding is a performance instrument. One window holds the running sketch on the stage, and your code rides over it as translucent text, so writing the sketch *is* the show. You edit the full Ollin sketch in Swift, not a constrained shader DSL. Any drawing, effect, 3D scene, or `Visual` chain the framework offers is available. Then you evaluate on command. ⌘↩ recompiles the buffer and hot-swaps the sketch, while the previous one keeps drawing. The clock carries across the swap, so motion never jumps mid-set.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/31-SharingAndPerforming/StageDiagram-dark.jpg">
  <img src="../../Guide/Images/31-SharingAndPerforming/StageDiagram.jpg" alt="An annotated diagram of the performance host: a dark window with a posterized visual filling the stage, code lines riding over it on translucent strips, an Evaluated toast, and callouts naming each part" width="680">
</picture>

```sh
swift run OllinLiveCoding                                     # untitled buffer, starter sketch
swift run OllinLiveCoding Examples/Basic/HelloCircle/Sketch.swift
Scripts/OllinLiveCoding                                       # release build (performance speed)
```

`Scripts/OllinLiveCoding` builds the host in release mode, which is what a live set wants. Evaluations stay quick either way, because only the sketch recompiles and never the host. Release mode is what makes the framework render at full speed.

It is a sibling of `OllinLive`, not a replacement. OllinLive watches a file you edit in your own editor, which is the development loop. OllinLiveCoding is the on-stage instrument, with the editor inside the window.

### Contents

- [The evaluate loop](#the-evaluate-loop) - ⌘↩, ⌘⇧↩, and what carries across a swap
- [Errors during a set](#errors-during-a-set) - the diagnostics strip
- [Files, saving, and recovery](#files-saving-and-recovery) - evaluate never saves
- [Performance chrome](#performance-chrome) - hide code, fullscreen, the inspector
- [Keyboard reference](#keyboard-reference)

---

### The evaluate loop

Type, then press **⌘↩ (Sketch ▸ Evaluate)**. The buffer compiles in the background (the running sketch never pauses), and on success the fresh sketch swaps in:

- **The clock carries.** `time` and `frameCount` continue across the swap, so a phase-driven animation does not snap. Use **⌘⇧↩ (Evaluate Fresh)** to reset the clock instead, when you want the piece to start over.
- **Tuned knobs carry.** A `@Param` value you dragged in the inspector (or bound over MIDI/OSC) is re-applied to the fresh sketch before it draws. Untouched params take whatever default the code now declares, so editing a default in source still works.
- **Instance state resets.** It's a fresh instance: `setup()` runs again, stored properties re-initialize, and the accumulation surface clears. `reloaded()` fires after the post-swap `setup()` if you need a hook.
- A compile takes a second or two, because Swift compiles rather than evals. The amber chip in the corner shows a compile in flight. A green "Evaluated" toast confirms the swap, with the build time.

Evaluation compiles the buffer exactly as it is on screen, unsaved changes included.

### Errors during a set

A typo never interrupts the show. The last good sketch keeps playing undimmed. The mistake shows as a compact strip along the bottom, one row per compiler error with its line number. The offending lines tint red in the editor. Click a row to jump the caret there, fix, and ⌘↩ again.

A user shader that fails to compile (an inline `Shader` or a `.metal` resource) reports through the same strip, at its real file and line. The two error kinds are independent. A fix to the Swift error does not hide a shader error, and the reverse is also true.

### Files, saving, and recovery

The `.swift` file is the artifact, and only you write it:

- **Evaluate never saves.** ⌘↩ compiles the in-memory buffer, so you can riff live without touching the file on disk.
- **Saving is explicit.** **⌘S** saves, **⌘⇧S** saves a copy elsewhere, **⌘N** starts a fresh untitled buffer, and **⌘O** opens any sketch file. A new buffer opens on the starter sketch, and the window's title dot shows unsaved changes.
- **A crash loses nothing.** The buffer autosaves to a recovery net on every evaluation (and periodically while dirty). If the app dies mid-set, the next launch of the *same* document offers to restore the recovered buffer. A clean save clears the net.

A sketch's co-located assets (an image or `.metal` file beside the `.swift`) resolve relative to the open file's folder, same as under `OllinLive`. An untitled buffer has no folder yet, so save it first if it needs assets. An edited co-located `.metal` is picked up on the next ⌘↩.

### Performance chrome

- **Hide Code (⌃⇧H)** blanks the editor for a code-free stretch, and the visuals keep the whole stage. While the code is hidden, a click on the canvas hands the sketch the keyboard, which interactive sketches need. Show the code again, and the keyboard returns to the editor.
- **Fullscreen (⌃⌘F)** is the projection mode. Fullscreen the window on the projector, or mirror your display. The canvas letterboxes to its true aspect on the black stage at any window shape.
- **Bigger/Smaller Code (⌘+ / ⌘−)** sizes the type for the room. Use **View ▸ Code Backdrop** to set how dark the strip behind the text reads over bright visuals.
- **The inspector (⌘/)** docks on the right, hidden by default. It is the rehearsal and soundcheck surface, with a live monitor card (FPS, frame time, geometry counts). Under the card comes a control per `@Param`, which is a slider, a stepper, a toggle, a menu, or a color well. **Save to the code** writes the knobs you turned into their own `@Param` lines in the buffer, so what the room reads is what it sees. It changes the text on the stage and nothing else, and ⌘S still decides what reaches the disk. See [saving what you turned](../Helpers/Parameters.md#saving).
- The **Camera menu** (⌘0-⌘8) works on any 3D sketch, same as in the other hosts.
- **Record (⌘⇧R)** keeps the set as a movie, picture and the sketch's own sound, written in real time to `~/Movies/Ollin/`. A red chip counts the take on the stage, a toast names the file when it is saved, and the recording plays straight through every evaluate. See [Recording](../Output/Recording.md).

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
