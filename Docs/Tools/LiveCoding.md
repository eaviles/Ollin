#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Tools](./README.md) → `Live coding`</sup>

---

## Live coding

OllinLiveCoding is a performance instrument: one window where the running sketch fills the stage and your code rides over it as translucent text, so writing the sketch *is* the show. You edit the full Ollin sketch in Swift (any drawing, effects, 3D, or `Visual` chain the framework offers, not a constrained shader DSL) and evaluate on command: ⌘↩ recompiles the buffer and hot-swaps the sketch while the previous one keeps drawing. The clock carries across the swap, so motion never jumps mid-set.

```sh
swift run OllinLiveCoding                                     # untitled buffer, starter sketch
swift run OllinLiveCoding Examples/Basic/HelloCircle/Sketch.swift
Scripts/OllinLiveCoding                                       # release build (performance speed)
```

`Scripts/OllinLiveCoding` builds the host in release mode, which is what a live set wants: evaluations stay quick either way (only the sketch recompiles, never the host), but the framework renders at full speed.

It is a sibling of `OllinLive`, not a replacement: OllinLive watches a file you edit in your own editor (the development loop), while OllinLiveCoding is the on-stage instrument with the editor inside the window.

### Contents

- [The evaluate loop](#the-evaluate-loop) - ⌘↩, ⌘⇧↩, and what carries across a swap
- [Errors during a set](#errors-during-a-set) - the diagnostics strip
- [Files, saving, and recovery](#files-saving-and-recovery) - evaluate never saves
- [Performance chrome](#performance-chrome) - hide code, fullscreen, the inspector
- [Keyboard reference](#keyboard-reference)

---

### The evaluate loop

Type, then press **⌘↩ (Sketch ▸ Evaluate)**. The buffer compiles in the background (the running sketch never pauses), and on success the fresh sketch swaps in:

- **The clock carries.** `time` and `frameCount` continue across the swap, so a phase-driven animation doesn't snap. **⌘⇧↩ (Evaluate Fresh)** resets the clock instead, for when you want the piece to start over.
- **Tuned knobs carry.** A `@Param` value you dragged in the inspector (or bound over MIDI/OSC) is re-applied to the fresh sketch before it draws. Untouched params take whatever default the code now declares, so editing a default in source still works.
- **Instance state resets.** It's a fresh instance: `setup()` runs again, stored properties re-initialize, and the accumulation surface clears. `onReload()` fires after the post-swap `setup()` if you need a hook.
- A compile takes a second or two (Swift compiles rather than evals); the amber chip in the corner shows one is in flight, and a green "Evaluated" toast confirms the swap with the build time.

Evaluation compiles the buffer exactly as it is on screen, unsaved changes included.

### Errors during a set

A typo never interrupts the show. The last good sketch keeps playing undimmed; the mistake shows as a compact strip along the bottom, one row per compiler error with its line number, and the offending lines tint red in the editor. Click a row to jump the caret there, fix, and ⌘↩ again.

A user shader that fails to compile (an inline `Shader` or a `.metal` resource) reports through the same strip, at its real file and line. The two error kinds are independent: fixing the Swift error doesn't hide a shader error, and vice versa.

### Files, saving, and recovery

The `.swift` file is the artifact, and only you write it:

- **Evaluate never saves.** ⌘↩ compiles the in-memory buffer, so you can riff live without touching the file on disk.
- **⌘S saves**; **⌘⇧S** saves a copy elsewhere; **⌘N** starts a fresh untitled buffer from the starter sketch; **⌘O** opens any sketch file. The window's title dot shows unsaved changes.
- **A crash loses nothing.** The buffer autosaves to a recovery net on every evaluation (and periodically while dirty). If the app dies mid-set, the next launch of the *same* document offers to restore the recovered buffer; a clean save clears the net.

A sketch's co-located assets (an image or `.metal` file beside the `.swift`) resolve relative to the open file's folder, same as under `OllinLive`. An untitled buffer has no folder yet, so save it first if it needs assets. An edited co-located `.metal` is picked up on the next ⌘↩.

### Performance chrome

- **Hide Code (⌃⇧H)** blanks the editor for a code-free stretch; the visuals keep the whole stage. While the code is hidden, a click on the canvas hands the sketch the keyboard (for interactive sketches); showing the code again returns it to the editor.
- **Fullscreen (⌃⌘F)** is the projection mode: fullscreen the window on the projector, or mirror your display. The canvas letterboxes to its true aspect on the black stage at any window shape.
- **Bigger/Smaller Code (⌘+ / ⌘−)** sizes the type for the room; **View ▸ Code Backdrop** sets how dark the strip behind the text reads over bright visuals.
- **The inspector (⌘/)** docks on the right with the live monitor card (FPS, frame time, geometry counts) and a control per `@Param` (slider, stepper, toggle, menu, color well), a rehearsal and soundcheck surface, hidden by default.
- The **Camera menu** (⌘0–⌘8) works on any 3D sketch, same as in the other hosts.

### Keyboard reference

| Keys | Action |
| --- | --- |
| ⌘↩ | Evaluate the buffer (clock carries) |
| ⌘⇧↩ | Evaluate fresh (clock resets) |
| ⌘N / ⌘O | New untitled buffer / open a sketch file |
| ⌘S / ⌘⇧S | Save / save as |
| ⌃⇧H | Hide or show the code |
| ⌃⌘F | Enter or leave fullscreen |
| ⌘+ / ⌘− | Bigger / smaller code |
| ⌘/ | Show or hide the inspector |
| ⌘0–⌘8 | Camera views (3D sketches) |
