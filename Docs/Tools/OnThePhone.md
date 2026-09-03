#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Tools](./README.md) → `The sketch on the phone`</sup>

---

## The sketch on the phone

A sketch written for the desk runs on an iPhone or an iPad as it is. The same Metal renderer, the same `draw()` at the display's refresh rate, the same shaders compiled from source at launch. A finger is the pointer, so `mouseX`, `mouseY`, and `mouseIsPressed` read the touch with no change, and a stylus fills `pressure`.

Working on it is one command:

```sh
ollin phone Sketch.swift
```

The sketch appears on the phone, and every save on the Mac puts the new version there. The phone's parameters open in a browser on the Mac, live in both directions. Stop the command when you are done; the app stays on the phone.

### Contents

- [What a save does](#what-a-save-does)
- [The parameters on the Mac](#the-parameters-on-the-mac)
- [What comes along](#what-comes-along)
- [The options](#the-options)
- [In an app of your own](#in-an-app-of-your-own)
- [What it needs](#what-it-needs)

### What a save does

A phone runs only code signed inside its app bundle. Nothing can be pushed into a running app the way the live window swaps a sketch on the desk. So a save is a small build and a reinstall, and the numbers make that fine:

| Step | Time |
|---|---|
| The framework, built for the phone | about 80 s, once |
| A save: the sketch recompiled, the app relinked and signed | 5 to 7 s |
| The app installed again, over Wi-Fi | about 2.5 s |

Under ten seconds from a save to the glass. The app writes its state down every second (the clock, the seed, every `@Param` value, every `@Saved` property) and reads it back when it launches, so a reinstall carries on mid-motion. An animation keeps its phase, and a value you tuned stays tuned. It is the desk's `--keep-clock`, kept on the phone.

Two things the phone decides. It must be unlocked for the Mac to open the app; locked, the new version is installed and waits for a tap. And it must be reachable: on the cable, or awake on the same network the Mac is on.

A compile error is printed at your own file and line, and the phone keeps running the last version until the next save.

### The parameters on the Mac

The app serves its `@Param` parameters through the [remote surface](../Integration/Remote.md), the same touch surface an installation is tuned from. The command prints the address and opens it:

```
  parameters  http://localhost:9330  or  http://Edgardos-iPhone.local:9330
```

Over the cable the surface is forwarded to `localhost`, which needs no network between the two. Over Wi-Fi it is the phone's own name. Drag a slider on the Mac and the phone follows between frames; tune something on the phone and the Mac shows it. A value you settle on is carried across every later save, since it is part of the state the app writes down. To put it into the file, type it in.

Shaders in a `.metal` file beside the sketch come along as resources, so a shader edit is one more save.

### What comes along

The sketch file is referenced where it is, never copied. Files beside it with a resource extension (images, sounds, video, fonts, data, meshes, `.metal` shaders) are copied into the app, and `Bundle.module` is the app, so `loadImage("photo.png", in: .module)` finds on the phone what it found on the desk. Drop a new file beside the sketch and the next save takes it along.

Every `import Ollin…` line links that satellite into the app. Ten have been built and run on a phone: `OllinRemote`, `OllinPhysics`, `OllinOSC`, `OllinMIDI`, `OllinController`, `OllinVideo`, `OllinBluetooth`, `OllinAudio`, `OllinVision`, and `OllinHaptics`. One outside that list is linked and named, so a build that fails on it has a first suspect. Five stay on the desk by nature and are refused with their reason: the virtual camera, Syphon, screen capture, and both ends of the phone-as-sensor link, since a phone cannot be its own peripheral.

The desk features stay on the desk: the export flags, the screen saver, the wallpaper, the menu bar piece, the display wall, the detached inspector panel, and the source-editing drag. A sketch that uses none of them is portable as written.

### The options

```
ollin phone Sketch.swift                  the loop: build, install, launch, watch
ollin phone Sketch.swift --once           build, install, launch, and stop
ollin phone Sketch.swift --fresh          start the sketch over, state forgotten
ollin phone Sketch.swift --device iPad    which paired device, by part of its name
ollin phone Sketch.swift --team ABCDE12345
ollin phone --devices                     the paired devices
```

The signing team is the flag, then `OLLIN_TEAM` in the environment, then the one the reference phone app in the checkout is signed with. The project the command writes lives under `~/Library/Caches/Ollin/Phone/`, one folder per sketch, with one shared build folder so the framework compiles for the phone once.

### In an app of your own

The command writes an app around the sketch, and `Apps/OllinSketchApp` in the checkout is the same shape by hand: an Xcode project with the framework as a local package, and a host that puts the sketch in a `SketchView`.

```swift
import SwiftUI
import Ollin

@main
struct MyApp: App {
    // `Scene` is spelled out: the framework has a 3D `Scene` of its own.
    var body: some SwiftUI.Scene {
        WindowGroup {
            SketchView(Waves(), onRunner: { runner in
                // Optional: the state written down and read back at launch.
                runner.beginInstallation(Installation(checkpoint: .every(seconds: 30)))
            })
            .ignoresSafeArea()
            .statusBarHidden()
        }
    }
}
```

The app owns the entry point, so `@main` goes on the `App` rather than on the sketch. `beginInstallation` is what the command's host calls every second; a piece that lives on a tablet in a room might want a minute.

### What it needs

- iOS 26 on the phone or tablet, paired with the Mac and trusted, with Developer Mode on.
- Xcode 26, and `xcodegen` (`brew install xcodegen`), which writes the project.
- A signing team the device is registered with. The first build asks Xcode to update the profile.
- Not the simulator. Its GPU reports itself as an older family with no cube-array textures, and the renderer binds one on every frame. Use a device.
