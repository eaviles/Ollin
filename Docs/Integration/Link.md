#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Integration](./README.md) → `Link`</sup>

---

## Link

Link lets a sketch move on the same beat as the whole room. It is the tempo-sync protocol most music software speaks. Ableton Link is what made it known. Apps on one machine or across a local network find each other, agree on one tempo, and align their bar phase. There is no cabling and no setup. Once a sketch joins, it pulses with the DAW, with the drum machine app on a phone, and with every other sketch in the session. Link lives in a separate library, so the drawing core stays free of networking. Add `import OllinLink` beside `import Ollin` to use it.

Ollin's implementation is independent. It is written from the published protocol documentation, and no SDK is vendored. It works with Link-enabled apps. Ollin is not affiliated with Ableton and is not endorsed by Ableton.

The usual shape is one [`LinkClock`](#linkclock). You start it in `setup()` and read musical time in `draw()`.

```swift
import Ollin
import OllinLink

final class OnTheBeat: Sketch {
    let link = LinkClock(tempo: 120)

    override func setup() { link.start() }

    override func draw() {
        let throb = 1 + 0.2 * link.beat                 // snaps on each beat, decays
        drawCircle(width / 2, height / 2, 120 * throb * scale)
        rotate(link.progress(over: 8) * .tau)           // one turn every 8 beats
    }
}
```

When there is no session to join, the clock free-runs at its own tempo. The sketch moves the same way with or without a session, and `peerCount` tells you which is the case.

### Contents

- [LinkClock](#linkclock) - join, leave, and who is there
- [Reading musical time](#reading-musical-time) - the same reads as the MIDI `TempoClock`
- [Tempo and transport](#tempo-and-transport) - propose a tempo, start and stop together
- [Bars and the quantum](#bars-and-the-quantum) - why downbeats land together
- [How the session works](#how-the-session-works) - discovery, clock sync, and who wins
- [Trying it without a rig](#trying-it-without-a-rig) - two copies of one example

<a name="linkclock"></a>

### LinkClock

```swift
let link = LinkClock(tempo: 120)   // the tempo it free-runs at, 20…999 BPM

link.start()                       // join the local network's session
link.stop()                        // leave it (peers are told goodbye)
link.isRunning                     // whether the clock participates
link.peerCount                     // how many other participants are in the session
```

`start()` begins announcing on every network interface, loopback included, so two sketches on one machine sync with no network at all. Each start uses a fresh identity, which means a restarted sketch joins the running session instead of imposing its old state on it.

On a Mac, the first join can ask for the Local Network permission. This is the same prompt OSC and DMX get. A sketch run from a terminal inherits the terminal's answer.

<a name="reading-musical-time"></a>

### Reading musical time

The reads mirror those of [`TempoClock`](MIDI.md#tempo-sync-tempoclock), the MIDI-clock sibling, so a sketch written against one moves to the other unchanged:

```swift
link.tempo             // BPM, the session's current tempo
link.beats             // continuous musical time in quarter notes: 2.5 is halfway through beat 3
link.beatCount         // its whole part
link.phase             // its fractional part, 0…1 through the current beat
link.beat              // a ready-made 0…1 pulse: snaps to 1 on the beat, decays over ~0.25 s
link.timeSinceBeat     // seconds since the last beat landed
link.bar               // which bar, over beatsPerBar
link.barPhase          // 0…1 through the current bar, aligned across the session
link.progress(over: 8) // a 0…1 ramp across any number of beats, wraps
```

One difference from the MIDI clock comes from the protocol's model. The beat grid never stops. `beats` always advances, even while the shared transport reads stopped. So a session where nobody uses the transport still has a beat to move on.

<a name="tempo-and-transport"></a>

### Tempo and transport

Any participant may propose a tempo, and the session follows the latest change:

```swift
link.tempo = 138       // proposes 138 BPM to the whole session, effective now
```

`isPlaying` is the session's shared start/stop flag. Apps that use transport sync start and stop together on it:

```swift
if link.isPlaying { /* the room's transport is running */ }
link.isPlaying = true  // starts everyone who listens to the shared transport
```

The flag is advisory. The beat runs either way, and in a session where nobody touches the transport the flag stays `false`.

<a name="bars-and-the-quantum"></a>

### Bars and the quantum

`beatsPerBar` (default 4) is also the session *quantum*, the bar length that the phase alignment works over. Every participant that declares the same value lands its downbeats at the same instant, which is the reason to join a session:

```swift
link.beatsPerBar = 4
let sweep = link.barPhase          // two machines set to 4 sweep together
let downbeat = link.barPhase < 0.05
```

Participants with different quanta still share the tempo and the beat. Only the bar grouping differs. `beats` itself is per-participant, because each one counts from around zero at its own start. The fractional beat and the bar phase are the values that align.

<a name="how-the-session-works"></a>

### How the session works

Three mechanisms run the session, and all of them are automatic:

- **Discovery.** Participants announce themselves a few times a second over UDP multicast, and they expire when they fall silent. So the session needs no server to track who is in the room.
- **Clock sync.** When the clock meets a new session, it runs a burst of ping/pong exchanges against one of its members. It takes the median offset from that burst, and the offset maps the machine's own clock onto the session's shared one. The clock re-measures every half minute to track drift.
- **One session wins.** When two sessions meet, everyone joins the older one, so a newcomer never disturbs a running set. A tempo change is a proposal stamped onto the session timeline. The latest proposal wins, whoever makes it. The last participant left keeps the tempo and the beat, so being alone changes nothing.

<a name="trying-it-without-a-rig"></a>

### Trying it without a rig

Run the example twice, in two terminals:

```sh
swift run Example-Integration-Tempo
```

The two windows find each other over loopback, settle on one tempo, and light the same bar dot at the same moment. Adjust the BPM parameter in one window and both follow. Quit one window and the other keeps the beat without a break. Anything else that speaks Link joins the same way, on this machine or on the same network.

---

#### See also

- [`MIDI`](MIDI.md) - the wired sibling: `TempoClock` follows MIDI clock from a DAW or DJ gear
- [`OSC`](OSC.md) - networked control values, for everything that is not a beat
- [`Audio`](../Helpers/Audio.md) - beats detected in the sound itself, when there is no session to join
