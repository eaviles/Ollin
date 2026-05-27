import Foundation
import AppKit
import Ollin
import OllinRuntime

// OllinLive — the live-reload host.
//
//   swift run OllinLive <path/to/Sketch.swift>
//
// Opens a window for the sketch, then (Phase 2) watches the file and hot-swaps
// the running sketch on save without closing the window.

setvbuf(stdout, nil, _IONBF, 0)   // unbuffered: reload messages show immediately

let arguments = Array(CommandLine.arguments.dropFirst())

if arguments.contains("--selftest") {
    SelfTest.run()   // headless reload-pipeline smoke test; exits
}
if arguments.contains("--watchtest") {
    WatchTest.run()  // headless FSEvents watcher check; exits
}

guard let pathArg = arguments.first(where: { !$0.hasPrefix("-") }) else {
    FileHandle.standardError.write(
        Data("usage: swift run OllinLive <path/to/Sketch.swift>\n".utf8))
    exit(2)
}

let sketchPath = (pathArg as NSString).isAbsolutePath
    ? pathArg
    : (FileManager.default.currentDirectoryPath as NSString).appendingPathComponent(pathArg)

guard FileManager.default.fileExists(atPath: sketchPath) else {
    FileHandle.standardError.write(Data("OllinLive: file not found — \(sketchPath)\n".utf8))
    exit(2)
}

let loader = SketchLoader(sketchPath: sketchPath)

print("OllinLive: compiling \(pathArg) …")
let sketch: Sketch
switch loader.load() {
case .success(let loaded):
    sketch = loaded
case .failure(let error):
    FileHandle.standardError.write(Data("OllinLive: \(error)\n".utf8))
    exit(1)
}

let keepClock = arguments.contains("--keep-clock")

let runner = OllinApp.boot(sketch)
print("OllinLive: running \(type(of: sketch))\(keepClock ? " (--keep-clock)" : "").")

let session = LiveSession(
    runner: runner, loader: loader, sketchPath: sketchPath,
    displayName: pathArg, keepClock: keepClock)
session.start()

NSApplication.shared.run()
