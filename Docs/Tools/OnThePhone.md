#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Tools](./README.md) → `The sketch on the phone`</sup>

---

## The sketch on the phone

A sketch written for the Mac runs on an iPhone or an iPad without changes. It uses the same Metal renderer, the same `draw()` at the display's refresh rate, and the same shaders compiled from source at launch. A finger is the pointer, so `mouseX`, `mouseY`, and `mouseIsPressed` read the touch with no change, and a stylus fills `pressure`.

You work on it with one command:

```sh
ollin phone Sketch.swift
```

The sketch appears on the phone, and every save on the Mac installs the new version there. The phone's parameters open in a browser on the Mac, and changes travel in both directions. Stop the command when you are done, and the app stays on the phone.

### Contents

- [What a save does](#what-a-save-does)
- [The parameters on the Mac](#the-parameters-on-the-mac)
- [What comes along](#what-comes-along)
- [The options](#the-options)
- [In an app of your own](#in-an-app-of-your-own)
- [What it needs](#what-it-needs)

### What a save does

A phone runs only code that is signed inside its app bundle. Nothing can be pushed into a running app the way the live window swaps a sketch on the Mac. So a save is a small build and a reinstall, and the times are short enough for that to work:

| Step | Time |
|---|---|
| The framework, built for the phone | about 80 s, once |
| A save: the sketch recompiled, the app relinked and signed | 5 to 7 s |
| The app installed again, over Wi-Fi | about 2.5 s |

A save reaches the screen in under ten seconds. The app writes its state down every second and reads it back when it launches. That state is the clock, the seed, every `@Param` value, and every `@Saved` property. So a reinstall carries on mid-motion. An animation keeps its phase, and a value you tuned stays tuned. The phone keeps the same behavior as `--keep-clock` on the Mac.

The phone has to meet two conditions. It must be unlocked for the Mac to open the app. If it is locked, the new version is installed and waits for a tap. It must also be reachable, either on the cable or awake on the same network as the Mac.

The command prints a compile error with your own file and line, and the phone keeps running the last version until the next save.

### The parameters on the Mac

The app serves its `@Param` parameters through the [remote surface](../Integration/Remote.md), which is the same touch surface you tune an installation from. The command prints the address and opens it:

```
  parameters  http://localhost:9330  or  http://Edgardos-iPhone.local:9330
```

Over the cable the surface is forwarded to `localhost`, so no network is needed between the two. Over Wi-Fi the address is the phone's own name. Drag a slider on the Mac and the phone follows between frames. Tune something on the phone and the Mac shows it. A value you settle on is carried across every later save, because it is part of the state the app writes down. To put it into the file, type it in.

Shaders in a `.metal` file beside the sketch come along as resources, so a shader edit is one more save.

### What comes along

The sketch file is referenced where it is, never copied. Files beside it with a resource extension are copied into the app. That covers images, sounds, video, fonts, data, meshes, and `.metal` shaders. `Bundle.module` is the app, so `loadImage("photo.png", in: .module)` finds on the phone what it found on the Mac. Drop a new file beside the sketch and the next save takes it along.

Every `import Ollin…` line links that satellite into the app. Ten have been built and run on a phone: `OllinRemote`, `OllinPhysics`, `OllinOSC`, `OllinMIDI`, `OllinController`, `OllinVideo`, `OllinBluetooth`, `OllinAudio`, `OllinVision`, and `OllinHaptics`. A satellite outside that list is linked too, and the command names it, so you know what to check first if the build fails. Five satellites work only on the Mac, so the command refuses them and gives the reason. They are the virtual camera, Syphon, screen capture, and both ends of the phone-as-sensor link, because a phone cannot be its own peripheral.

The Mac features stay on the Mac. They are the export flags, the screen saver, the wallpaper, the menu bar piece, the display wall, the detached inspector panel, and the source-editing drag. A sketch that uses none of them is portable as written.

### The options

```
ollin phone Sketch.swift                  the loop: build, install, launch, watch
ollin phone Sketch.swift --once           build, install, launch, and stop
ollin phone Sketch.swift --fresh          start the sketch over, state forgotten
ollin phone Sketch.swift --device iPad    which paired device, by part of its name
ollin phone Sketch.swift --team ABCDE12345
ollin phone --devices                     the paired devices
```

The signing team comes from the `--team` flag first, then from `OLLIN_TEAM` in the environment. If neither is set, the team is the one the reference phone app in the checkout is signed with. The project the command writes lives under `~/Library/Caches/Ollin/Phone/`, with one folder per sketch. The sketches share one build folder, so the framework compiles for the phone only once.

### In an app of your own

The command writes an app around the sketch. `Apps/OllinSketchApp` in the checkout is built the same way, by hand. It is an Xcode project with the framework as a local package, plus a host that puts the sketch in a `SketchView`.

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

The app owns the entry point, so `@main` goes on the `App` rather than on the sketch. The command's own host calls `beginInstallation` with a checkpoint every second. But a piece that runs on a tablet in a room can use a checkpoint every minute instead.

### What it needs

- iOS 26 on the phone or tablet. The device is paired with the Mac and trusted, with Developer Mode on.
- Xcode 26, and `xcodegen` (`brew install xcodegen`), which writes the project.
- A signing team the device is registered with. The first build asks Xcode to update the profile.
- A device, not the simulator. The simulator's GPU reports itself as an older family with no cube-array textures, and the renderer binds one on every frame.
