#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → Integration</sup>

---

## Integration

- [`OSC`](./OSC.md) - `import OllinOSC` to send and receive OSC messages over UDP (to and from TouchOSC, Max/MSP, TouchDesigner, …), read in `draw()` or bound to a `@Param`
- [`MIDI`](./MIDI.md) - `import OllinMIDI` to read from and send to MIDI controllers and keyboards over Core MIDI, read in `draw()` or bound to a `@Param`, and to lock motion to MIDI clock with a `TempoClock`
- [`Syphon`](./Syphon.md) - `import OllinSyphon` to share live visuals with other Mac apps (openFrameworks, Resolume, MadMapper, VDMX, …): publish a sketch's frames as a Syphon source, and draw an incoming Syphon feed as an `Image`
- [`Virtual camera`](./VirtualCamera.md) - `import OllinCamera` to feed a sketch's frames to the Ollin Camera system camera, so webcam apps and browser tools (Zoom, OBS, Hydra via `getUserMedia`, …) read the sketch as a live camera
- [`Game controllers`](./Controller.md) - `import OllinController` to read a game controller in `draw()`: sticks, triggers and buttons on any pad, plus motion and a touchpad on hardware that has them, with several players at once
- [`Screen capture`](./ScreenCapture.md) - `import OllinScreen` to take any display, app, or window on the Mac as a live GPU-textured frame source, drawn and filtered like any image and read by the vision trackers; the non-cooperative counterpart to Syphon, including the feedback tunnel when a sketch captures the screen it is drawn on
