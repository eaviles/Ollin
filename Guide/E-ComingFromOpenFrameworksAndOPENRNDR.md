#### <sup>[Ollin](../README.md) → [Guide](README.md) → Appendix E</sup>

---

# E. Coming from openFrameworks and OPENRNDR

Ollin learned from both of these. openFrameworks showed how plain a creative-coding app can be, and OPENRNDR showed what a typed core with layers you compose looks like. So if you've worked in either one, the ideas here won't be new. What you need is where each thing went.

This appendix is shorter than [Appendix C](C-ComingFromP5.md) on purpose, and it covers the big moves only. Each one says what you reach for there and how Ollin does it, with a small pair of code, and then what's different. The everyday calls for shapes, ink, and transforms read much the same in every framework, so Appendix C's tables serve you too. The Swift itself is in [Appendix A](A-JustEnoughSwift.md) and the [Swift quick reference](../Docs/Swift.md).

## From openFrameworks

### The app becomes one class

An openFrameworks app is three files. `main.cpp` opens the window, while `ofApp.h` and `ofApp.cpp` declare and define `setup`, `update`, and `draw`:

```cpp
// main.cpp
int main() {
    ofGLWindowSettings settings;
    settings.setSize(1080, 1080);
    auto window = ofCreateWindow(settings);
    ofRunApp(window, std::make_shared<ofApp>());
    ofRunMainLoop();
}

// ofApp.cpp, with float angle = 0 declared in ofApp.h
void ofApp::update() {
    angle += 0.02;
}

void ofApp::draw() {
    ofBackground(0);
    ofTranslate(ofGetWidth() / 2, ofGetHeight() / 2);
    ofRotateRad(angle);
    ofSetColor(255, 180, 0);
    ofDrawRectangle(-100, -100, 200, 200);
}
```

In Ollin the same piece is one class in one file:

```swift
import Ollin

final class Spinner: Sketch {
    override func draw() {
        background(.black)
        translate(width / 2, height / 2)
        rotate(time * 1.2)
        fill(Color(red: 1, green: 0.7, blue: 0))
        drawRect(center: .zero, width: 200, height: 200)
    }
}
```

There's no header and no `main`. The canvas is 1080 by 1080 unless the sketch declares another `canvasSize`, and `swift run OllinLive Spinner.swift` opens the window.

There's no `update()` either. `draw()` is the one call per frame, so anything that changes goes at its top. Often nothing needs storing, because the state can be worked out from the clock. Here the angle is `time * 1.2`, where `time` is the seconds since the sketch started. When something really does build up over time, like a particle's position, step it by `deltaTime` at the top of `draw()`.

The frame rate follows the display, and there's no call to set it. A Mac display may refresh 60 or 120 times a second. Motion written against `time` and `deltaTime` keeps its speed on both. Ported as it is, the `0.02` a frame above would spin twice as fast on the second.

### The names you type every day

| openFrameworks | Ollin | Notes |
|---|---|---|
| `ofGetElapsedTimef()` | `time` | seconds, as a `Double` |
| `ofGetLastFrameTime()` | `deltaTime` | |
| `ofGetFrameNum()` | `frameCount` | |
| `ofGetWidth()`, `ofGetHeight()` | `width`, `height` | the canvas, not the window |
| `ofBackground(0)` | `background(.black)` | the canvas clears every frame on its own |
| `ofSetBackgroundAuto(false)` | `noClear()` | for marks that pile up |
| `ofSetColor(255, 0, 102)` | `fill(Color(red: 1, green: 0, blue: 0.4))` | channels run `0...1`, as in `ofFloatColor` |
| `ofSetLineWidth(4)` | `strokeWeight(4)` | |
| `ofDrawCircle(x, y, r)` | `drawCircle(x, y, r)` | a radius in both |
| `ofDrawRectangle(x, y, w, h)` | `drawRect(x, y, w, h)` | |
| `ofRotateDeg(45)` | `rotate(.pi / 4)` | radians only |
| `ofRandom(10)`, `ofNoise(x, y)`, `ofSignedNoise(x)` | `random(10)`, `noise(x, y)`, `signedNoise(x)` | |
| `ofMap(v, a, b, c, d, true)` | `map(v, a, b, c, d, clamped: true)` | |
| `glm::vec2`, `ofColor` | `Vector2`, `Color` | values, with real operators |

### Fill and stroke are separate inks

In openFrameworks, `ofSetColor` sets one current color, and `ofFill` or `ofNoFill` decides whether a shape comes out filled or outlined. A disc with an outline takes two draws:

```cpp
ofSetColor(255, 180, 0);
ofFill();
ofDrawCircle(540, 540, 200);
ofSetColor(0);
ofNoFill();
ofSetLineWidth(6);
ofDrawCircle(540, 540, 200);
```

Ollin keeps two inks at once, so one call draws both:

```swift
fill(Color(red: 1, green: 0.7, blue: 0))
stroke(.black)
strokeWeight(6)
drawCircle(540, 540, 200)
```

Three settings from that world have nothing to set here. Antialiasing is always on, and so is alpha blending. There's no circle resolution either, because a circle isn't built from straight sides. Its edge is worked out at every pixel, so it stays round at any size.

### One scope for the matrix and the style

`ofPushMatrix` and `ofPushStyle` are two stacks, and each needs its matching pop:

```cpp
ofPushMatrix();
ofPushStyle();
ofTranslate(300, 200);
ofRotateDeg(30);
ofSetColor(255, 0, 0);
ofDrawRectangle(-40, -40, 80, 80);
ofPopStyle();
ofPopMatrix();
```

`withState { }` saves both at once and restores them when the block ends, so a pop can't be forgotten:

```swift
withState {
    translate(300, 200)
    rotate(.pi / 6)
    fill(.red)
    drawRect(-40, -40, 80, 80)
}
```

`pushState()` and `popState()` are there for the rare case a block can't express. [Chapter 6](06-GridsAndRepetition.md) uses the scoped form throughout.

### An ofFbo is a layer

You allocate an `ofFbo` once, draw into it between `begin` and `end`, and then draw it to the screen. Its pixels stay until you clear them:

```cpp
// setup()
fbo.allocate(1080, 1080, GL_RGBA);

// draw()
fbo.begin();
ofClear(0, 0, 0, 0);
ofSetColor(255, 120, 0);
ofDrawCircle(540, 540, 200);
fbo.end();
fbo.draw(0, 0);
```

An Ollin layer is made inside `draw()` and drawn into with `withTarget`. Filters run on it directly, and its `image` composites back:

```swift
override func draw() {
    background(.black)
    let layer = makeRenderTarget()
    withTarget(layer) {
        fill(.orange)
        drawCircle(540, 540, 200)
    }
    drawImage(layer.filtered(.gaussianBlur(radius: 20)).image, 0, 0)
}
```

Making the layer every frame costs nothing, because Ollin keeps the GPU texture behind it and hands the same one back each time. A new layer starts transparent, so there's no `ofClear` to call.

The two differ in what they keep between frames, since a layer keeps nothing from the frame before. For a buffer that keeps what you drew, as the classic trails buffer does, make a `Feedback` once in `setup()` with `makeFeedback()` and draw into it with `withFeedback`. [Chapter 16](16-LayersAndEffects.md) builds both. The effect chains ofxFX gives you are the `Filter` catalog there: blurs, bloom, color grading, and many more, each one a value you name.

### Shaders: one function, in Metal

`ofShader` loads a vertex and fragment pair written in GLSL, and a rectangle drawn between `begin` and `end` runs it:

```cpp
// setup()
shader.load("shader");   // shader.vert and shader.frag

// draw()
shader.begin();
shader.setUniform1f("time", ofGetElapsedTimef());
ofDrawRectangle(0, 0, ofGetWidth(), ofGetHeight());
shader.end();
```

An Ollin shader is one function, `shade`, written in the Metal Shading Language. Ollin writes the vertex stage and the pass around it:

```swift
let rings = Shader("""
float4 shade(float2 uv, ShaderInfo info) {
    float d = length(uv - 0.5);
    float v = 0.5 + 0.5 * sin(d * 60.0 - info.time * 3.0);
    return float4(v, v * 0.6, 1.0 - v, 1.0);
}
""")

override func draw() {
    drawImage(generate(rings).image, 0, 0)
}
```

The time, the resolution, and the mouse arrive in `info` without being set, and numbers of your own ride along as `params`. How many layers the function reads decides what it is. With none it's a generator, with one it's a filter, and with two it combines them. Metal's grammar is C's, as GLSL's is, so most lines change only their type names, and `vec2` becomes `float2`.

For a shader you already have, `ollin new --from-shader` translates a fragment shader in the common web form into Metal and writes a project around it. [Chapter 17](17-YourFirstShader.md) teaches the whole contract, and [Bringing a GLSL shader over](../Docs/Tools/ShaderImport.md) lists what the translation carries and what it leaves as a note.

### 3D: the camera is a call

In openFrameworks, 3D is an `ofEasyCam` you begin and end, with depth testing and lights switched on by hand:

```cpp
// ofApp.h declares ofEasyCam cam and ofLight light
void ofApp::draw() {
    ofEnableDepthTest();
    cam.begin();
    light.enable();
    ofSetColor(240, 90, 90);
    ofDrawBox(200);
    cam.end();
}
```

In Ollin, calling a camera is what makes a sketch 3D, and depth testing comes with it:

```swift
override func draw() {
    background(Color(hex: 0x10141B))
    cameraControl(radius: 5)
    pointLight(.white, at: Vector3(3, 4, 5))
    fill(Color(hex: 0xF05A5A))
    drawBox(size: 1.5)
}
```

`cameraControl` orbits with the mouse the way `ofEasyCam` does. With no lights of your own, a default rig shades what you draw. Inside the camera, y points up and distances are world units, not pixels. An `ofMesh` becomes a `Mesh` value, built from positions and indices or from a generator such as `Mesh.box`, and drawn with `drawMesh`. `loadMesh` reads glTF, OBJ, USD, STL, and PLY files, so it covers most of what ofxAssimpModelLoader loads. [Chapter 21](21-3DGently.md) starts there.

### C++ habits that change

Several C++ chores go away in Swift. There are no headers, no pointers, and no `new` or `delete`, because memory is counted for you. `std::vector<T>` becomes an array, `[T]`. `auto` becomes `let` for a constant and `var` for something that changes.

One habit changes meaning, and it's the loop over your particles. In C++, `auto&` hands you each particle by reference, so the loop changes the vector:

```cpp
for (auto& p : particles) {
    p.position += p.velocity;
}
```

In Swift a struct is a value, and `for p in particles` hands you a copy. The compiler won't let you change it, and `for var p` changes only the copy. Loop over the indices and write through the array instead:

```swift
for i in particles.indices {
    particles[i].position += particles[i].velocity
}
```

Or make `Particle` a class, whose instances are shared rather than copied. [Appendix A](A-JustEnoughSwift.md) covers values and references.

### Addons become satellite modules

The addons sketches reach for most have counterparts that ship with Ollin. Each one is a Swift module you `import`, or a part of the core:

| openFrameworks addon | In Ollin | Reference |
|---|---|---|
| ofxGui | `@Param` properties, shown in the inspector | [Parameters](../Docs/Helpers/Parameters.md) |
| ofxOsc | `OSCReceiver` and `OSCSender`, in `OllinOSC` | [OSC](../Docs/Integration/OSC.md) |
| ofxMidi | `MIDIInput` and `MIDIOutput`, in `OllinMIDI` | [MIDI](../Docs/Integration/MIDI.md) |
| ofxOpenCv, ofxCv | `OllinVision`, on Apple's Vision framework: faces, hands, bodies, and `ContourDetector` for outlines | [Vision](../Docs/Vision/Vision.md) |
| ofxBox2d | `World`, in `OllinPhysics`, with Box2D bundled | [Physics](../Docs/Simulation/Physics.md) |
| ofxSyphon | `SyphonServer` and `SyphonClient`, in `OllinSyphon` | [Syphon](../Docs/Integration/Syphon.md) |
| ofxFX | the `Filter` catalog, on layers | [Effects](../Docs/Drawing/Effects.md) |
| ofxAssimpModelLoader | `loadMesh` and `loadScene` | [Scenes](../Docs/3D/Scenes.md) |
| ofVideoGrabber, ofVideoPlayer | `Camera` in `OllinVision`, `VideoPlayer` in `OllinVideo` | [Vision](../Docs/Vision/Vision.md), [Video](../Docs/Video/Video.md) |
| ofSoundPlayer, ofSoundStream | `AudioPlayer`, `AudioInput`, and `AudioAnalyzer`, in `OllinAudio` | [Audio](../Docs/Helpers/Audio.md) |

Here is ofxGui beside its Ollin form, which has no panel code at all:

```cpp
// ofApp.h declares ofxPanel gui and ofxFloatSlider radius
void ofApp::setup() {
    gui.setup();
    gui.add(radius.setup("radius", 140, 10, 300));
}

void ofApp::draw() {
    ofDrawCircle(ofGetWidth() / 2, ofGetHeight() / 2, radius);
    gui.draw();
}
```

```swift
@Param(10...300) var radius = 140.0

override func draw() {
    background(.black)
    drawCircle(width / 2, height / 2, radius)
}
```

The inspector beside the canvas draws the slider, so it never lands in an export. The control follows the property's type. A `Bool` becomes a toggle, a `Color` becomes a color well, and a `Vector2` becomes a pair of fields. Values survive a live reload, and the inspector can write the ones you like back into the source file.

### projectGenerator becomes ollin new

The projectGenerator writes an IDE project with your addons in it. `ollin new` writes a Swift package, with the satellites you name already wired in, or a single loose file when the name ends in `.swift`:

```sh
ollin new Spinner --with osc,params    # a project folder
ollin new Spinner.swift                # one file
ollin Spinner.swift                    # run it live
```

The bigger change is the working loop. In openFrameworks you rebuild, relaunch, and start again from the first frame. Ollin's live host keeps the window open instead. Save the file and it recompiles just the sketch, then swaps it into the running window. A compile error leaves the last good version running. `--keep-clock` carries `time` across the swap, so an animation doesn't jump back to its start. [Chapter 1](01-HelloOllin.md) sets this up, and [the project generator](../Docs/Tools/ProjectGenerator.md) lists every kind of project it writes.

## From OPENRNDR

### From Kotlin to Swift

OPENRNDR runs on the Java virtual machine, so it's easy to think of it as Java. The programs are written in Kotlin, though, and Kotlin and Swift are close relatives. `val` is Swift's `let`, and `var` is `var`. A trailing lambda reads like a trailing closure, `it` becomes `$0`, and `?` marks a value that may be missing in both. An extension function is a Swift extension.

Two differences show up often. Swift reads `140` as a `Double` wherever one is expected, so the `.0` endings go. And a Kotlin data class is a reference, while a Swift struct is a value, copied when you assign it.

### The program becomes a sketch

```kotlin
fun main() = application {
    configure {
        width = 1080
        height = 1080
    }
    program {
        var radius = 200.0
        mouse.buttonDown.listen { radius = 120.0 }
        extend {
            drawer.clear(ColorRGBa.BLACK)
            drawer.fill = ColorRGBa.PINK
            drawer.stroke = null
            drawer.circle(drawer.bounds.center, radius + sin(seconds) * 80.0)
        }
    }
}
```

```swift
import Ollin

final class Pulse: Sketch {
    var radius = 200.0

    override func mousePressed() {
        radius = 120
    }

    override func draw() {
        background(.black)
        fill(.pink)
        noStroke()
        drawCircle(center: center, radius: radius + sin(time) * 80)
    }
}
```

Code in `program { }` that comes before `extend { }` runs once, so it moves to `setup()` or into properties. The `extend { }` block runs every frame, which makes it `draw()`. `configure` becomes a `canvasSize` declaration, `seconds` becomes `time`, and `drawer.bounds.center` becomes `center`.

Events are overrides rather than listeners. Where OPENRNDR listens on `mouse.buttonDown`, a sketch overrides `mousePressed()` and reads `mouse` inside it. Keys work the same way, through `keyPressed()`.

### No drawer to pass around

OPENRNDR hands every program a `drawer`, and you set its state by assigning to it. Ollin's calls live on the sketch, so `drawer.fill = ColorRGBa.PINK` is `fill(.pink)`. There is a drawer underneath, and the bare calls forward to it, but it isn't public yet. Whether to open it is a decision the project will make before 1.0.

So a helper that draws extends `Sketch` rather than the drawer:

```kotlin
fun Drawer.target(position: Vector2) {
    circle(position, 40.0)
    circle(position, 20.0)
}
```

```swift
extension Sketch {
    func drawTarget(at position: Vector2) {
        drawCircle(center: position, radius: 40)
        drawCircle(center: position, radius: 20)
    }
}
```

The `draw` prefix is the house rule for any call that puts geometry on the canvas. What a helper passes around is still public: `Color`, `Vector2`, `Contour`, `Shape`, and `Mesh` are all values. [Writing an extension](../Docs/Tools/Extensions.md) covers helpers you hand to other people.

### The value types are close by design

| OPENRNDR | Ollin | Notes |
|---|---|---|
| `ColorRGBa(1.0, 0.4, 0.0)` | `Color(red: 1, green: 0.4, blue: 0)` | channels run `0...1` in both |
| `ColorRGBa.fromHex("#ff6600")` | `Color(hex: "#ff6600")` | |
| `Vector2(3.0, 4.0)`, `Vector3` | `Vector2(3, 4)`, `Vector3` | the same names and operators |
| `a.distanceTo(b)` | `a.distance(to: b)` | |
| `Rectangle` | `Rectangle` | |
| `ShapeContour`, `Shape` | `Contour`, `Shape` | a `Contour` holds points, so curves are flattened into it |
| `contour { moveTo(…); lineTo(…) }` | `Path { $0.move(to: …); $0.line(to: …) }` | `drawShape { }` takes the same builder and draws at once |
| `drawer.contour(c)` | `drawShape(Shape(contours: [c]))` | |
| `c.position(t)` | `c.point(at: t)` | measured by length along the whole outline |
| `c.normal(t)`, `c.nearest(p)` | `c.normal(at: t)`, `c.nearestPoint(to: p)` | |
| `c.sub(t0, t1)` | `c.piece(from: t0, to: t1)` | |
| `intersections(a, b)` | `a.crossings(with: b)` | |

`position(t)` and `point(at:)` measure differently. OPENRNDR splits `t` evenly across the contour's segments, so on an outline of uneven segments `0.5` can land well away from halfway. Ollin's `point(at:)` always measures along the length, so `c.point(at: t)` matches `c.pointAtLength(t * c.length)` there. The contour questions are in [Geometry](../Docs/Drawing/Geometry.md) and [Chapter 15](15-ShapesAsMaterial.md).

### isolated, and the degrees trap

`drawer.isolated { }` is `withState { }`, the same block shown in the openFrameworks half:

```kotlin
drawer.isolated {
    translate(300.0, 200.0)
    rotate(30.0)
    fill = ColorRGBa.RED
    rectangle(-40.0, -40.0, 80.0, 80.0)
}
```

Ported line by line, one call keeps compiling and changes meaning. OPENRNDR's `rotate` takes degrees. Ollin's `rotate` takes radians, so `rotate(30)` turns almost five times around and gives no error. Write `rotate(.pi / 6)`, or think in turns, where `.tau` is one.

### Render targets and the compositor

OPENRNDR builds a composite once, before the frame loop, and draws it every frame. A filter is an object you configure:

```kotlin
val composite = compose {
    layer {
        draw {
            drawer.fill = ColorRGBa.PINK
            drawer.circle(drawer.bounds.center, 200.0)
        }
        post(GaussianBlur()) {
            window = 25
            sigma = 5.0
        }
    }
}
extend {
    drawer.clear(ColorRGBa.BLACK)
    composite.draw(drawer)
}
```

Ollin's `compose { }` goes inside `draw()` and is declared again every frame. A filter is a value named with its settings:

```swift
override func draw() {
    background(.black)
    compose {
        layer {
            fill(.pink)
            drawCircle(center: center, radius: 200)
        }
        .post(.gaussianBlur(radius: 25))
    }
}
```

Declaring it every frame costs nothing, since the textures underneath are kept and reused. To animate a setting, you pass a new value each frame rather than changing a property on the filter. A layer's blend is a modifier, `.blended(.add)`. A helper layer that feeds another layer's effect is `aside { }`, as in the compositor.

The pieces under `compose` map just as directly. A `renderTarget` made once and drawn into with `isolatedWithTarget` becomes `makeRenderTarget()` and `withTarget` inside `draw()`, as in the openFrameworks half. A target that keeps its pixels between frames is `makeFeedback()`, and `extend(NoClear())` is `noClear()`. [Chapter 16](16-LayersAndEffects.md) teaches the whole stack.

### Shade styles

A shade style splices GLSL into the fill of every shape drawn while it's set:

```kotlin
drawer.shadeStyle = shadeStyle {
    fragmentTransform = "x_fill.rgb *= c_boundsPosition.x;"
}
drawer.circle(drawer.bounds.center, 200.0)
```

Ollin has no shader per shape. The common uses divide in two. A gradient across a shape is paint, which `fill` and `stroke` take anywhere they take a color:

```swift
fill(.linear(from: Vector2(340, 0), to: Vector2(740, 0), [.black, .pink]))
drawCircle(center: center, radius: 200)
```

The gradient's two ends are canvas points, so you place them where the shape is. `.radial(center:radius:_:)` and `stroke(.alongPath(_:))` are the other two geometries.

Anything else is a `Shader` over a layer, kept inside the shape by a mask. In a `compose` block that's `.masked(by: aside { … })`, with the shape drawn in the aside. [Layered effects](../Docs/Drawing/Effects.md#aside) shows the mask, and [Chapter 17](17-YourFirstShader.md) the shader.

### The orx modules

| OPENRNDR module | In Ollin | Reference |
|---|---|---|
| orx-fx | the `Filter` catalog | [Effects](../Docs/Drawing/Effects.md) |
| orx-compositor | `compose { }` | [Effects](../Docs/Drawing/Effects.md#compose) |
| orx-gui, orx-parameters | `@Param` properties, shown in the inspector | [Parameters](../Docs/Helpers/Parameters.md) |
| orx-olive | the live host, `OllinLive` | [Chapter 1](01-HelloOllin.md) |
| orx-camera | `cameraControl()` and `cameraShowcase()` | [Camera](../Docs/3D/Camera.md) |
| orx-noise | `noise`, `simplexNoise`, `fbm`, and the `signed…` forms | [Noise](../Docs/Generators/Noise.md) |
| orx-shapes | `drawCurve(_:closed:spline:)` with `.hobby`, `convexHull(of:)`, `offset(by:join:)`, `simplified(tolerance:)` | [Geometry](../Docs/Drawing/Geometry.md) |
| orx-osc, orx-midi, orx-syphon | `OllinOSC`, `OllinMIDI`, `OllinSyphon` | [Integration](../Docs/Integration/README.md) |

Parameters take one line rather than an annotated object registered with a panel. `@DoubleParameter("radius", 10.0, 300.0)` on a settings object, added with `gui.add`, is the same `@Param(10...300)` shown in the openFrameworks half.

orx-noise passes the seed with every call, as in `simplex(seed, x, y)`, and its simplex is centered on zero. In Ollin you set the seed once with `noiseSeed(_:)`, and the match is `signedSimplexNoise(x, y)`. The unsigned forms run `0...1`.

orx-olive and `OllinLive` both keep the window open while you edit. Olive evaluates a Kotlin script inside the running program. `OllinLive` compiles the saved Swift file and swaps the result in, and nothing in the sketch changes to allow it:

```sh
swift run OllinLive Pulse.swift
```

`extend(…)` is here too. A `SketchExtension` hooks the same moments an OPENRNDR extension does, setup and before and after the draw, and it can also receive each finished frame. Screenshots and screen recording are run flags rather than extensions, such as `--export` and `--export-video`. Syphon reads almost the same in both:

```kotlin
extend(SyphonServer("Pulse"))
```

```swift
import OllinSyphon

override func setup() {
    extend(SyphonServer(name: "Pulse"))
}
```

The OPENRNDR template is a Gradle build, and it's where you name the orx modules you want. Here the build is SwiftPM. `ollin new` writes the `Package.swift` with the satellites you name, the same command as in the openFrameworks half.

## What stays behind

Both frameworks run on Windows and Linux, and both draw through OpenGL. OPENRNDR also has a browser target. Ollin draws through Metal and runs on Apple platforms only, by design. The [README](../README.md#why-apple-only) gives the reasons. In short, it lets Ollin use Metal and Apple's own frameworks for vision, audio, and the iPhone's sensors directly. That choice has a cost. A sketch here won't build on a Linux box or a Raspberry Pi, and it won't run in a browser. `--export-web` writes a page that plays back what the sketch drew, which covers sharing but isn't the same thing.

The other thing that stays behind is years of community work. The `ofx` and `orx` ecosystems hold addons for hardware and techniques that Ollin doesn't have yet. When you miss one, check [Appendix D](D-CompleteToolbox.md) first, since the name may simply be different. If it isn't there, the [roadmap](../ROADMAP.md) says what's planned, and [Writing an extension](../Docs/Tools/Extensions.md) shows how to build it yourself.

## Go deeper

- [Appendix C](C-ComingFromP5.md): the full call-by-call dictionary, written for p5.js, which serves for the everyday calls here too.
- [Appendix A](A-JustEnoughSwift.md): the Swift you need, including values against references.
- [Chapter 16, Layers and effects](16-LayersAndEffects.md): layers, filters, feedback, and `compose`.
- [Chapter 17, Your first shader](17-YourFirstShader.md): the `shade` contract, the shader library, and bringing GLSL over.
- [Chapter 21, 3D, gently](21-3DGently.md): the camera, lights, and meshes.
- [Appendix D](D-CompleteToolbox.md): everything Ollin ships, one line each.

---

[Contents](README.md#contents) · Previous: [Appendix D, The complete toolbox](D-CompleteToolbox.md)
