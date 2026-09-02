#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → Integration</sup>

---

## Integration

- [`OSC`](./OSC.md) - `import OllinOSC` to send and receive OSC messages over UDP (to and from TouchOSC, Max/MSP, TouchDesigner, …), read in `draw()` or bound to a `@Param`
- [`MIDI`](./MIDI.md) - `import OllinMIDI` to read from and send to MIDI controllers and keyboards over Core MIDI, read in `draw()` or bound to a `@Param`, and to lock motion to MIDI clock with a `TempoClock`
- [`Link`](./Link.md) - `import OllinLink` to join the local network's shared tempo-and-phase session (the Link protocol most music apps speak), so a sketch moves on the same beat and lands the same downbeat as the whole rig, with no cabling or setup
- [`Serial`](./Serial.md) - `import OllinSerial` to read a USB microcontroller's sensor lines in `draw()` (or bound to a `@Param`) and write lines back to drive servos and LEDs: IOKit discovery, automatic reconnection, the classic physical-computing loop
- [`Bluetooth`](./Bluetooth.md) - `import OllinBluetooth` to read a Bluetooth Low Energy sensor in `draw()` (or bound to a `@Param`) and write back to it: the room in range, connection that waits and returns by itself, the standard's own values already named, and the permission the first run has to get past
- [`Remote`](./Remote.md) - `import OllinRemote` to serve the sketch's `@Param` parameters to a phone or a second machine on the local network: a touch surface in any browser, live both ways, for tuning an installation from in front of it
- [`Room`](./Room.md) - `import OllinRoom` to let several machines on one network draw one piece: they find each other by the room's name with no server, trade values and `@Param` parameters, agree on one clock so motion stays in step, and take a seat each when the piece is split across screens
- [`DMX`](./DMX.md) - `import OllinDMX` to drive stage lights and dimmers from `draw()` over Art-Net or sACN (a `DMXUniverse` of 512 channels with named-fixture sugar), to send the canvas's own pixels to LED strips and matrices (`LEDMap`, sampled on the GPU each frame), and to let a lighting console drive a sketch, channels read in `draw()` or bound to a `@Param`
- [`Laser`](./Laser.md) - `import OllinLaser` to draw with a show laser from `draw()`: line work optimized into the point stream a projector actually scans (spacing, corner and blanking dwell, path order, the point budget), guarded by an arm gate and a stopped-beam rule, streamed to a network DAC or written as an ILDA file
- [`Syphon`](./Syphon.md) - `import OllinSyphon` to share live visuals with other Mac apps (openFrameworks, Resolume, MadMapper, VDMX, …): publish a sketch's frames as a Syphon source, and draw an incoming Syphon feed as an `Image`
- [`Virtual camera`](./VirtualCamera.md) - `import OllinCamera` to feed a sketch's frames to the Ollin Camera system camera, so webcam apps and browser tools (Zoom, OBS, Hydra via `getUserMedia`, …) read the sketch as a live camera
- [`Game controllers`](./Controller.md) - `import OllinController` to read a game controller in `draw()`: sticks, triggers and buttons on any pad, plus motion and a touchpad on hardware that has them, with several players at once
- [`Haptics`](./Haptics.md) - `import OllinHaptics` to put touch under the hand beside the picture: a designed pattern of taps and hums composed like a phrase and played from `draw()`, translated for the trackpad's three feelings and one strength, and played as written where a full haptic engine exists
- [`Screen capture`](./ScreenCapture.md) - `import OllinScreen` to take any display, app, or window on the Mac as a live GPU-textured frame source, drawn and filtered like any image and read by the vision trackers; the non-cooperative counterpart to Syphon, including the feedback tunnel when a sketch captures the screen it is drawn on
