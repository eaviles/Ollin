import Foundation

// The one line the app needs beside the sketch.
//
// The sketch is the whole program: `@main` on it starts the app here, as it
// opens the window on the desk. A package build writes `Bundle.module` for its
// targets, and an Xcode app target has none, so this says what it is: the
// sketch is compiled into the app itself, and the files beside it are the
// app's own resources, so the bundle the sketch asks for with `in: .module` is
// the app.

extension Bundle {
    static var module: Bundle { .main }
}
