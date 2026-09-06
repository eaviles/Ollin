# Sonification

Sonification reads numbers out as notes.

You can listen to any series: a column of a table, a line across a terrain, or a row of a picture. Sonification spreads the values of the series over a range of pitch. When you snap the reading through a [`Scale`](Composition.md#scale), it stays in key, so the data can be music rather than only a signal.

It is also a way for a drawing to reach someone who is not looking at it. A sketch that plots a column can read that column out loud from the same numbers, so there is no second copy of the data.

```swift
import OllinAudio

let synth = Synth(.pluck)
let readings = Sonification(table, column: "temperature",
                            in: Scale(.minorPentatonic, root: "A3"))
var counter = StepCounter(perBeat: 2)

override func draw() {
    for step in counter.steps(upTo: time * 2) {
        synth.play(readings, step: step, tempo: 120)
    }
}
```

Like everything else in the [composition](Composition.md) tier, a reading answers a step number and has no clock of its own. So the same reading can be driven by `time`, by a detected beat, or by a `TempoClock` that follows a drum machine.

---

## What it reads

There are four kinds of source, and each is a single call. A heightfield takes more than one, because a line across it can run along a row or at any angle.

```swift
Sonification(numbers)                                  // a series in hand
Sonification(table, column: "rainfall")                // a column of a table
Sonification(land, row: 32)                            // a line across a terrain
Sonification(land, from: Vector2(0, 0), to: Vector2(1, 1), count: 64)
Sonification(picture, row: 200)                        // a row of a picture
```

| Source | What it reads |
|---|---|
| `[Double]` | the numbers, in order |
| `Table` | one column, in row order. Cells that are not numbers are dropped, so a gap is a note that is not played rather than a note at zero |
| `Heightfield` | one `row:` left to right, one `column:` top to bottom, or a straight line at any angle through `from:to:count:` in normalized coordinates |
| `Image` | one `row:` or `column:` as brightness. The brightness is weighted the way the eye weights it, so a pure blue reads far darker than a green of the same numeric size |

A picture that lives on the GPU has no pixels to read on this side, so it gives an empty reading. Call `snapshot()` first.

---

## The settings

```swift
Sonification(numbers,
             in: Scale(.dorian, root: "D3"),   // the notes it may land on
             pitches: "C3"..."C6",             // the span it is spread over
             bounds: .robust(ignoring: 0.05),  // how the ends are decided
             polarity: .positive,              // which way round
             noteLength: 0.25)                     // beats per note
```

| Setting | What it does |
|---|---|
| `in scale:` | the notes the reading may land on. If you omit it, every semitone between the ends is available |
| `pitches:` | the span the data is spread over. The default is three octaves, which is wide enough to hear a shape in and not so wide that the top is shrill |
| `bounds:` | which values land at the ends. See below |
| `polarity:` | `.positive` means a larger value is a higher note, which is what a listener expects of a quantity. `.negative` is the right way round for a size, because a small thing is the one that sounds high |
| `noteLength:` | how long each note lasts, **in beats**. The tempo is applied when the note is played |

### Where the ends go

```swift
.extremes                   // the smallest and largest values there are
.robust(ignoring: 0.05)     // the same, after setting aside 5% at each end
.fixed(0 ... 100)           // a range you name, whatever the data does
```

Use `.robust` with real measurements. Otherwise one bad sensor reading at a thousand times the scale of everything else flattens the entire series into a single note. Use `.fixed` to make two readings comparable with each other, because the same value then lands on the same note in both.

A value outside the range is held at the end of the range, so it does not run off into an inaudible pitch.

---

## Reading it

| Member | What it gives |
|---|---|
| `count` / `isEmpty` | how many notes there are |
| `sonification[step]` | the `Note` at a step, or nil past the end |
| `note(at:)` | the same, spelled out |
| `notes()` | the whole reading at once, so a phrase can hold on to it |
| `pitch(for: value)` | where any one value lands, whether or not it is in the data |
| `values` / `valueDomain` | the numbers as read, and the two that land at the ends |

Use `pitch(for:)` to place another value, such as a threshold, an average, or the value under the mouse, on the same scale as the reading.

---

## The reference note

```swift
let sealevel = reading.reference(at: 0.5)
marker.play(sealevel, tempo: tempo)     // under the reading, every bar
```

Without a reference note, a listener needs absolute pitch to know what any note means. With one, a listener hears each note as above or below the reference note. That is what makes the reading a measurement rather than only a sound. The reference note does the job of a grid line on an ordinary chart.

---

## Loudness

A second series can be read out as loudness alongside the first.

```swift
let reading = Sonification(depth, in: scale).amplified(by: confidence)
```

The two series are lined up by position, so entry 3 of one is heard at the same moment as entry 3 of the other. If you give no second series, every note plays at full level.

Loudness is the weaker of the two dimensions, and it deliberately does nothing unless you ask for it. How loud a note sounds depends on its pitch as well as its strength. That means a series read out on loudness alone is heard through a distortion. Use pitch first, and use `amplified(by:)` for a *second* series rather than to say the same thing twice.

---

## How the mapping is made

Two choices are worth knowing about, because both are easy to get wrong and neither is what you would write first.

**Pitch is spread evenly in semitones, not in hertz.** Hearing is logarithmic. For example, the step from 220 Hz to 440 Hz and the step from 440 Hz to 880 Hz sound like the same distance. In hertz, the second step is twice the size of the first. So a series spread evenly in hertz crushes its whole bottom half into a few notes at the low end.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../../Guide/Images/29-MakingSound/Sonification-dark.jpg">
  <img src="../../Guide/Images/29-MakingSound/Sonification.jpg" alt="A series of sixteen values shown as bars, then the same series as note positions spread evenly in semitones, again spread evenly in hertz where the low half bunches against the top two octaves, and again snapped so every mark lands on a line of the scale" width="880">
</picture>

**Loudness is spread evenly in decibels**, for the same reason. The span runs between a floor and full level, not between silence and full level.

Semitones and decibels are the units pitch and loudness are heard in, which is why the mapping is linear once it is expressed in them.

---

## Going further

- [Composition](Composition.md) - the `Scale`, `StepCounter`, and `Note` this is built on
- [Synthesis](Synthesis.md) - the instrument that plays it
- [Data](Data.md) - `loadTable` and the `Table` a column is read from
- [Terrain](../Generators/Terrain.md) - the `Heightfield` a profile is read from

The example is `Examples/Audio/Sonification`. It draws a line across a landscape and reads it out at the same time.
