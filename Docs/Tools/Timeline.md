#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Tools](./README.md) → `Timeline`</sup>

---

## The parameter timeline

An [`Automation`](../Core/Automation.md) writes a sketch's knobs down over time. The timeline is OllinLive's surface for authoring one by hand. It is a floating panel with one lane per automated knob and a playhead over the sketch clock, plus a small diamond in every knob row of the inspector. What it edits is the sketch's own automation. The frames play exactly what the lanes show, and every export renders it the same way.

This page is about the host panel. The `Timeline` value type inside a sketch, the keyframe sequencer a sketch drives itself, lives in [Animation](../Helpers/Animation.md).

### Opening it

Click **Timeline** in the title bar of OllinLive, or press **⌘T**. The panel floats beside the window, remembers its place and size, and closes from its own close button or the same toggle.

The panel lives in OllinLive only. The gallery shows knobs as a showcase; the live host is where a piece is directed.

### The authoring loop

The loop is three moves, and it repeats:

1. **Scrub.** Drag along the ruler. Space pauses, and the arrow keys step one frame at a time. The picture follows the playhead live.
2. **Turn the knob.** Set the value in the inspector, the way you always do.
3. **Click the diamond.** The knob's row places a key at the playhead with the value the knob holds.

A hollow diamond means nothing drives the knob yet; the first click starts its track. A filled diamond means a track drives it. Clicking while the playhead stands on a key takes that key away, so the diamond both places and removes. The **+ Track** menu in the panel's footer starts a track the same way. A right-click on a diamond or a lane label removes the whole track.

### Lanes and keys

A number lane draws its track's sampled value, so the line is what the knob will do. A color lane draws the blend itself as a band. A switch steps between its two levels. A knob driven by a [formula](../Helpers/Formula.md) shows the rule and takes no keys; its text is edited in the sketch.

Drag a key along its lane to move it in time. Double-click a key to remove it. Click a key to select it. The footer then names the moment and the curve that leaves the key, with a menu to change the curve and a button to delete the key. Choosing **Bezier** shows two handles on the lane; drag them to shape the ease by eye. The handles bend the same `.bezier(x1:y1:x2:y2:)` curve the file carries.

### The transport

The playhead rides the automation's own position. When the automation loops, the playhead comes around while the clock runs on, and the readout follows it. Pausing holds the clock still without drawing a single wasted frame, which is what an accumulating canvas needs. A frame step holds first, the way a video editor's does.

The **loop button** repeats a stretch while you work on it. Option-drag the ruler to choose the region, and the button arms and disarms it. The region lives on the transport only. It is never written into the file, so looping two seconds while shaping a curve changes nothing about the piece.

### The file

The tracks round-trip to a JSON file. By default it is the sketch's sibling, `Sketch.automation.json` beside `Sketch.swift`; `--automation <file>` points at another. On launch, OllinLive reads the file and installs its tracks, and it re-installs them across every reload. The panel's work survives the edit loop. Edits write back to the same file a moment after they land, and the footer names the file and whether it is saved.

OllinLive's own export flags read the sibling file too, so this renders the piece exactly as the panel played it:

```sh
swift run OllinLive Sketch.swift --export-video out.mp4 --seconds 12
```

A standalone run or an example's own export reads the same file through the flag: `--automation Sketch.automation.json`.

One precedence rule, the same rule the file has everywhere: the file's tracks install before `setup()` runs. A sketch that writes a track for the same knob in `setup()` wins that knob. A knob the sketch directs in code belongs to the code; the panel's edit of it lasts until the next reload.

---

Related: [Automation](../Core/Automation.md) - [Parameters](../Helpers/Parameters.md) - [Formula](../Helpers/Formula.md) - [Replay](../Core/Replay.md) - [Export](../Output/Export.md)
