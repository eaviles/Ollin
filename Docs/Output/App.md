#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [Output](./README.md) → `A sketch as an app`</sup>

---

## A sketch as an app

A finished piece should not need you standing next to it. Wrapped as a Mac app, a sketch opens with a double click on a machine that has never seen the toolchain. A friend's laptop, a gallery machine, the computer that runs the wall.

```sh
ollin new Orbit --kind mac-app
cd Orbit && ./build.sh
```

`Orbit.app` appears beside the script, wearing a frame of itself as its icon. `./build.sh --install` also puts it in /Applications.

### What you get

```
Orbit/
  Package.swift              the mac sketch's manifest, unchanged
  Info.plist                 the app's name tag
  build.sh                   wraps the built binary in Orbit.app
  Sources/Orbit/
    Sketch.swift             an ordinary sketch
```

The sketch keeps its `@main` and its window, because an app is a program. The target `swift run` runs during the work is the target the script wraps at the end. Nothing about the sketch is app-shaped: every sketch this shape can become one, and the project stays a normal project all the way.

### The icon is the sketch

`build.sh` runs the binary it just built with `--export`, takes frame 120, squares it, and folds it into the `.icns` the Finder shows. The piece is its own icon, and it updates itself every build.

Two ways to take over:

- Drop an `AppIcon.icns` of your own beside `build.sh`. A file of yours always wins.
- Change the `--frame 120` in the script to catch the sketch at a different moment.

If the render fails, the app keeps the stock icon and the build carries on; the icon is never the reason there is no app.

### Working on it

Building an app is a slow way to look at a change. Open the same sketch in a window instead, where it reloads as you save, and wrap it when it looks right:

```sh
ollin Sources/Orbit/Sketch.swift
```

The file is the same file either way, and inside the app the mouse, the keyboard, and every export flag keep working.

### What the script does

```sh
./build.sh              # build Orbit.app here, signed for this machine
./build.sh --install    # build it and put it in /Applications
```

The script builds the package in release and puts the `.app` folder around the binary. It copies the framework's own files in, renders the icon, and signs the result. Two details in there are each a way an app fails quietly:

- **The framework's files travel inside the app.** Shader segments, fonts, and tables are looked for in the app's own `Resources` once the binary runs from a bundle. An app without them opens and shows nothing.
- **The signature decides how far it travels.** Unsigned, the system will not launch it at all. The script's plain build signs for this machine only, and says so every time, so nobody ships one by accident.

If the sketch uses the camera or the microphone, the generated `Info.plist` carries the matching usage line, written in when the capability is wired. A bundled app that asks without one is not refused politely; the system kills it.

### Giving it to somebody else

The plain build runs here and nowhere else. Traveling takes a paid Apple Developer account and two commands, the first of them once:

```sh
xcrun notarytool store-credentials ollin-notary \
    --apple-id you@example.com --team-id TEAMID --password <app-specific password>
./build.sh --sign "Developer ID Application: Your Name (TEAMID)" --notarize ollin-notary
```

`--sign` applies your Developer ID with the hardened runtime the notary checks for. `--notarize` sends the app to Apple, waits for the pass, staples the ticket onto the bundle, and leaves an `Orbit.zip` beside it ready to hand over. Any Mac will open what is inside.

Before you send one anywhere, change `CFBundleIdentifier` in `Info.plist` from `com.example.*` to something of yours. Two apps with one identifier are one app as far as the system is concerned.

### An app for a wall

`build.sh` and `Info.plist` are self-contained. Copy the pair into any sketch folder of the same shape, change the two names at the top of the script, and that project builds an app too. A piece delivered to a gallery machine this way runs without the repo, without the toolchain, and without you. A sketch that declares an `Installation` keeps it inside the app, so the double click opens the piece the way [installation mode](./Installation.md) says: full screen, unattended, on the building's hours.

---

## See also

- [Installation](./Installation.md) - running unattended on a wall, once the app is on the machine
- [Screen saver](./ScreenSaver.md) - the other double-clickable home a sketch can live in
- [The project generator](../Tools/ProjectGenerator.md) - the kinds of project `ollin new` writes, this one among them
- [Export](./Export.md) - leaving with a picture instead
