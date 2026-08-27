#### <sup>[Ollin](../../README.md) → [Examples](../README.md) → Integration</sup>

---

## Integration

Sketches that talk to the other apps and gear in a rig: control in over OSC, MIDI, a serial board, a game controller, or a phone's browser; visuals out (and in) over Syphon, as a system-wide virtual camera, as stage light, as LEDs, or as a laser; the Mac's own screen taken as material; and touch put back under the hand as a felt pattern.

Each integration lives in its own library, so a sketch links only what it uses: `import OllinOSC`, `import OllinMIDI`, `import OllinSerial`, `import OllinRemote`, `import OllinDMX`, `import OllinLaser`, `import OllinSyphon`, `import OllinCamera`, `import OllinScreen`, `import OllinController`, `import OllinHaptics`. The references are [OSC](../../Docs/Integration/OSC.md), [MIDI](../../Docs/Integration/MIDI.md), [Serial](../../Docs/Integration/Serial.md), [Remote](../../Docs/Integration/Remote.md), [DMX](../../Docs/Integration/DMX.md), [Laser](../../Docs/Integration/Laser.md), [Syphon](../../Docs/Integration/Syphon.md), [Virtual camera](../../Docs/Integration/VirtualCamera.md), [Screen capture](../../Docs/Integration/ScreenCapture.md), [Game controllers](../../Docs/Integration/Controller.md), and [Haptics](../../Docs/Integration/Haptics.md).

Several of these run both ends themselves, so they need no second app and no hardware: the round trip you watch is the real wire on loopback.

| Example | What it shows |
|---|---|
| [OSCLoopback](OSCLoopback/Sketch.swift) | self-contained round trip: sends an animated position to itself on `127.0.0.1` and draws the dot from what it *receives*, so the picture is the round trip; no second app needed (`OSCSender`, `OSCReceiver`) |
| [OSCMonitor](OSCMonitor/Sketch.swift) | listens for OSC and prints/draws every message: point TouchOSC or any OSC source at this Mac to discover what its controls send (`OSCReceiver.messages()`) |
| [MIDILoopback](MIDILoopback/Sketch.swift) | self-contained: a virtual source sends stepped CC to itself and a bound, smoothed `@Param` glides toward each step; runs with no hardware (`MIDIOutput.openVirtual`, `MIDIInput.bind`, `@Param` smoothing) |
| [MIDIMonitor](MIDIMonitor/Sketch.swift) | lists every MIDI source and prints/draws each message: connect a controller and discover what each knob and pad sends by touching it (`MIDIInput.messages()`) |
| [TempoSync](TempoSync/Sketch.swift) | visuals locked to MIDI clock: an internal timer sends the sync messages to itself and a `TempoClock` drives the beat throb, the bar dots, and an eight-beat orbit; point a DAW or DJ mixer at the Mac and the same sketch follows that (`TempoClock`, `MIDIOutput.openVirtual`) |
| [SerialLoopback](SerialLoopback/Sketch.swift) | the physical-computing loop with no board: a fake device on one side of a pty pair prints a sensor number thirty times a second while a real `SerialPort` reads the other side, so the trace is what arrived over the wire; a click writes a line back and the wave flips (`SerialPort`, `latestLine`) |
| [SerialMonitor](SerialMonitor/Sketch.swift) | every serial device on this Mac, live: the first USB one opens by itself, its lines scroll up the screen, a numeric line also fills a value bar, and an unplug reconnects on its own; 1-9 opens a specific device and space writes back (`SerialPort.availableDevices()`, `matching:`) |
| [RemoteSurface](RemoteSurface/Sketch.swift) | a tunable aurora served to your phone: a `RemoteInspector` on the extension seam starts a local-network server, and every `@Param` appears as a touch control in any browser on the same Wi-Fi, live both ways (`RemoteInspector`) |
| [DMXLoopback](DMXLoopback/Sketch.swift) | a full DMX round trip on screen: a `DMXSender` chases color through universe 1 over sACN on loopback, and the drawn stage of pars is lit from the *received* channels; point the sender at a node's IP and the same universe drives real lights (`DMXSender`, `DMXReceiver`, `DMXFixture`) |
| [LEDMapping](LEDMapping/Sketch.swift) | the canvas leaving the screen as LEDs: an `LEDMap` lays a 48-LED strip along a wave and a 12x8 matrix over the picture, samples the rendered pixels under them on the GPU each frame, and lights the drawn hardware from the universes that came back (`LEDMap`, `DMXSender`) |
| [LaserPreview](LaserPreview/Sketch.swift) | what a show laser makes of a drawing: the optimized point stream drawn the way the beam traces it, dark travel and all, with the knobs that decide what a frame costs and a readout of the point budget (`LaserFrame`, `LaserOptimizer`, `drawLaserPreview`) |
| [SyphonLoopback](SyphonLoopback/Sketch.swift) | publishes its own frames as a Syphon source *and* subscribes to them, so the recursive feedback-tunnel inset is the round trip made visible; open Syphon's Simple Client to see it cross-app (`publishSyphon`, `SyphonClient`) |
| [SyphonViewer](SyphonViewer/Sketch.swift) | subscribes to any external Syphon source (openFrameworks, Resolume, …) and draws it letterboxed, listing what it sees while it waits (`SyphonClient`, `availableServers`) |
| [VirtualCamera](VirtualCamera/Sketch.swift) | publishes the sketch to the system-wide **Ollin Camera**, so Photo Booth, QuickTime, Zoom, and any browser read it as a live webcam: a broadcast-style "on air" scene so the feed is obviously live; needs the camera extension installed once, and explains what to do when it isn't (`publishVirtualCamera`) |
| [ScreenCapture](ScreenCapture/Sketch.swift) | the Mac's own screen as material: a whole display, one app, or a single window arrives as a live image to draw and filter, and the `tunnel` knob leaves the sketch inside its own capture so the picture recedes into itself (`ScreenCapture`) |
| [ControllerInput](ControllerInput/Sketch.swift) | a game controller as a drawing instrument: the left stick steers a pen that leaves ink, the trigger sets how heavy the line is, the shoulders spin its heading, and on a pad that reports motion, tilting it tips the canvas so the ink runs downhill (`Controller`, `ControllerButton`) |
| [HapticRidges](HapticRidges/Sketch.swift) | a plate of ridges you drag across and feel: three strips of different spacing and crispness knock under the pointer as it crosses them, holding the button runs a hum whose strength follows the hand, and the bottom edge draws what the hardware was actually asked for (`HapticPattern`, `playHaptic`, `TrackpadPlan`) |

Run one with `swift run Example-Integration-<Name>`, e.g. `swift run Example-Integration-OSCLoopback`.
