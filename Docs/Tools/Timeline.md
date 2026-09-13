#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Tools](./README.md) → `Timeline`</sup>

---

## The parameter timeline

An [`Automation`](../Core/Automation.md) writes a sketch's parameters down over time. The timeline is the OllinLive surface where you author one by hand. It is a floating panel with one lane per automated parameter and a playhead over the sketch clock. It also puts a small diamond in every parameter row of the inspector. What it edits is the sketch's own automation, so the frames play exactly what the lanes show, and every export renders it the same way.

This page covers the host panel. A sketch can also drive its own keyframe sequencer with the `Timeline` value type, which is documented in [Animation](../Helpers/Animation.md).

### Opening it

Click **Timeline** in the title bar of OllinLive, or press **⌘T**. The panel floats beside the window and remembers its place and size. Close it with its own close button or with the same toggle.

The panel is in OllinLive only. The gallery shows parameters as a showcase, and the live host is where you direct a piece.

### The authoring loop

The loop has three moves, and you repeat it:

1. **Scrub.** Drag along the ruler. Space pauses, and the arrow keys step one frame at a time. The picture follows the playhead live.
2. **Adjust the parameter.** Set the value in the inspector, the same way you always do.
3. **Click the diamond.** The parameter's row places a key at the playhead, with the value the parameter holds.

A hollow diamond means nothing drives the parameter yet, and the first click starts its track. A filled diamond means a track already drives it. If the playhead stands on a key, clicking takes that key away, so the diamond both places and removes keys. The **+ Track** menu in the panel's footer starts a track the same way. Right-click a diamond or a lane label to remove the whole track.

### Lanes and keys

A number lane draws its track's sampled value, so the line shows what the parameter will do. A color lane draws the blend itself as a band. A switch steps between its two levels. A parameter driven by a [formula](../Helpers/Formula.md) shows the rule and takes no keys. You edit that rule in the parameter's own row, which the next section covers.

Drag a key along its lane to move it in time. Double-click a key to remove it. Click a key to select it. The footer then names the moment and the curve that leaves the key. It also gives you a menu to change the curve and a button to delete the key. Choosing **Bezier** shows two handles on the lane, and you drag them to shape the ease by eye. The handles bend the same `.bezier(x1:y1:x2:y2:)` curve the file carries.

### Writing a rule in the row

A parameter can be worked out from a rule instead of placed on keys, the way `drive($radius, "190 + sin(time * tau / 6) * 80")` does in a sketch. The inspector row is where you write one by hand. Right-click the diamond of a number, a whole number, or a switch and choose **Write a Rule**. A field opens under the row, in the same arithmetic the sketch speaks. Press Return, and the rule drives the parameter from the next frame on. The diamond turns into a function mark, and the slider or switch follows the rule and takes no hand, since a hand would be undone a frame later.

The row points at what went wrong. A rule that cannot be read stays in the field with a caret under the character the parser stopped at and the reason beneath it, and the rule that was running keeps running. A misspelled name is refused the same way, at the name, because a name nothing supplies would read as zero every frame and draw something rather than nothing. A parameter cannot name itself, and two parameters cannot name each other, so those are refused where they are written rather than reported when the frames play.

Empty the field and press Return to take the rule away. Escape puts the running rule back. Right-click the mark for **Remove Rule**. A parameter that already has keys keeps them: remove its track first if you want a rule there instead. A parameter of more than one number, such as a point or a color, takes its rules per part in the sketch with `drive($eye, x:y:)`, and the row leaves it alone.

The rule lands in the same automation file as the keys, written as the text you typed, so a run that reads the file plays it. A rule the sketch itself writes in `setup()` shows in the row too, and you can edit it there for the run. The next reload puts the sketch's own rule back, because the code is the artifact.

### The transport

The playhead follows the automation's own position. When the automation loops, the playhead comes around again while the clock runs on, and the readout follows the playhead. Pausing holds the clock still and draws no wasted frames, which is what an accumulating canvas needs. A frame step holds the clock first, the way a video editor does.

The **loop button** repeats a stretch of time while you work on it. Option-drag the ruler to choose the region, and use the button to arm and disarm the loop. The region belongs to the transport only, and it is never written into the file. So looping two seconds while you shape a curve changes nothing about the piece.

### The file

The tracks round-trip to a JSON file. By default that file is the sketch's sibling, so `Sketch.automation.json` sits beside `Sketch.swift`. Use `--automation <file>` to point at another file. On launch, OllinLive reads the file and installs its tracks, and it re-installs them across every reload. The panel's work survives the edit loop. Edits write back to the same file a moment after they land, and the footer names the file and says whether it is saved.

OllinLive's own export flags read the sibling file too, so this renders the piece exactly as the panel played it:

```sh
swift run OllinLive Sketch.swift --export-video out.mp4 --seconds 12
```

A standalone run or an example's own export reads the same file through the flag `--automation Sketch.automation.json`.

There is one precedence rule, and it is the same rule the file has everywhere. The file's tracks install before `setup()` runs. So a sketch that writes a track for the same parameter in `setup()` wins that parameter. A parameter the sketch directs in code belongs to the code, and the panel's edit of it lasts until the next reload.

---

Related: [Automation](../Core/Automation.md) - [Parameters](../Helpers/Parameters.md) - [Formula](../Helpers/Formula.md) - [Replay](../Core/Replay.md) - [Export](../Output/Export.md)
