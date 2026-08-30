#### <sup>[Ollin](../README.md) → [Guide](README.md) → Chapter 32</sup>

---

# 32. Installations

<img src="Images/32-Installations/WallPiece.jpg" alt="A wide dark screen carrying a slow field of vertical bars in dusk colors, deep plum at the right rising into orange at the left, with a separate band of the same colors running along the bottom edge" width="680">

Nobody is sitting in front of that. It is on a wall, it has been there since Tuesday, and it will still be there when the building shuts on Sunday. The band along its bottom edge is not decoration either. A strip of lamps is reading that band and lighting the wall under the screen with it.

[Chapter 31](31-SharingAndPerforming.md) sent work out as files and feeds. This chapter is the other way a piece leaves your desk: it stays where it is, and you go home. That turns out to be a different job. The output may not even be a screen, the frame budget stops being a preference, and a room does things to a sketch that a desk never does. By the end you'll have built the piece above, declared for a room rather than a window.

## Light instead of pixels: DMX

A lighting rig is a display with very few, very bright pixels, and a sketch can render for it too. Stage lighting speaks **DMX**, the protocol that has told dimmers, LED pars, and moving heads what to do since 1986. It travels over ordinary Ethernet in two dialects, **Art-Net** and **sACN**. The model is small. A *universe* is 512 channels of one byte each. A *fixture* listens at an address and reads a few consecutive channels. What each channel means is printed in the fixture's manual, whether that is red, green, blue, a dimmer, or a pan motor. You fill 512 bytes, you send them, the room changes.

```swift
import OllinDMX

let dmx = DMXSender()                           // sACN multicast: zero config
let par = DMXFixture.rgb(at: 1)                 // an RGB par on channels 1-3

override func draw() {
    var rig = DMXUniverse()
    rig.set(par, color: Color(hue: fract(time * 0.1), saturation: 1, brightness: 1))
    dmx.send(rig)                               // universe 1, every frame
}
```

`DMXSender()` with no address multicasts sACN, which any listening node on the network picks up with no addressing at all. `DMXSender(artNet: "192.168.1.60")` unicasts Art-Net to a node that wants it. Either way you send every frame, like a second `draw()` aimed at the room. The sender handles the wire's own etiquette. It sends changed data only, caps near DMX's own refresh rate, and keeps alive while nothing moves. A 60 fps sketch therefore makes a perfectly polite lighting console. The fixture sugar keeps the addressing in one place. Patch a `DMXFixture` per lamp with the roles its manual lists, and chain them with `nextAddress`. Then `rig.set(par, color:)` lands on whatever channels the layout names.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/32-Installations/LampsAndBytes-dark.jpg">
  <img src="Images/32-Installations/LampsAndBytes.jpg" alt="A diagram in two rows: six colored pars hanging over a dark stage throwing red through violet light, and below them the same universe's first eighteen channels as meter bars bracketed into fixtures, with the fourth par dim in both views" width="680">
</picture>

It works the other way around too. A `DMXReceiver` turns the sketch into a fixture. A real console fades channel 1, and `draw()` reads it as `dmx.level(1)`. Or `dmx.bind(channel: 1, to: $radius)` puts the fader on the same knob the inspector slider moves. That is exactly like [Chapter 28](28-SoundAndControl.md)'s MIDI and OSC bindings. The `Integration/DMXLoopback` example runs both ends on `127.0.0.1`. A sender chases colors across a drawn rig, and the rig is lit from what the receiver reads back. The whole path runs with no console and no hardware. When you do reach for real lights, two practical notes matter. macOS asks once for Local Network permission, attributed to the terminal you launched from. A free sACN monitor app will show you every universe on the wire. Use it while you find your fixture's address.

The rig's big sibling is the LED wall, and for that you stop filling channels by hand. An `LEDMap` lays the fixtures over the canvas itself. A strip is a run of sample points along a line or a curve, and a matrix is a grid of them. Every frame the map reads the rendered pixels under each LED and ships them through a `DMXSender`. That read happens on the GPU, over a few hundred points, never as a whole-frame readback. The wall is just the canvas, somewhere else.

```swift
let dmx = DMXSender()                     // or unicast to your pixel controller
let leds = LEDMap(sender: dmx)

override func setup() {
    leds.addStrip(from: Vector2(100, 540), to: Vector2(980, 540), leds: 144)
    leds.addMatrix(in: Rectangle(x: 390, y: 150, width: 300, height: 300),
                   columns: 16, rows: 16, universe: 2)
    extend(leds)                          // from here on it feeds itself
}
```

After `extend(leds)` you draw as if the wall didn't exist. Whatever lands under the mapped points is what the wall shows. Each LED averages the little patch of canvas it stands for, so a strip over fine detail glows steadily instead of flickering. On the wire the map packs whole LEDs into universes, 170 RGB pixels per universe, with longer runs continuing on the next number up. That is exactly the layout pixel controllers expect. Patch yours to the numbers `leds.universes` reports and you're done. The `Integration/LEDMapping` example runs it all on loopback, the drawn strip and panel lit from what a receiver reads back off the wire.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/32-Installations/LEDWall-dark.jpg">
  <img src="Images/32-Installations/LEDWall.jpg" alt="A diagram in two rows: a colorful gradient picture with a wavy strip of small rings and a bracketed grid of rings mapped over it, and below, the same LEDs lit for real: the strip laid out straight in wire order and the panel beside it, each labeled with the universe it occupies" width="680">
</picture>

## When it gets slow: the cost row

The night before an opening is a bad time to discover that a piece runs at 24 frames a second. Sooner or later one will, and the useful question is not "is it slow" but "which half is slow".

Press **⌘/** for the inspector. The cell grid ends with three counts, and two bars sit under it.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/32-Installations/CostRow-dark.jpg">
  <img src="Images/32-Installations/CostRow.jpg" alt="A diagram of the inspector's cost row: a row of cells reading 1 draw, 2 passes, 1 batch, over a CPU bar filled a little over half and a GPU bar filled less, with callouts naming what each part means" width="680">
</picture>

The **CPU** bar is your `draw()` plus the encoding that turns it into GPU commands. Tessellation lives there: every fill and every stroke is cut into triangles before the GPU sees it. The **GPU** bar is what the card spent on the frame, taken from its own clock.

Both bars are drawn to the same scale, which is the length of one frame. At 60 frames a second that is 16.7 ms. So the longer bar is your problem, and two short bars mean you have room.

They are not stacked into one bar on purpose. The CPU is already building the next frame while the GPU draws this one, so the two overlap in time rather than adding up.

The counts say what the frame asked for. **Draws** is the draw calls. **Passes** is the render passes, which is two for a plain sketch and one more for every layer and filter. **Batches** is the runs the drawer recorded, and a run breaks whenever the blend mode, texture, or clip changes.

That last one is the surprise. Ten thousand circles in a row cost one draw call. Ten circles that each change the blend mode cost ten. If the batch count is close to the shape count, group the shapes that share a state.

The rest of the reading is short:

- **CPU bar long?** You are making geometry. Hover Draws for the vertex count. Static geometry belongs in a [retained batch](../Docs/Drawing/Batches.md), recorded once and replayed from the card.
- **GPU bar long?** You are filling pixels. Look at the pass count, and give soft layers a smaller `makeRenderTarget(scale:)`.
- **Both short and still slow?** Something outside the drawing is holding the frame, like a file read in the middle of `draw()`.

When you need to know which pass, hand the frame to Xcode:

```sh
MTL_CAPTURE_ENABLED=1 ollin MySketch.swift
```

Then **View ▸ Capture GPU Frame (⌘⇧G)**, or `captureGPUFrame()` from your own code. Ollin writes a `.gputrace` file that opens in Xcode's GPU debugger, and prints the frame's passes in order on the way past. Often that printed list is the whole answer.

## Leaving it running

Some pieces are not files. They go on a wall, or in a shop window, and stay there for a week with nobody watching them.

That is a different job from a sketch at your desk, and different things end it. The screen saver comes on at midnight. The display sleeps. Somebody unplugs the monitor to borrow it. None of that is your drawing's fault, and all of it stops the show.

One line asks Ollin to hold it off:

```swift
override var installation: Installation { .on }
```

Now the window takes the whole screen with no title bar, the pointer disappears, and the display stays lit with the screen saver held off. Command-Q still quits, whatever the piece covers.

You do not have to edit a sketch to try this, or to get out of it:

```sh
swift run --package-path Examples Example-Motion-Orbits --installation                 # any sketch, up on the wall
swift run --package-path Examples Example-Installation-Unattended --no-installation    # back to a window to work in
```

A single file goes up the same way. It has no target of its own, and the host that usually runs it keeps the window. The flag hands the sketch one:

```sh
ollin piece.swift --installation
```

That host does not reload on save. On a wall that is what you want: the piece runs the code you started it with. Plain `ollin piece.swift` is still where you work on it.

### What actually breaks is the clock

The screen saver is the obvious enemy. The clock is the real one, and it goes wrong twice.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/32-Installations/LongRunClock-dark.jpg">
  <img src="Images/32-Installations/LongRunClock.jpg" alt="A diagram in two parts: a timeline of frame ticks with an eight-hour gap where the display slept, the first frame back read two ways as either an eight-hour deltaTime or a quarter-second one; and two cards of three consecutive shader-clock readings, one stuck at 604800.00 and one counting normally after a restart" width="680">
</picture>

First, a gap. When the display sleeps, no frames are drawn, and the first frame back happened eight hours after the last one. Read from the wall clock, that is a `deltaTime` of eight hours. Hand that to anything that moves by `speed * deltaTime` and it leaves the canvas forever, in one step.

So the sketch clock is not the wall clock. It is the sum of its own frame steps, and each step is capped at a quarter of a second. A gap becomes a pause, and the piece carries on where it stopped. You get this whether or not you declared an installation, because a laptop lid closes in the middle of an afternoon too.

Second, precision. Your `time` is a 64-bit number and stays exact for centuries. The copy your shaders read is a 32-bit one, and it cannot count seconds for a week. After a day the steps go uneven. After a week, adding one frame to it changes nothing at all, and every motion written inside a shader stops dead.

The fix is to give the shaders a clock that starts over. It is only free if the restart lands where the piece repeats, so it is tied to the loop you declare:

```swift
override var installation: Installation { .on }
override var loopDuration: Double? { 120 }     // two minutes a lap
```

Nothing moves at the restart, because the piece is back at the start of a lap anyway. A sketch with no declared loop keeps counting, since there is no free moment to jump at. Say `Installation(clock: .restarting(every: 600))` if you know one, or leave it alone.

### Picking up where it left off

Some pieces are the same every launch, because everything they draw comes from the clock and the seed. Those need nothing here.

Others grow. A wall that fills in one tile at a time, a reef that adds a polyp an hour, a drawing that accumulates. Three days in, that piece is not something you can rebuild from its seed. Getting back there means running the three days again.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/32-Installations/Resuming-dark.jpg">
  <img src="Images/32-Installations/Resuming.jpg" alt="Two dark eight-by-eight boards side by side with an arrow labeled relaunch between them: the left holding fourteen colored tiles, the right holding the same fourteen in the same cells plus three more, ringed in orange" width="680">
</picture>

So write the state down. Two lines: how often, and what.

```swift
override var installation: Installation { Installation(checkpoint: .every(seconds: 60)) }

@Saved var tiles: [Tile] = []
```

Every `@Saved` property goes into the file on that cadence, along with the seed, the clock, and every `@Param` value. A relaunch puts them all back before your first frame draws. The piece carries on.

Anything `Codable` can be saved, which includes your own structs once you mark them `Codable`. What cannot is anything living on the GPU: an accumulated canvas, a feedback layer, a simulation field. Those are textures the framework owns, and the checkpoint does not reach them.

You will edit the sketch while an old file is still sitting there, so every mismatch is made to cost only itself. Rename a property and the old value finds nothing. Change its type and it fails alone, named in the log, while everything else still restores. Damage the file and it is ignored. A piece on a wall that will not start is worse than one that started over.

`--fresh` ignores the saved state for one run without deleting it. That is the one to reach for when a piece comes back in a state you do not want.

### When it falls over

A piece on a wall crashes at three in the morning and nobody is there. The wall stays dark until somebody notices, which is usually the next day.

```swift
override var installation: Installation {
    Installation(checkpoint: .every(seconds: 60), restarts: .onFailure)
}
```

The process you start becomes a small watch with no window of its own, and your piece runs inside it as a child. When a run ends badly, the watch starts another one. Pair it with a checkpoint, or the piece comes back at the beginning every time.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/32-Installations/BackUp-dark.jpg">
  <img src="Images/32-Installations/BackUp.jpg" alt="A timeline of one night from 22:00 to 08:00: three run bars for the piece, the first ending at a marker labeled crash, the second turning gray before a marker labeled stopped answering, the third still going; underneath, a row of heartbeat ticks that stops where the gray stretch begins" width="680">
</picture>

Two things end a run badly. A crash is the obvious one. The other is a frame that never finishes. The process stays perfectly healthy and the picture freezes, which is what a viewer actually sees. So the piece writes a heartbeat every couple of seconds from the thread that draws. A main thread stuck in a frame stops writing it, and that silence is the only sign there is.

Quitting is not falling over. Command-Q ends the whole thing, watch included.

A piece that fails one second after it starts will not be fixed by starting it again. So each try waits longer than the last. After five short runs the watch gives up and says so in the log. One run of any real length clears that record. A slow `setup()` is not a stall either: a piece gets at least two minutes to draw its first frame, whatever limit you set.

### Gallery hours

A piece on a wall is in a building, and buildings have hours.

```swift
Installation(schedule: .open(from: 10, to: 18))
```

Outside them the screen goes dark and the display is allowed to sleep. The frames stop with it, and the clock stops with them. In the morning the piece carries on from where it stopped, not from where the day got to.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/32-Installations/GalleryHours-dark.jpg">
  <img src="Images/32-Installations/GalleryHours.jpg" alt="A day drawn as a colored bar over a 24-hour axis: a dark stretch until six, then parts named dawn, day, dusk and night, and dark again from eleven at night; below it the sketch clock as a line that lies flat through the dark hours and climbs through the rest" width="680">
</picture>

The other half is a piece that changes through the day. Name the parts of the day, and read the one you are in:

```swift
override var installation: Installation {
    Installation(schedule: [.from(6, "dawn"), .from(10, "day"),
                            .from(18, "dusk"), .from(20, "night")])
}

override func draw() {
    background(scheduledPeriod == "night" ? Color(white: 0.04) : .white)
}
```

Each part runs until the next one starts. The last one runs round to the first, which is how a night crosses midnight in one piece. `scheduledProgress` says how far through the current part you are, from 0 to 1, for a piece that slides rather than switches. The two halves are one list, so mix them: `.dark(from: 20)` is a part with nothing on screen.

Both readings work at your desk as well as on a wall. You can build a piece that changes at dusk without waiting for dusk.

### Fitting the wall

A projector is almost never square to what it is aimed at. It hangs off a beam, or sits on a shelf to one side, and your rectangle lands as a trapezoid.

So press **Command-K** on the running piece. Four handles appear on the corners. Drag each one onto the wall, and press Command-K again.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/32-Installations/FittingTheWall-dark.jpg">
  <img src="Images/32-Installations/FittingTheWall.jpg" alt="Left, a rectangle of grid lines landing on a wall as a tilted trapezoid, labeled as it lands. Right, the same grid sitting square inside the wall with a handle on each corner, labeled corner-pinned. Below, two colored blocks meeting in a shared band where each fades out, with a flat line across the top labeled added up, one coat" width="680">
</picture>

The numbers are kept under the display rather than under the sketch. The projector is out of true by the same amount whatever is playing. Line it up once and everything you show there opens square.

A wall longer than one projector takes two machines, each carrying a part of the canvas:

```swift
// The machine on the left.
Installation(projection: .init(visibleRegion: Rectangle(x: 0, y: 0, width: 0.6, height: 1),
                               blend: Insets(right: 0.2)))
```

The one on the right declares the mirror of that: `shows` starting at 0.4, and the same 0.2 fading in from its left. They are told the same number about the same band. Their two fades add up to one coat, so no bright bar runs down the join.

None of this reaches an export. A file has no wall to fit.

### Several displays, one machine

Two projectors do not have to mean two machines. A Mac with two outputs can carry both of them itself:

```swift
override var installation: Installation {
    Installation(displays: .spanning)
}
```

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/32-Installations/ManyDisplays-dark.jpg">
  <img src="Images/32-Installations/ManyDisplays.jpg" alt="A long canvas at the top holding a night sky, a sun and one wave, divided by two lines into three parts labeled shows 0 to 0.33, 0.33 to 0.66, and 0.66 to 1. Three arrows lead down to three display panes, each holding its own third of the same picture, so the wave carries on from one to the next" width="680">
</picture>

That spreads one canvas over every display the machine has, in the arrangement they are actually in. Two monitors side by side carry a half each. One above the other carries a band each. You declare no numbers at all, because the desk already says them.

The piece knows none of this. It draws one canvas, and the wall decides which part of that canvas each display carries. That is the same split as the two-machine wall above, with both parts on one machine.

For a wall that is not a plain row of monitors, declare the parts yourself. Two projectors overlapping in the middle is the usual case:

```swift
Installation(displays: .parts([
    .init(visibleRegion: Rectangle(x: 0, y: 0, width: 0.6, height: 1), blend: Insets(right: 0.2)),
    .init(visibleRegion: Rectangle(x: 0.4, y: 0, width: 0.6, height: 1), blend: Insets(left: 0.2)),
]))
```

Command-K raises the handles on every display at once, since a wall is lined up as one thing. The keys that move a corner go to the display you last clicked.

You will usually meet the wall for the first time in the room it is going up in. So look at it before then:

```sh
swift run --package-path Examples Example-Installation-ManyDisplays --rehearse 3
```

That opens one window per part on the desk you are at, side by side, each carrying its own part. It shows you the layout rather than the light. Two beams sharing a band add up to one coat; two windows sharing one would only hide each other.

The piece is drawn once a frame however many displays it goes on. What grows is the size it is drawn at, since each display wants its own part at its own resolution.

### Several windows, one world

A piece does not have to be one window. Run the same sketch three times and you have three windows on one desk, and they can look into one world rather than three.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/32-Installations/OneWorldManyWindows-dark.jpg">
  <img src="Images/32-Installations/OneWorldManyWindows.jpg" alt="A pale rectangle labeled the desk, holding faint rings and colored dots. Three dark window panes sit on it, each showing the part of the rings and dots that falls inside it, so the rings carry on across the gaps between the panes. A bracket under the middle pane is labeled canvasOnScreen: where this one sits on the desk" width="680">
</picture>

What each window needs is to know where it is. `canvasOnScreen` says where this canvas sits on the desk. It is measured the way the canvas is measured, so all three windows describe the same desk in the same numbers:

```swift
guard let mine = canvasOnScreen else { return }
let onCanvas = worldPoint - Vector2(mine.x, mine.y)      // the desk, seen from here
```

Then draw in desk coordinates and move each point into this canvas at the last moment. Drag a window and the next frame reads the new place, so the world stays where it is while the window slides over it.

The other half is that nothing here talks to anything. The windows are separate programs, and separate programs are hard to keep in step. So make the whole world a function of the time of day, which they all read the same, and they cannot disagree. That is worth reaching for before anything with a network in it. The `Installation/ManyWindows` example is the whole thing, in about eighty lines.

Windows on one machine can share a clock that way. Machines cannot, and that is the next section.

### Several machines, one piece

A wall longer than one projector took two machines, each told which part of the canvas it shows. Nothing has told them what time it is.

Each sketch starts its clock when it starts. Switch on the machine at the left of the wall, walk to the one at the right, switch that on. The two are now seconds apart, and everything that moves in the piece says so.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/32-Installations/OneRoom-dark.jpg">
  <img src="Images/32-Installations/OneRoom.jpg" alt="Two rows, each with two screens showing a bead on a ring. In the top row, labeled each machine's own clock, the beads sit in different places and two timelines below start at different points, one reading 7.0 s and the other 4.6 s. In the bottom row, labeled the room's clock, both beads sit in the same place over one shared timeline reading now, 7.0 s on both" width="680">
</picture>

A room fixes that. The machines find each other by a name you make up: no server, no address, nothing to configure.

```swift
import OllinRoom

let room = Room(named: "wall", seat: 0)   // the machine at the right says seat: 1

override func setup() {
    extend(room)
    room.shareAll()
}

override func draw() {
    let angle = room.time * speed     // room.time, not time
}
```

Three things arrive with it.

**One clock.** `room.time` is the same number on every machine. One of them keeps it, and the others ask it what time it is a few times a second. The answer allows for the time it spent on the wire. Measured between two sketches on one Mac, the first answer lands within a quarter second of joining. The clocks then agree to a tenth of a millisecond, which is as fine as the measurement could see. Before that first answer `room.clockError` is `nil`, so a piece that must not start early can wait for it. When the machine keeping the clock leaves, the room picks another and keeps the time it already had.

**One seat each.** `room.seat` counts from zero and `room.seatCount` says how many there are. A piece can then lay itself out across the whole wall and slide its own part into view:

```swift
let wall = width * Double(room.seatCount)
withState {
    translate(-Double(room.seat) * width, 0)
    drawWholePiece(across: wall)
}
```

That is a different tool from the `shows` rectangle earlier in this chapter, and they get on. `shows` cuts a finished canvas for a projector that is hung where it is hung. A seat tells the sketch which part of the wall it *is*, so the drawing itself can be wider than one screen. Ask for a fixed seat, as above, and a machine that restarts comes back to the same slice.

**One set of knobs.** `room.shareAll()` makes every `@Param` travel; `room.share("speed", "hue")` picks. Turn a knob on any machine and the rest follow within a frame. Two people turning one knob at the same moment is settled by the room's clock: the later turn wins everywhere.

Anything else the piece wants to say travels under a key, and reads the way OSC and MIDI read in [Chapter 28](28-SoundAndControl.md):

```swift
room.send("bird", position, reliable: false)      // sent every frame
let bird = room.point("bird", default: center)     // the latest one
for message in room.messages() { }                 // or every one that arrived
```

The first time a sketch opens a room, the system asks to use the local network. A sketch run from a terminal inherits the terminal's answer, so grant it once at the desk before the show. Anyone on that network who knows the room name can join, which is the convenience working as intended on a show network and a reason for the `passcode:` on a network you do not control.

You do not need a second machine to see the loop. `RoomLoopback` puts two rooms in one sketch: the left panel sends where the pointer is, the right panel draws only what arrived, and the space bar cuts the wire.

```sh
swift run --package-path Examples Example-Integration-RoomLoopback
```

In plain terms: give the machines a name to meet under, and they draw one piece on one clock instead of several copies of it.

### The log

An unattended run prints a line when it starts, when it resumes, and when the machine wakes or the displays change. The hours and the watch print their own. Send it somewhere you can read on Monday:

```sh
swift run --package-path Examples Example-Installation-Unattended >> ~/piece.log 2>&1
```

```
Ollin installation [2026-08-15 08:41:45]: running unattended; Command-Q quits
Ollin installation [2026-08-15 08:41:45]: resumed the run saved at 2026-08-14 23:07:12 (frame 4098, 68s in)
Ollin installation [2026-08-15 18:00:04]: dark until 10:00
Ollin installation [2026-08-16 03:12:08]: the screens woke
```


## Tuning it from the floor

The piece is on the wall and the Mac is behind it. The right place to judge a speed or a color is in front of the wall, twenty steps from the keyboard. One line serves every knob the sketch declares to your phone.

```swift
import OllinRemote

@Param(0.1...4) var speed = 1.4
@Param var accent = Color.purple

override func setup() {
    extend(RemoteInspector())
}
```

On launch the sketch prints `Remote surface: http://your-mac.local:9330`. Open that address in the phone's browser, on the same Wi-Fi. Every `@Param` appears as a touch control. Sliders take the width of the screen; a `style: .pad` vector becomes an XY pad; switches, menus, and a color picker cover the rest. The groups match the inspector sidebar. A strip at the top carries the frame rate, the clock, and the frame count. The piece's health is readable from the floor too.

Edits go both ways. Drag a slider on the phone and the value lands before the next frame, exactly where the inspector's own edits land. Turn a knob on the Mac and the phone follows. Stand in front of the wall, look at the piece, and turn the speed until it breathes right.

One honest note: anyone on the same network who has the address can move the knobs. On your studio Wi-Fi or a private show network that is the convenience working as intended. On a network you do not control, do not leave it up.

In plain terms: the tuning knobs come off the laptop and into your hand, so you adjust the piece from where the audience stands.

The `RemoteSurface` example serves a tunable aurora with every control family. It draws its own address at the bottom of the canvas, so the piece tells you how to reach it:

```sh
swift run --package-path Examples Example-Integration-RemoteSurface
```


## Living in the system

A wall is one place a piece can wait. Your own machine is another, and it is a much shorter walk. Every Mac already has a screen that goes idle several times a day. It also has a list of things it could show while it does. Putting your sketch in that list takes two commands.

```sh
ollin new Ripple --kind screen-saver
cd Ripple && ./build.sh --install
```

Open System Settings, go to Screen Saver, and there it is. Nothing about the sketch changed to get there. It is the same class you would run in a window, and you can still open it in a window while you work on it.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Images/32-Installations/LivingInTheSystem-dark.jpg">
  <img src="Images/32-Installations/LivingInTheSystem.jpg" alt="A diagram in two columns: on the left, three stacked cards for the files inside Ripple.saver, with an arrow joining the NSPrincipalClass line in the property list to the matching @objc name in the code; on the right, two wide black screens showing a drawing filling one edge to edge and sitting square in the middle of the other" width="680">
</picture>

A screen saver is not a program. It is a plug-in: a folder called `Ripple.saver` holding one binary, which the system loads when it needs something to show. So there is no `@main` anywhere, and one small class stands in for it:

```swift
@objc(RippleSaverView)
final class RippleSaverView: SketchSaverView {
    override func makeSketch() -> Sketch { Ripple() }
}
```

That is the whole of the wiring. `SketchSaverView` builds the canvas when the system starts the saver. It runs the frames off the display's own clock, and puts everything away when the saver is over. `@objc` pins the name so the property list can point at it.

### Two things are different, and neither is the framework's idea

**Your sketch gets no input.** A key or a click ends a screen saver. That is what a screen saver is for. A canvas that answered the click would be a canvas that swallowed it, leaving somebody hammering at a machine that will not come back. So the canvas stays out of the way entirely, and `mouseX`, `mouseY`, and `key` hold whatever they started at. Write the piece to run on `time` alone, which is how most of this guide's sketches already run.

**Your sketch cannot write files.** The system loads a screen saver into a sandbox that reads anything and writes almost nothing. Pictures, fonts, meshes, and clips all load as they always did. Exporting a frame does not, and neither does a checkpoint. None of that belongs in a screen saver anyway.

### Filling the screen, or sitting in the middle of it

A display is almost never the shape of a canvas. Which of the two you get is the sketch's own `windowMode`, the same property that decides it in a window:

```swift
override var windowMode: WindowMode { .resizable }
```

With that line, the canvas *is* the display: `width` and `height` are the screen's, and the drawing goes edge to edge. `ollin new` writes it for you, because filling the screen is what people mean by a screen saver. Take it out and a square sketch stays square, as large as fits, centered on black. Neither one stretches the drawing, which is the answer you want either way: a circle stays a circle on a wide screen.

### Building it again

Every edit needs a rebuild, so do the work in a window and install when it looks right:

```sh
ollin Sources/Ripple/Sketch.swift     # the same file, reloading as you save
./build.sh --install                  # when you are happy with it
```

The script signs the saver for this machine. Another Mac will refuse it. Handing a screen saver to somebody else needs a Developer ID and a trip through notarization, the same as an app. [The reference page](../Docs/Output/ScreenSaver.md) has those commands.

One more thing worth knowing before you build something ambitious for it. The system makes a separate saver for each display, so two screens run two copies of your sketch, each from its own first frame. They are not in step and they do not share anything. A piece that has to line up across two screens is the installation earlier in this chapter, not a screen saver.

## The desktop and the menu bar

The screen saver waits for you to leave. Two more surfaces work while you stay. The desktop can run a sketch behind the icons, and the menu bar can hold a moving strip of one beside the clock. Each is two commands, and the sketch stays an ordinary sketch.

```sh
ollin new Drift --kind wallpaper
cd Drift && swift run Drift
```

The desktop becomes the piece. Windows still stack over it, icons still sit on it, and clicks still land where they always did. The piece takes no input at all. A small sparkle appears at the right end of the menu bar, and its menu is the way out. Each display runs its own copy, edge to edge. `./build.sh --install` makes it an app in /Applications. Add that app to your Login Items and it is the machine's wallpaper for good.

It earns one honest note about cost. Wallpaper draws at the display's rate for as long as the machine is up, through every meeting and every compile. Calm pieces wear well here, and a still one can call `noLoop()` and cost nothing at all.

The menu bar is the same idea at the other extreme of size:

```sh
ollin new Pulse --kind menu-bar
cd Pulse && swift run Pulse
```

A strip 56 points wide appears among the status items and starts moving. It draws at 30 frames a second, a rate a surface that never goes away can afford. The sketch inside sees a canvas of the strip's own points, so `width / 2` is still the middle and everything this guide taught still works. It is simply the smallest canvas you will ever draw on. A click opens the strip's menu, and Quit is there.

Both kinds write the same wrapper the next section describes, plus one line that keeps the app out of the Dock. A program with no window has nothing to show from a Dock icon. The reference pages ([wallpaper](../Docs/Output/Wallpaper.md), [menu bar](../Docs/Output/MenuBar.md)) carry the rest, the strip's width knob among them.

## An app to hand somebody

The screen saver lives on your own machine. The other thing a finished piece wants is to leave. It goes to a friend who has never typed `swift`, or to the gallery machine that will run the wall for a month. That is an app, and the path is the same two commands.

```sh
ollin new Orbit --kind mac-app
cd Orbit && ./build.sh
```

`Orbit.app` appears beside the script. Double-click it and the sketch opens in its window, the same window `swift run` would have given you. Nothing about the sketch changed on the way in. It keeps its `@main`, its mouse, its keyboard, and every export flag. The app is a wrapper, not a port, so you keep working in a window (`ollin Sources/Orbit/Sketch.swift`) and wrap when it looks right.

Two of the wrapper's choices are worth knowing.

**The icon is the sketch.** The script runs the binary it just built, renders one frame, and folds that picture into the icon the Finder shows. The piece wears its own face, and the face changes as the piece does. Drop an `AppIcon.icns` beside `build.sh` when you would rather choose it yourself.

**The signature decides how far it travels.** `./build.sh` alone signs the app for this machine and says so every time, so nobody ships one by accident. Handing it to somebody else takes a Developer ID and one more flag:

```sh
./build.sh --sign "Developer ID Application: Your Name (TEAMID)" --notarize ollin-notary
```

That signs with the hardened runtime, sends the app through Apple's notary, and leaves an `Orbit.zip` beside the app, ready to send. Any Mac opens what is inside. [The reference page](../Docs/Output/App.md) has the one-time setup behind the `ollin-notary` name.

The app is also how the wall piece below reaches its wall. A sketch that declares an `Installation` keeps it inside the app, so the double click opens the piece full screen, unattended, hours and all. The machine that runs it never needs the repo or the toolchain, only the app.

## Putting it together: the wall piece

The finished piece is one you could hang. Everything a room needs is in its declaration, and the drawing itself is deliberately calm, because a piece that stays up for a week is a different kind of thing from one that has to hold a scroll. Make `MySketches/WallPiece.swift`.

The first part is what the room needs to know. One `Installation` says fill the screen and keep it awake, write a checkpoint every minute, restart if you ever stall, and open and close with the building. `loopDuration` says the piece repeats every three minutes, which is what lets a shader clock stay small and a viewer feel the piece has a shape.

```swift
import Ollin
import OllinDMX

final class WallPiece: Sketch {
    override var canvasSize: CanvasSize { .size(1280, 720) }

    /// Everything the room needs to know, in one declaration.
    override var installation: Installation {
        Installation(checkpoint: .every(seconds: 60),
                     restarts: .onFailure,
                     schedule: [.from(6, "dawn"), .from(10, "day"),
                                .from(18, "dusk"), .from(21, "night")])
    }

    /// Three minutes a lap, so the piece is exactly where it was every three
    /// minutes and the shader clock never has to count a week.
    override var loopDuration: Double? { 180 }

    /// Which part of the day to draw. Leave it nil on the wall and the schedule
    /// answers; name one here to see any hour without waiting for it.
    let showing: String? = "dusk"
    var period: String { showing ?? scheduledPeriod ?? "day" }

    let palettes: [String: [Color]] = [
        "dawn":  [Color(hex: 0x1B1B2E), Color(hex: 0x5B4A78), Color(hex: 0xD98E73), Color(hex: 0xF3D9A4)],
        "day":   [Color(hex: 0x16324A), Color(hex: 0x3E7CA6), Color(hex: 0x9FD2E0), Color(hex: 0xF4F1E4)],
        "dusk":  [Color(hex: 0x140F1E), Color(hex: 0x53264A), Color(hex: 0xC7503F), Color(hex: 0xF0A860)],
        "night": [Color(hex: 0x05070F), Color(hex: 0x122744), Color(hex: 0x2E5C7A), Color(hex: 0x8FB8CE)],
    ]

    let leds = LEDMap(sender: DMXSender())

    override func setup() {
        noStroke()
        // The wall under the screen: one run of lamps reading the canvas above
        // them. After this the piece draws as if they were not there.
        leds.addStrip(from: Vector2(90, Double(height) - 54),
                      to: Vector2(Double(width) - 90, Double(height) - 54), leds: 96)
        extend(leds)
    }

```

The second part is the drawing, and it holds nothing between frames. Every bar's height comes from where it stands and how far along the lap the piece is, so a restart in the small hours puts it back exactly where the checkpoint left it. Nothing accumulates, so nothing drifts over a week.

```swift
    override func draw() {
        let ramp = Ramp(palettes[period] ?? palettes["day"]!)
        background(ramp.color(at: 0))

        // One lap of the loop, so nothing in the picture depends on how long the
        // machine has been switched on.
        let lap = loopProgress(over: 180) * .tau
        let columns = 96
        let step = Double(width) / Double(columns)

        for i in 0 ..< columns {
            let u = (Double(i) + 0.5) / Double(columns)
            // Three slow waves that share one lap, so their sum repeats with it.
            let swell = sin(lap + u * .tau) * 0.5
                      + sin(lap * 2 - u * .tau * 2) * 0.3
                      + sin(lap * 3 + u * .tau * 3) * 0.2
            let t = swell * 0.5 + 0.5
            let tall = Double(height) * (0.16 + t * 0.6)
            fill(ramp.color(at: 0.15 + t * 0.85))
            drawRect(corner: Vector2(Double(i) * step, Double(height) - tall - 90),
                     width: step - 1.5, height: tall)
        }

        // The band the lamps read, kept plain so a strip over it glows steadily.
        for i in 0 ..< columns {
            let u = (Double(i) + 0.5) / Double(columns)
            let t = sin(lap + u * .tau) * 0.5 + 0.5
            fill(ramp.color(at: 0.2 + t * 0.7))
            drawRect(corner: Vector2(Double(i) * step, Double(height) - 84),
                     width: step - 1.5, height: 60)
        }
    }
}
```

<img src="Images/32-Installations/WallPiece.jpg" alt="The finished wall piece at dusk: a slow field of bars from deep plum through red to orange, with the plain band along the bottom that the lamps read" width="680">

Read the declaration back and it is a list of the things this chapter is about. The screen saver never comes on. A power cut costs at most a minute. A stall fixes itself in the small hours with nobody there. The piece is dark outside opening hours, and it is a different color at dawn than at dusk. And the strip of lamps under it is lit by the same drawing, because an `LEDMap` reads the canvas rather than being told about it.

Then make it yours:

- Take `showing` off `"dusk"` by setting it to nil, and the piece follows the real clock. Set it to `"dawn"` to see the morning at any hour.
- Add `projection:` and press Command-K, then drag the corners onto a wall that is not square to the projector.
- Give it a second display with `displays: .spanning`, and make the piece read `displayIndex` so the two halves are not the same picture.
- Put the strip on a curve instead of a line, or add a matrix over the middle of the canvas.
- Run it as `swift run --package-path Examples Example-Installation-Unattended --no-installation` first, so you can work on it in an ordinary window.

## Where this comes from

DMX512 was standardized by the United States Institute for Theatre Technology in 1986, and it is still what a lighting desk speaks. It survived that long by being simple: 512 numbers, sent over and over, with nothing to negotiate. The two ways this chapter puts it on a network are later work on the same idea, Art-Net from Artistic Licence and sACN as ANSI E1.31. Correcting a projected rectangle onto a surface it is not square to is a projective homography, the same mathematics behind perspective in a camera. Edge blending two projectors into one picture is stage practice older than either.

A piece that has to run unattended is a reliability problem rather than a graphics one, and the answers here are the ordinary ones: bound the step, write down what you can lose, and restart when you stop. Full credits are in the project's [attribution notes](../ATTRIBUTION.md).

## Go deeper

- [Installation](../Docs/Output/Installation.md): leaving a piece running, what each part of the declaration turns on, the checkpoint file's shape, the schedule's parts, projection and blending, and several displays.
- [Screen saver](../Docs/Output/ScreenSaver.md): the project the generator writes, the sandbox a saver runs in, filling against fitting, and signing one for somebody else's machine.
- [DMX](../Docs/Integration/DMX.md): universes and fixtures, Art-Net and sACN, the send cadence, the console-drives-the-sketch direction, and the LED map's sampling.
- [Profiling](../Docs/Tools/Profiling.md): reading the cost row, what to do about each answer, and capturing a frame for a closer look.
- [Remote](../Docs/Integration/Remote.md): the `@Param` knobs served to a phone as touch controls, what each kind becomes, how values land, and the network honesty.
- [Room](../Docs/Integration/Room.md): several machines joining by name, the three ways to read what arrives, shared knobs, the clock they agree on and what it costs, seats, and who can join.
- Worked examples, in [`Examples/Installation/`](../Examples/Installation/): `Unattended` (the one-line declaration), `Resuming`, `Watched`, `Hours`, `Fitted`, `ManyDisplays`, and `ManyWindows`, plus [`Examples/Integration/DMXLoopback`](../Examples/Integration/DMXLoopback/Sketch.swift), [`Examples/Integration/LEDMapping`](../Examples/Integration/LEDMapping/Sketch.swift), [`Examples/Integration/RemoteSurface`](../Examples/Integration/RemoteSurface/Sketch.swift), [`Examples/Integration/RoomCanvas`](../Examples/Integration/RoomCanvas/Sketch.swift), and [`Examples/Integration/RoomLoopback`](../Examples/Integration/RoomLoopback/Sketch.swift).

---

[Contents](README.md#contents) · Previous: [Chapter 31, Sharing and performing](31-SharingAndPerforming.md) · Next: [Appendix A, Just enough Swift](A-JustEnoughSwift.md)
