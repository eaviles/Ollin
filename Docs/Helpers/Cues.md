#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Helpers](./README.md) → `Cues`</sup>

---

## Cues: looks you can call back

A cue is one named set of every parameter's value, the look a piece was tuned to at some moment. You save one from the parameters as they stand and call it back later, at once or over a fade. A set of cues is how a performance moves between the looks it rehearsed, and how a still is rendered at a look that was saved rather than typed in.

```swift
saveCue("night")               // every @Param, as it stands, under a name
cue("night", over: 2)          // back to that look over two seconds
nextCue(over: 1)               // the one after the current, wrapping
```

### Contents

- [Saving and calling](#saving-and-calling)
- [What fades and what jumps](#what-fades-and-what-jumps)
- [The inspector's card](#the-inspectors-card)
- [A pad, a program change, an address](#a-pad-a-program-change-an-address)
- [The file](#the-file)
- [A cue on the command line](#a-cue-on-the-command-line)

---

### Saving and calling

`saveCue(_:)` reads every `@Param` the sketch declares and stores the values under the name. A name already in the sheet is replaced where it stands, and a new one goes at the end. `deleteCue(_:)` takes one out. `cueSheet` is the whole list, in order, and `currentCue` names the one called last.

`cue(_:over:)` calls one by name, `cue(_ index:over:)` by position counting from 0, and `nextCue(over:)` / `previousCue(over:)` step from the current one and wrap at the ends. Each returns `false` when there is nothing to call. With `over` at 0 the parameters jump. With seconds, they ease there, slow at both ends, and `isCueFading` is true until they arrive. A cue called while another is still fading starts from wherever the parameters are, so a quick change of mind never snaps back first.

A cue holds only the parameters that existed when it was saved. A parameter you add later keeps its value when an older cue is called, and a name the sketch no longer declares is skipped. A parameter an [automation](../Core/Automation.md) drives keeps following its track. The track sets it every frame, after the cue has.

The sketch can call cues from anywhere: a key, a beat, a sensor.

```swift
override func keyPressed() {
    if key == " " { nextCue(over: 1) }
    else if let n = key.wholeNumberValue { cue(n - 1, over: 1) }
}
```

### What fades and what jumps

A number, a color, a vector, a rectangle, a set of insets, and a range fade, each component on the same ease. A switch, a menu choice, a piece of text, and a palette have nothing between two values, so they take the cue's value on the first frame of the fade rather than at its end. A fade moves a parameter through the same restore path a reload uses, so a smoothed parameter does not add its own glide on top.

### The inspector's card

Under OllinLive and OllinLiveCoding the inspector shows a **Cues** card under the parameters. Each row is a cue. Press one and it is called over the card's fade, and the dot lights on the cue in force, whoever called it. The field at the bottom saves the parameters as they stand under the name you type, or under "Cue 1", "Cue 2" and so on when you leave it blank. Type the name of a cue that exists and the button updates it instead. The minus beside a row deletes that cue. **Fade** is the seconds a called cue takes, for the card and for the host's own controls alike; 0 is at once.

The card changes the sheet and the file, never the sketch's text. The "Save parameters" button above it is a different thing: it writes the values you turned into the `@Param` lines, which is where a *default* lives. A cue is a look you come back to; a default is where the piece starts.

### A pad, a program change, an address

In the performance host a cue answers to a controller, as a host preference, the way [its other actions](../Tools/LiveCoding.md#the-host-on-a-controller) do. A MIDI **program change** calls the cue of that number, on any channel, with nothing to learn. Two press actions, **Next cue** and **Previous cue**, sit on the Controls card to learn a pad or a button, and answer at `/ollin/cue/next` and `/ollin/cue/previous` over OSC. `/ollin/cue` takes a name (`"night"`) or a number, and an optional second argument sets the fade in seconds for that call; without one the card's fade applies. A sketch that binds its own [MIDI](../Integration/MIDI.md) or [OSC](../Integration/OSC.md) can call cues from those messages too.

### The file

The sheet round-trips through JSON, and the live hosts keep it in `Sketch.cues.json` beside `Sketch.swift`, the way the timeline keeps `Sketch.automation.json`. OllinLive reads the file at launch and re-installs the sheet across every reload, so an edit to the code never loses a cue. Every save and delete from the card writes the file. OllinLiveCoding does the same for an open document, and keeps an untitled buffer's cues in memory until the buffer is saved somewhere.

A sketch running on its own names its file: `loadCues(from:)` reads one and `saveCues(to:)` writes one. The example loads the sheet from its bundle in `setup()` when a host has not installed one first. `CueSheet.load(from:)` and `write(to:)` are the same pair on the value. A file written by a newer format is refused rather than misread.

### A cue on the command line

`--cue <name>` on any export path, or on a standalone window, calls that cue after `setup()`, the way `--param` lands. `--cues <file>` names the sheet when the sketch is not carrying one already; under OllinLive the sibling file is installed first, so `--cue` alone finds it. A `--param` given beside it lands after the cue, so a value given by hand still wins.

```sh
swift run OllinLive MySketches/Finale.swift --export finale.png --cue night
swift run --package-path Examples Example-Live-Cues --export-video looks.mov --cues looks.json --cue storm --seconds 8
```

A name the sheet does not hold stops the run and says which names it does.

---

Related: [Parameters](./Parameters.md), [Automation](../Core/Automation.md), [The parameter timeline](../Tools/Timeline.md), [Live coding](../Tools/LiveCoding.md), [Export](../Output/Export.md#setting-a-parameter-for-the-run).
