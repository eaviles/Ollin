#### <sup>[Ollin](../../README.md) → [Examples](../README.md) → Integration</sup>

---

## Integration

Sketches that talk to the other apps and gear in a rig: control in over OSC and MIDI, visuals out (and in) over Syphon, and the sketch itself as a system-wide virtual camera. Each integration lives in its own library — `import OllinOSC`, `import OllinMIDI`, `import OllinSyphon`, `import OllinCamera` — see the [OSC](../../Docs/OSC.md), [MIDI](../../Docs/MIDI.md), [Syphon](../../Docs/Syphon.md), and [Virtual camera](../../Docs/VirtualCamera.md) references.

| Example | What it shows |
|---|---|
| [OSCLoopback](OSCLoopback/Sketch.swift) | self-contained round-trip — sends an animated position to itself on `127.0.0.1` and draws the dot from what it *receives*, so the picture is the round-trip; no second app needed (`OSCSender`, `OSCReceiver`) |
| [OSCMonitor](OSCMonitor/Sketch.swift) | listens for OSC and prints/draws every message — point TouchOSC or any OSC source at this Mac to discover what its controls send (`OSCReceiver.messages()`) |
| [MIDILoopback](MIDILoopback/Sketch.swift) | self-contained — a virtual source sends stepped CC to itself and a bound, smoothed `@Param` glides toward each step; runs with no hardware (`MIDIOutput.openVirtual`, `MIDIInput.bind`, `@Param` smoothing) |
| [MIDIMonitor](MIDIMonitor/Sketch.swift) | lists every MIDI source and prints/draws each message — connect a controller and discover what each knob and pad sends by touching it (`MIDIInput.messages()`) |
| [SyphonLoopback](SyphonLoopback/Sketch.swift) | publishes its own frames as a Syphon source *and* subscribes to them, so the recursive feedback-tunnel inset is the round-trip made visible; open Syphon's Simple Client to see it cross-app (`publishSyphon`, `SyphonClient`) |
| [SyphonViewer](SyphonViewer/Sketch.swift) | subscribes to any external Syphon source (openFrameworks, Resolume, …) and draws it letterboxed, listing what it sees while it waits (`SyphonClient`, `availableServers`) |
| [VirtualCamera](VirtualCamera/Sketch.swift) | publishes the sketch to the system-wide **Ollin Camera**, so Photo Booth, QuickTime, Zoom, and any browser read it as a live webcam — a broadcast-style "on air" scene so the feed is obviously live; needs the camera extension installed once, and explains what to do when it isn't (`publishVirtualCamera`) |

Run one with `swift run Example-<Name>`, e.g. `swift run Example-OSCLoopback`.
