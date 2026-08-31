#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Integration](./README.md) → `Link`</sup>

---

## Link

Move on the same beat as the whole room. Link is the tempo-sync protocol most music software speaks, made known by Ableton Link. Apps on one machine or across a local network find each other, agree on one tempo, and align their bar phase. There is no cabling and no setup. A sketch that joins pulses with the DAW, the drum machine app on a phone, and every other sketch in the session. It lives in a separate library so the drawing core stays free of networking. Add `import OllinLink` alongside `import Ollin` to reach it.

Ollin's implementation is independent, written from published protocol documentation; no SDK is vendored. It is compatible with Link-enabled apps and is not affiliated with or endorsed by Ableton.

The usual shape is one [`LinkClock`](#linkclock): start it in `setup()`, read musical time in `draw()`.

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

Alone, the clock free-runs at its own tempo. The sketch moves the same with or without a session to join, and `peerCount` says which is happening.

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

`start()` begins announcing on every network interface, loopback included, so two sketches on one machine sync with no network at all. Starting always begins with a fresh identity: a restarted sketch joins the running session instead of imposing its old state on it.

The first join on a Mac can ask for the Local Network permission, the same prompt OSC and DMX get. A sketch run from a terminal inherits the terminal's answer.

<a name="reading-musical-time"></a>

### Reading musical time

The reads mirror [`TempoClock`](MIDI.md#tempo-sync-tempoclock), the MIDI-clock sibling, so a sketch written against one moves to the other unchanged:

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

One difference from the MIDI clock is part of the protocol's model: the beat grid never stops. `beats` always advances, even while the shared transport reads stopped, so a session with no transport user still has a beat to move on.

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

The flag is advisory. The beat runs either way, and a session where nobody touches transport simply stays `false`.

<a name="bars-and-the-quantum"></a>

### Bars and the quantum

`beatsPerBar` (default 4) is also the session *quantum*: the bar length the phase alignment works over. Every participant that declares the same value lands its downbeats at the same instant, which is the whole point of joining:

```swift
link.beatsPerBar = 4
let sweep = link.barPhase          // two machines set to 4 sweep together
let downbeat = link.barPhase < 0.05
```

Participants with different quanta still share the tempo and the beat; only the bar grouping differs. `beats` itself is per-participant (each one counts from around zero at its own start); the fractional beat and the bar phase are what align.

<a name="how-the-session-works"></a>

### How the session works

Three mechanisms, all automatic:

- **Discovery.** Participants announce themselves a few times a second over UDP multicast and expire when they fall silent, so the session tracks who is in the room with no server.
- **Clock sync.** On meeting a new session, the clock runs a burst of ping/pong exchanges against one of its members and takes the median offset, mapping the machine's own clock onto the session's shared one. It re-measures every half minute to track drift.
- **One session wins.** When two sessions meet, everyone joins the older one, so a newcomer never disturbs a running set. A tempo change is a proposal stamped onto the session timeline; the latest proposal wins, whoever makes it. The last participant left standing keeps the tempo and the beat, so being alone is seamless.

<a name="trying-it-without-a-rig"></a>

### Trying it without a rig

Run the example twice, in two terminals:

```sh
swift run Example-Integration-LinkTempo
```

The two windows find each other over loopback, settle on one tempo, and light the same bar dot at the same moment. Turn one window's BPM knob and both follow. Quit one and the other keeps the beat without a hiccup. Anything else that speaks Link joins the same way, on this machine or on the same network.

---

#### See also

- [`MIDI`](MIDI.md) - the wire sibling: `TempoClock` follows MIDI clock from a DAW or DJ gear
- [`OSC`](OSC.md) - networked control values, for everything that is not a beat
- [`Audio`](../Helpers/Audio.md) - beats *heard* in sound, when there is no session to join
