import Ollin

/// A user shader loaded from a `.metal` FILE beside the sketch (`Shader(resource:)`),
/// rather than an inline string: the form for a shader too big to keep in the Swift
/// source. Under OllinLive, editing `ripple.metal` and saving hot-reloads it (the file
/// is re-read and recompiled without restarting the sketch).
@main
final class ShaderFile_Example: Sketch {
    private let ripple = Shader(resource: "ripple", in: .module)

    override func draw() {
        drawImage(generate(ripple).image, 0, 0)
    }
}
