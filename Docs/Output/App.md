#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Output](./README.md) → `A sketch as an app`</sup>

---

## A sketch as an app

A finished piece should not need you standing next to it. Wrapped as a Mac app, a sketch opens with a double click on a machine that has never seen the toolchain. That machine can be a friend's laptop, a gallery machine, or the computer that runs the wall.

```sh
ollin new Orbit --kind mac-app
cd Orbit && ./build.sh
```

`Orbit.app` appears beside the script, and its icon is a frame of the sketch itself. Run `./build.sh --install` to build the app and put it in /Applications as well.

### What you get

```
Orbit/
  Package.swift              the mac sketch's manifest, unchanged
  Info.plist                 the app's name tag
  build.sh                   wraps the built binary in Orbit.app
  Sources/Orbit/
    Sketch.swift             an ordinary sketch
```

The sketch keeps its `@main` and its window, because an app is a program. The target that `swift run` runs while you work is the same target the script wraps at the end. Nothing about the sketch is app-shaped, so any sketch of this shape can become an app, and the project stays a normal project throughout.

### The icon is the sketch

`build.sh` runs the binary it just built with `--export`, takes frame 120, squares it, and writes it into the `.icns` file the Finder shows. The piece is its own icon, so the icon is made again on every build.

You can take that over in two ways:

- Put an `AppIcon.icns` of your own beside `build.sh`. A file of yours always wins.
- Change the `--frame 120` in the script to take the icon from a different moment.

If the render fails, the app keeps the stock icon and the build carries on. The icon is never the reason there is no app.

### Working on it

Building an app is a slow way to look at a change. Open the same sketch in a window instead, because there it reloads as you save. Wrap it as an app once it looks right:

```sh
ollin Sources/Orbit/Sketch.swift
```

It is the same file either way, and inside the app the mouse, the keyboard, and every export flag keep working.

### What the script does

```sh
./build.sh              # build Orbit.app here, signed for this machine
./build.sh --install    # build it and put it in /Applications
```

The script builds the package in release and puts the `.app` folder around the binary. It copies the framework's own files in, renders the icon, and signs the result. Two of those steps are each a way an app fails quietly:

- **The framework's files travel inside the app.** The binary runs from a bundle, so it looks in the app's own `Resources`. Shader segments, fonts, and tables all live there. An app without them opens and shows nothing.
- **The signature decides how far the app travels.** Without a signature, the system will not launch it at all. The plain build signs it for this machine only, and the script says so every time, so nobody ships one by accident.

If the sketch uses the camera or the microphone, the generated `Info.plist` carries the matching usage line, added when the capability is wired. A bundled app that asks without that line is not refused politely, because the system kills it.

### Giving it to somebody else

The plain build runs on this machine and nowhere else. To let the app travel, you need a paid Apple Developer account and two commands. You run the first of them only once:

```sh
xcrun notarytool store-credentials ollin-notary \
    --apple-id you@example.com --team-id TEAMID --password <app-specific password>
./build.sh --sign "Developer ID Application: Your Name (TEAMID)" --notarize ollin-notary
```

`--sign` applies your Developer ID with the hardened runtime the notary checks for. `--notarize` sends the app to Apple and waits for the pass. It then staples the ticket onto the bundle and leaves an `Orbit.zip` beside it, ready to hand over. Any Mac will open what is inside.

Before you send an app anywhere, change `CFBundleIdentifier` in `Info.plist` from `com.example.*` to an identifier of your own. As far as the system is concerned, two apps with one identifier are one app.

### An app for a wall

`build.sh` and `Info.plist` are self-contained. Copy the pair into any sketch folder of the same shape and change the two names at the top of the script. That project then builds an app too. A piece delivered to a gallery machine this way runs without the repo, without the toolchain, and without you. A sketch that declares an `Installation` keeps that declaration inside the app. The double click then opens the piece the way [installation mode](./Installation.md) describes, which means full screen, unattended, and on the building's hours.

---

## See also

- [Installation](./Installation.md) - running unattended on a wall, once the app is on the machine
- [Screen saver](./ScreenSaver.md) - the other double-clickable form a sketch can take
- [The project generator](../Tools/ProjectGenerator.md) - the kinds of project `ollin new` writes, this one among them
- [Export](./Export.md) - leaving with a picture instead of an app
