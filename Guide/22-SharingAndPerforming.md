#### <sup>[Ollin](../README.md) → [Guide](README.md) → Chapter 22</sup>

---

# 22. Sharing and performing

<img src="Images/22-SharingAndPerforming/Finale.jpg" alt="A bold posterized field of nested contour bands, electric blue and green at the edges through lilac and olive to a small lime core, like a printed topographic map of a wave" width="560">

Twenty-one chapters of pieces have lived on your screen. This last chapter is about everywhere else they can go: out as files (a poster, a video, a GIF, a plotter drawing), out as live feeds (into a VJ rig, into a video call), and out on a stage, where writing the code is the performance. The piece above is the final state of a live-coded set you'll build in five evaluations, and every road out of the framework starts from the same place: the sketch you already have.

## Leaving as files

<img src="Images/22-SharingAndPerforming/ExportMap.jpg" alt="A diagram with a box labeled your sketch in the middle, arrows fanning left to five file outputs (still, sequence, video, GIF, SVG) and right to three live feeds (the window, Syphon, virtual camera)" width="680">

Every file export runs the sketch *headlessly*: no window opens, `setup()` runs, the clock advances to the frame you asked for, `draw()` runs, and the result is written. Because the offline clock is a fixed timestep, an export is deterministic: the same sketch, seed, and frame make the same file every time, however long the render takes. Sources follow the same clock: a video decodes by frame position, and an `AudioPlayer` feeds its analyzer the matching slice of its file each frame, so even an audio-reactive piece exports with its beats in the same places. The flags live on any example's executable, and a loose sketch file gets the identical surface through the live host:

```sh
swift run OllinLive MySketches/Finale.swift --export poster.png --frame 200
swift run Example-Motion-Breathing --export-sequence /tmp/out --seconds 5 --fps 60
```

`--export` writes one frame as a PNG; `--export-sequence` writes every frame, lossless, ready for `ffmpeg` or an edit timeline. Exports default to the best render quality (`.detail`), since a file has no frame rate to protect; `--render-quality` dials that when you want a fast draft.

## Motion: video and GIF

For a file you can post, skip the stitching and encode directly:

```sh
swift run OllinLive MySketches/Finale.swift --export-video finale.mp4 --seconds 12
swift run OllinLive MySketches/Finale.swift --export-gif finale.gif --seconds 4 --gif-width 540
```

Video first, because it's almost always the right choice. The default `h264` plays everywhere; `--codec hevc` is better quality per byte when the file needs to be smaller; the two ProRes profiles are for edit timelines, not for sharing. `--bitrate` (in Mbit/s) is the file-size dial, and a 1080-square piece looks clean around 10 to 15 in `h264`. The GIF is for the short loop: it's palette-limited and heavy per second, so keep it a few seconds, downscale with `--gif-width`, and know that a piece where *every* pixel changes every frame (a drifting full-canvas field) defeats GIF compression entirely and balloons the file. Chapter 3's perfectly looping phase tricks are exactly what a GIF wants.

## Vector: the plotter path

Chapter 13 promised that shapes held as geometry could leave as geometry; `--export-svg` is that promise kept:

```sh
swift run OllinLive MySketches/Plot.swift --export-svg plot.svg
swift run OllinLive MySketches/Plot.swift --export-svg plot.svg --hatch
```

The exporter records each draw call at its own level, before any pixels exist: circles become `<circle>`, polylines `<polyline>`, shapes and outline text `<path>` with their fill rules, transforms and opacity intact. The file opens in a browser, Inkscape, or Illustrator, and feeds a pen plotter's tooling directly. Since a pen has no fill, `--hatch` turns solid fills into parallel line work spaced by tone (add `--cross-hatch`, or set `--hatch-spacing` and `--hatch-angle`), while stroke fonts and stroked geometry pass through as the single lines they already are. Images are the one thing that can't come along; a vector file has no place for them.

## Reproducibility is part of the piece

A shared render is better when it can be *re-made*. Three habits from earlier chapters pay off here. Seed the randomness (`seed(…)` in `setup()`, Chapter 4), so the export and the re-export are the same artwork, not siblings. Copy tuned `@Param` values back into their declarations once they feel right, because a headless export reads the defaults written in code, not the inspector. And share the `.swift` file alongside the render when you can: in Ollin the sketch is the artifact, and a reader holding the source holds the whole piece, seeds, knobs, and all.

## Live feeds: into other apps

Some pieces shouldn't become files at all; they should stay alive and go *into* something. **Syphon** is the macOS standard for handing GPU frames between running apps, and one line makes a sketch a source every VJ tool can see:

```swift
import OllinSyphon

override func setup() {
    publishSyphon(name: "Ollin")     // every frame is now a Syphon source
}
```

Resolume, MadMapper, VDMX, and other creative-coding frameworks all read it live, pixel-identical to your window, with nothing touching disk. It works the other way too: `SyphonClient` subscribes to another app's feed and hands you each frame as an `Image` to draw, warp, or feed to Chapter 21's trackers. Pair it with Chapter 20 and the rig conversation goes both directions at once: visuals over Syphon, control over OSC or MIDI. The `Integration/SyphonLoopback` example runs both ends in one sketch (a video-feedback tunnel, since it watches itself), so you can see the plumbing with no second app installed.

The **virtual camera** goes where Syphon can't: `publishVirtualCamera()` makes the sketch a system-wide webcam called "Ollin Camera", so Zoom, Photo Booth, QuickTime, OBS, and (importantly) the *browser* can all take a sketch as their camera. It needs a one-time install of the camera extension (the Ollin Camera app in this repo; approve it in System Settings), and from then on any sketch can feed it, with a broadcast test card showing whenever none is. Your next video call can open on a reaction-diffusion field.

## Performing the code itself

The last output is a stage. `swift run OllinLiveCoding` opens the performance host: the sketch fills the window, and the code rides over it as translucent text, part of the show:

<img src="Images/22-SharingAndPerforming/StageDiagram.jpg" alt="An annotated diagram of the performance host: a dark window with a posterized visual filling the stage, code lines riding over it on translucent strips, an Evaluated toast, and callouts naming each part" width="680">

The loop is different from the live-reload host you've used since Chapter 1. There is no file watching and no separate editor: you type in the window and press **⌘↩** to evaluate. The buffer compiles in the background while the running sketch keeps drawing, and on success the new sketch swaps in with the clock carried across, so a phase-driven motion never jumps mid-set. Tuned `@Param` knobs (including ones bound over MIDI or OSC) carry across too. A typo can't stop the show: the last good sketch keeps playing, the errors land in a strip along the bottom, and you fix and evaluate again. When the code should get out of the way, **⌃⇧H** hides it and the visuals keep the whole stage; **⌃⌘F** is fullscreen for the projector. For a real set, `Scripts/OllinLiveCoding` builds the host in release mode so the framework renders at full speed.

Evaluation never writes your file (⌘S does), so you can riff as recklessly as the room deserves and keep only what worked.

## The payoff: a set in five evaluations

The payoff is a short performed piece. Open the host with a fresh buffer and build the chapter's finale the way an audience would watch it grow, one evaluation at a time, using Chapter 15's `Visual` chains (the natural material for this kind of set, since every step is one added line):

<img src="Images/22-SharingAndPerforming/SetSteps.jpg" alt="Five numbered thumbnails: vertical color bands, the bands folded into a five-pointed mandala, the fold melted by noise, the melt posterized into hard bands, and the whole thing color-shifted toward green" width="680">

1. Start with breath: `drawVisual(.oscillator(frequency: 11, speed: 0.6, colorShift: 0.5))` and ⌘↩. Drifting bands fill the stage.
2. Fold space: add `.kaleidoscope(5)`. A five-pointed mandala, still breathing.
3. Melt it: add `.displaced(by: .noise(scale: 3, speed: 0.25), amount: 0.09)`.
4. Make it a print: add `.posterized(bins: 6, gamma: 0.75)`. Hard contour bands, a screen-print of the melt.
5. Set it flying: add `.rotated(time * 0.03)` and `.colorCycled(time * 0.04)`, a slow spin through the whole color wheel.

The finished buffer is the whole piece, and it's small enough to retype from memory, which is rather the point ([`Finale.swift`](Figures/22-SharingAndPerforming/Finale.swift) is the committed figure):

```swift
import Ollin

final class Finale: Sketch {
    override func draw() {
        drawVisual(
            .oscillator(frequency: 11, speed: 0.6, colorShift: 0.5)
                .kaleidoscope(5)
                .displaced(by: .noise(scale: 3, speed: 0.25), amount: 0.09)
                .posterized(bins: 6, gamma: 0.75)
                .rotated(time * 0.03)
                .colorCycled(time * 0.04)
        )
    }
}
```

<img src="Images/22-SharingAndPerforming/Finale.jpg" alt="The finale at one moment: nested posterized contour bands from electric blue and green edges to a lime core, slowly rotating and cycling hue when live" width="560">

Then close the loop this chapter opened: save the buffer (⌘S), record the piece as a file to share (`swift run OllinLive MySketches/Finale.swift --export-video finale.mp4 --seconds 12`), and if a projector or a call is handy, `publishSyphon()` or `publishVirtualCamera()` while you perform. The same small sketch just walked out of every door this chapter opened.

Then make it yours:

- Play the set differently: reorder the moves, or swap step 2's fold for `.repeated(x: 3, y: 3)` and the mandala becomes wallpaper.
- Wire Chapter 20 in: `@Param` the oscillator frequency, bind it to a MIDI knob, and the set gets a second instrument.
- Feed it eyes: `.displaced(by: .layer(feed), amount: 0.1)` over a layer you draw the webcam into, and the audience melts the piece.
- Perform an old friend: any payoff from this guide runs in the host as-is; try evaluating changes into Chapter 16's reaction-diffusion while it grows.

## Where this comes from

Live coding as a performance practice was organized by TOPLAP (founded 2004), whose manifesto demanded "show us your screens"; the code-over-the-visuals layout of this host is that idea, and its most direct model is Olivia Jack's browser instrument Hydra, which made the pattern feel effortless. Alex McLean and the TidalCycles community built the musical wing of the same practice. Syphon is Tom Butterworth and Anton Marini's gift to the Mac's visual ecosystem, and the vendored framework carries their names. The pen-plotter revival that SVG export serves grew around the AxiDraw and the #plottertwitter community, heirs of the 1960s computer-art plotters this guide's recreations visit. Full credits are in the project's [attribution notes](../ATTRIBUTION.md).

## Go deeper

- [Export](../Docs/Output/Export.md): every flag, codec advice, GIF timing, SVG mapping, hatching.
- [Syphon](../Docs/Integration/Syphon.md): publishing, receiving, discovery, and the loopback.
- [Virtual camera](../Docs/Integration/VirtualCamera.md): the one-time install, publishing, the test card.
- [Live coding](../Docs/Tools/LiveCoding.md): the evaluate loop, errors, recovery, and the keyboard reference.
- Worked examples: [`Examples/Export/VectorExport`](../Examples/Export/VectorExport/Sketch.swift), [`Examples/Export/Hatching`](../Examples/Export/Hatching/Sketch.swift), [`Examples/Integration/SyphonLoopback`](../Examples/Integration/SyphonLoopback/Sketch.swift), [`Examples/Integration/SyphonViewer`](../Examples/Integration/SyphonViewer/Sketch.swift), and [`Examples/Integration/VirtualCamera`](../Examples/Integration/VirtualCamera/Sketch.swift).

---

[Contents](README.md#contents) · Previous: [Chapter 21, Seeing](21-Seeing.md) · Next: the appendices, as they land
