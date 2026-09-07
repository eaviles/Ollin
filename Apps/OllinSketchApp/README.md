# Ollin Sketch: a sketch as an iOS app

One Ollin sketch, running as an app on the phone and the tablet. The framework
does the drawing exactly as it does on the desk: the same Metal renderer, the
same `draw()` loop at the display's refresh rate, the same shaders compiled from
source at launch.

This app is the reference for what an iOS project looks like, and the thing that
proves the platform leg works. It is not a product.

## What changes for a sketch

Almost nothing.

- **The app owns the entry point.** On the desk `Sketch.main()` opens a window
  for the sketch, and `@main` goes on the sketch itself. The system owns an
  app's launch instead, so `@main` goes on the `App`, which puts the sketch in a
  `SketchView`. See `Sources/OllinSketchHostApp.swift`.
- **A finger is the pointer.** `mouseX`, `mouseY`, and `mouseIsPressed` read the
  touch, so a sketch written for a mouse runs on glass with no change. A stylus
  or a screen that measures force also fills `pressure`.
- **`Scene` is two types.** The framework has a 3D `Scene` and SwiftUI has one,
  so an `App` in a file that imports both writes `some SwiftUI.Scene`.
- **The desk features stay on the desk.** The standalone launcher, the export
  flags, the screen saver, the wallpaper, the menu bar piece, the display wall,
  the detached inspector panel, and the source-editing drag are all macOS only.
  A sketch that uses none of them is portable as written.

## Build and run

The quick way, from the checkout: `ollin phone Sources/TouchRings.swift` writes this same shape around the sketch, builds and installs it, and installs it again on every save. See [the sketch on the phone](../../Docs/Tools/OnThePhone.md). For a project of your own in this shape, `ollin new <Name> --kind ios-app` writes one; see [the project generator](../../Docs/Tools/ProjectGenerator.md). By hand:

The framework arrives as a local package dependency, so a change to Ollin is
picked up by the next build with nothing to publish.

```sh
cd Apps/OllinSketchApp
xcodegen generate                     # the .xcodeproj is gitignored
open OllinSketchApp.xcodeproj         # pick the phone, Run
```

Headless, onto a connected phone:

```sh
xcodebuild -project OllinSketchApp.xcodeproj -scheme OllinSketchApp \
  -destination 'platform=iOS,id=<device id>' -allowProvisioningUpdates build
xcrun devicectl device install app --device <device id> <path to Ollin Sketch.app>
```

`xcrun devicectl list devices` names the connected devices.

## The simulator does not run it

It builds for the simulator and aborts on the first frame. The simulated GPU
reports itself as an Apple family 2 device, which has neither MetalFX nor
cube-array textures, and the renderer binds a cube array on every encode for the
point-shadow slot the mesh fragment declares. Use a device.

## Requirements

iOS 26. A registered device (see `Apps/OllinPhoneApp/README.md` for the signing
setup, which is shared).
