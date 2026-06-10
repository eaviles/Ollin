# Ollin Camera

A macOS **virtual camera**: it publishes a sketch's rendered frames as a system camera device, so every app that takes a webcam — Photo Booth, QuickTime, Zoom, Meet, OBS, and browser tools like Hydra through `getUserMedia` — can read Ollin as a live input. Where Syphon shares GPU frames app-to-app on one Mac, a virtual camera reaches the much larger set of apps that only speak "webcam," including the browser sandbox an OS-level transport can't cross.

This folder lives **beside `Sources/`**, not inside it, on purpose. A camera extension is a signed, notarized `.app` with an embedded **CMIO system extension** — a different build artifact from the SwiftPM package: it can't be `swift build`-compiled into a bundle, can't be `swift run`, and is *installed*, not imported. It builds through its own xcodegen-generated Xcode project (`project.yml` → `OllinCamera.xcodeproj`), so the core package stays clean. The sketch-facing half is the normal `Sources/OllinCamera/` library — `import OllinCamera`, then `publishVirtualCamera()` in `setup()`, mirroring `publishSyphon`; see [`Docs/VirtualCamera.md`](../../Docs/VirtualCamera.md).

## How it works

The device publishes two streams. The **source** stream is the camera every app captures from. The **sink** stream is the writable half: a publishing sketch process finds it through the CoreMediaIO DAL API, starts it, and enqueues IOSurface-backed `CVPixelBuffer`s; the extension consumes them (`consumeSampleBuffer`) and forwards each one to the source stream. While nothing has fed the sink for about a second, a timer renders the built-in **"no signal" test card** instead — a broadcast-style circle card (an original design in the genre of the classic Philips test cards) with color bars, gray steps, gratings, a live clock, and a moving dot, so a viewer can always tell the camera itself works (`Extension/TestCard.swift`).

Two client-side findings worth keeping (both cost a debugging round): the sink is the **direction-0** stream (`kCMIOStreamPropertyDirection`: 0 = output, host → device — the capture stream is direction 1), and `CMIOStreamCopyBufferQueue` returns `noErr` with a **nil queue** unless you pass a non-nil queue-altered callback (an empty closure is fine).

One presentation note: **Photo Booth mirrors every camera preview** (like a selfie mirror) **and crops** the frame to fill its non-16:9 pane — both can look like a broken feed. QuickTime (File ▸ New Movie Recording) shows the frame as actually published: upright and complete. Don't "fix" the mirror by pre-flipping; that would break every non-mirroring consumer.

## Build, notarize, install

Everything up to the install is one script (needs a paid Apple Developer account, a stored `notarytool` credential, and `xcodegen` — see the script header):

```sh
./Scripts/build.sh
```

Then install from the repo build (never from an iCloud-synced folder — file-provider xattrs poison bundle validation) and launch:

```sh
rm -rf /Applications/OllinCamera.app
ditto --noextattr --norsrc build/export/OllinCamera.app /Applications/OllinCamera.app
open /Applications/OllinCamera.app
```

The first activation prompts once in *System Settings ▸ General ▸ Login Items & Extensions ▸ Camera Extensions*; approve it, then open **Photo Booth** (or QuickTime ▸ New Movie Recording) and pick **Ollin Camera**. Check status or remove it with:

```sh
systemextensionsctl list
systemextensionsctl uninstall - dev.ollin.OllinCamera.Extension
```

## What activation requires (learned the hard way)

macOS validates the embedded extension strictly before it will even ask the user. Each of these produced a distinct activation failure:

- **Launch SIGKILL** — the host carries the restricted `com.apple.developer.system-extension.install` entitlement, which must be authorized by an embedded provisioning profile. Xcode's automatic signing mints one during `archive`/`-exportArchive` (`-allowProvisioningUpdates`, Mac registered as a device); ad-hoc or bare Developer ID signing gets the host killed at launch.
- **Code=4 "Extension not found in App bundle"** — the `.systemextension` bundle's *filename* must be the extension's bundle identifier, not its product name (`PRODUCT_NAME = $(PRODUCT_BUNDLE_IDENTIFIER)` in `project.yml`).
- **Code=9 "does not appear to belong to any extension categories"** — the extension's Info.plist must declare `CFBundlePackageType` = `SYSX`. Xcode's generated Info.plists set it; a hand-written `INFOPLIST_FILE` must spell it out, and nothing injects it for you. sysextd's category check is `SYSX` + the `CMIOExtension` dict (with `CMIOExtensionMachServiceName` prefixed by the team identifier or an app group); no provisioning profile and no special entitlement are required *on the extension* for the category to resolve.
- **Code=3** — the app must run from `/Applications`, launched as a bundle.
- The activation error surfaces in the host's delegate; `NSLog` from an `open`-launched app is privacy-redacted in `log show`, so run the binary directly (`/Applications/OllinCamera.app/Contents/MacOS/OllinCamera`) to read it.

## Identifiers

Host `dev.ollin.OllinCamera`, extension `dev.ollin.OllinCamera.Extension`, CMIO mach service `<team id>.dev.ollin.OllinCamera` (the shared app group).
