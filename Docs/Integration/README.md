#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → Integration</sup>

---

## Integration

- [`OSC`](./OSC.md) - `import OllinOSC` to send and receive OSC messages over UDP (to and from TouchOSC, Max/MSP, TouchDesigner, …), read in `draw()` or bound to a `@Param`
- [`MIDI`](./MIDI.md) - `import OllinMIDI` to read from and send to MIDI controllers and keyboards over Core MIDI, read in `draw()` or bound to a `@Param`, and to lock motion to MIDI clock with a `TempoClock`
- [`Serial`](./Serial.md) - `import OllinSerial` to read a USB microcontroller's sensor lines in `draw()` (or bound to a `@Param`) and write lines back to drive servos and LEDs: IOKit discovery, automatic reconnection, the classic physical-computing loop
- [`DMX`](./DMX.md) - `import OllinDMX` to drive stage lights and dimmers from `draw()` over Art-Net or sACN (a `DMXUniverse` of 512 channels with named-fixture sugar), to send the canvas's own pixels to LED strips and matrices (`LEDMap`, sampled on the GPU each frame), and to let a lighting console drive a sketch, channels read in `draw()` or bound to a `@Param`
- [`Syphon`](./Syphon.md) - `import OllinSyphon` to share live visuals with other Mac apps (openFrameworks, Resolume, MadMapper, VDMX, …): publish a sketch's frames as a Syphon source, and draw an incoming Syphon feed as an `Image`
- [`Virtual camera`](./VirtualCamera.md) - `import OllinCamera` to feed a sketch's frames to the Ollin Camera system camera, so webcam apps and browser tools (Zoom, OBS, Hydra via `getUserMedia`, …) read the sketch as a live camera
- [`Game controllers`](./Controller.md) - `import OllinController` to read a game controller in `draw()`: sticks, triggers and buttons on any pad, plus motion and a touchpad on hardware that has them, with several players at once
- [`Screen capture`](./ScreenCapture.md) - `import OllinScreen` to take any display, app, or window on the Mac as a live GPU-textured frame source, drawn and filtered like any image and read by the vision trackers; the non-cooperative counterpart to Syphon, including the feedback tunnel when a sketch captures the screen it is drawn on
