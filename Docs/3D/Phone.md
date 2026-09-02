#### <sup>[Ollin](../../README.md) → [Documentation](../README.md) → [3D](./README.md) → `Phone`</sup>

---

## Phone (iPhone sensor stream)

Borrow a tethered iPhone's on-device perception in a sketch that still renders on the Mac. **Ollin Capture**, Ollin's own iOS app ([`Apps/OllinPhoneApp`](../../Apps/OllinPhoneApp/README.md)), runs ARKit on the phone's Neural Engine and streams the results over the USB cable. `PhoneDevice` reads them on the Mac as typed values you use in `draw()`.

Eleven payloads come over. A **3D body skeleton**. **Faces**, up to 3 at once, each a deforming mesh plus the 52 expression blendshapes. The **hands** in view, up to 4, each a 21-joint skeleton lifted to metric 3D where the phone has LiDAR. The lines of **text** it can read, each with its corners lifted the same way. The **pictures and objects it knows**, each found in the room as a named 6DoF placement with its real size. A map of **where the picture draws the eye**, a heat map with the regions it peaks in. A world-facing **RGBD depth frame** from the rear LiDAR, which unprojects into a point cloud and carries the camera's 6DoF pose. The **room mesh**, the space itself reconstructed as a labeled triangle surface. A **person-segmentation matte** from the rear camera, as a silhouette and a cutout. **Device motion**. And the phone itself **held as a pointer**, which is the one payload that carries the person rather than the room.

Where [`Record3D`](../3D/Record3D.md) borrows another app's color-plus-depth feed, this is Ollin's own app, so the stream carries what ARKit *perceives*. The chain is Ollin's end to end.

`PhoneDevice` lives in a separate library so the drawing core stays lean, so add `import OllinPhone` alongside `import Ollin`. The transport is the standard `usbmuxd` device tunnel, the same plumbing Xcode uses. There's no third-party dependency and no Wi-Fi pairing, just the cable.

```swift
import Ollin
import OllinPhone

final class Pose: Sketch {
    let device = PhoneDevice()

    override func setup() { device.start() }

    override func draw() {
        background(Color(white: 0.05))
        guard let body = device.latestBody else {
            return drawStatus(device.waitingMessage, style: .info)
        }
        camera(.orbiting(target: body.center, radius: 2.6, azimuth: time * 0.4, elevation: 0.12))
        drawPointCloud(body.cloud())
    }
}
```

### Contents

- [Setup](#setup) - install the capture app, connect the cable
- [Reading the stream](#reading-the-stream) - `latestBody`, `latestFace`, `latestFrame`, `sceneMesh`, `planes`, `latestLight`, `latestMotion`, the connection state
- [The body](#the-body) - `PhoneBody`, the joints, drawing the skeleton, where the person stands, joints that turn
- [The face](#the-face) - `PhoneFace`, the blendshapes, the mesh and its texture coordinates, [the eyes and the gaze](#the-eyes-and-the-gaze)
- [The hands](#the-hands) - `PhoneHand`, 21 joints, the 3D lift, `pinchDistance`
- [The text in view](#the-text-in-view) - `PhoneText`, the corners, `worldTransform`
- [The pictures and objects it knows](#the-pictures-and-objects-it-knows) - `PhoneMarker`, the reference folder, `placement`
- [The phone as a pointer](#the-phone-as-a-pointer) - `PhoneWand`, the beam, the button, the thumb
- [World depth](#world-depth) - `latestFrame`, `pointCloud(...)`, the camera pose
- [World fusion](#world-fusion) - `WorldCloud`, sweeping a room into one cloud, [keeping it registered](#drift), and [recognizing a place already scanned](#loops) with `ScanGraph`
- [The room mesh](#the-room-mesh) - `sceneMesh`, the room as a labeled surface, the Room mode
- [The flat surfaces](#the-flat-surfaces) - `planes`, somewhere to stand something, no LiDAR needed
- [The room's light](#the-rooms-light) - `latestLight`, how bright and how warm the room is
- [Segmentation](#segmentation) - `latestSegmentationMatte`, `latestSegmentationCutout`, the Segment mode
- [Where the eye goes](#where-the-eye-goes) - `latestSaliency`, the heat map, the salient regions
- [Device motion](#device-motion) - `PhoneMotion`, the transport smoke-test
- [Notes](#notes) - the wire, coordinate space, what's ahead

---

## Setup

The sketch side is just `import OllinPhone` and a `PhoneDevice`, but the phone needs the capture app:

1. **Build Ollin Capture onto the iPhone.** It's an xcodegen + Xcode project, since an iOS app can't be `swift run`. From [`Apps/OllinPhoneApp`](../../Apps/OllinPhoneApp/README.md): `xcodegen generate`, open the project, select the phone, and Run. It needs an A12+ iPhone on iOS 17+ and automatic signing; that README has the device-registration step.
2. **Connect the cable** and launch the app. Its screen reads **READY** until the Mac connects, then **ON AIR**.
3. **Run the sketch** on the Mac. `PhoneDevice` retries on its own, so launching the app or plugging in after the sketch is already running just begins the feed.

The bundled example is `swift run --package-path Examples Example-3D-Phone-PhoneBodyPose`.

## Reading the stream

`PhoneDevice` mirrors `Record3DDevice`'s shape, with `start()` / `stop()`, a `waitingMessage` for the pre-connection notice, and `isRunning`:

```swift
let device = PhoneDevice()
device.start()                       // begins connecting; safe to call once

device.isRunning                   // Bool, frames currently arriving
device.waitingMessage                // a notice reflecting the live connection state
device.latestBody                    // PhoneBody?, the tracked skeleton (Body mode)
device.latestBodies                  // [PhoneBody], every tracked body (= one today)
device.latestFaces                   // [PhoneFace], every tracked face, up to 3 (Face mode)
device.latestFace                    // PhoneFace?, the most prominent face (= latestFaces.first)
device.latestHands                   // [PhoneHand], every hand in view, up to 4 (Hands mode)
device.latestHand                    // PhoneHand?, the most confident one
device.latestTexts                   // [PhoneText], the lines it can read (Text mode)
device.latestMarkers                 // [PhoneMarker], the pictures it knows (Markers mode)
device.latestWand                    // PhoneWand?, the phone as a pointer (Wand mode)
device.latestSaliency                // PhoneSaliency?, where the eye goes (Attention mode)
device.latestFrame              // RGBDFrame?, the latest depth frame (World mode)
device.sceneMesh                     // PhoneSceneMesh, the room scanned so far (Room mode)
device.planes                        // PhonePlanes, the flat surfaces found (Room mode)
device.latestLight                   // PhoneLight?, how bright and how warm the room is
device.latestMotion                  // PhoneMotion?, the latest device-motion sample
```

These are fresh each time the phone sends one, so read them within the current `draw()`. Each is `nil` until the first of its kind arrives. Motion typically lights up first, since it needs no camera or model, proving the wire before ARKit has found a body, face, or depth.

**The camera modes are mutually exclusive.** Body, World, Segment, Room, Hands, Text, Markers, Wand, and Attention use the rear camera, Face and Selfie the front camera, and only one camera session runs at a time. The capture app has a **Body / Face / World / Segment / Selfie / Room / Hands / Text / Markers / Wand / Attention** toggle, and whichever is selected is the one that updates: `latestBody`, `latestFace`, `latestHands`, `latestTexts`, `latestMarkers`, `latestWand`, `latestSaliency`, `latestFrame`, the segmentation images (Segment and Selfie both feed them), or the room's `sceneMesh` and `planes`. The others hold their last value, so read the one for the mode you mean to drive. Motion streams across all of them, and `latestLight` across every mode except Selfie, the one mode that runs no ARKit session.

## The body

`PhoneBody` carries every reported joint as a 3D position in **meters**, in model space. The pelvis root sits at the origin. ARKit's convention puts x to the picture's right, y up, and z toward the camera. Its accessor shape matches `Body3D` and `LiftedPose` from [`OllinVision`](../Vision/Vision.md):

```swift
if let body = device.latestBody {
    body.isTracked                   // Bool, ARKit tracking vs. extrapolating
    body.position(.head)             // Vector3?, one joint, model space
    body.positions                   // [PhoneJoint: Vector3]
    body.bones()                     // [(Vector3, Vector3)], segments to draw
    body.center                      // Vector3, centroid, to aim an orbiting camera
}
```

The joints are the `PhoneJoint` set, a practical subset of ARKit's ~91-joint skeleton. It holds root, hips, spine, chest, neck, head, and the arms and legs out to hands and feet. A joint ARKit didn't report this frame is simply absent. The subset is deliberate: only part of the full rig is really observed by the camera, and the rest exists to smooth a rigged mesh, so streaming it would add bytes and no information.

The lightest way to draw the skeleton is as a `PointCloud`. Each joint is a splat and each bone a dotted line of splats, exactly like `LiftedPose.cloud`. For solid bones, string capsules between the joints with `drawCapsule(from:to:radius:)`:

```swift
camera(.orbiting(target: body.center, radius: 2.6, azimuth: time * 0.4, elevation: 0.12))
drawPointCloud(body.cloud(jointSize: 0.055, boneSize: 0.018, color: .white))

for (a, b) in body.bones() {            // or: solid bones
    drawCapsule(from: a, to: b, radius: 0.03)
}
```

<img src="../../Guide/Images/27-DepthAndThePhone/BodyAsFigure.jpg" alt="The same staged mid-stride pose twice: on the left as ivory dots and dotted bones, on the right as a solid mannequin with capsule limbs, a leaning torso box, and a turned head, its left forearm tinted blue" width="680">

### Where the person stands

Model space keeps the root at the origin, so a figure drawn from `position(_:)` stays put while the person walks. The body also carries its anchor's **world transform**: model space → ARKit world space, y up, meters, the origin where the phone's session started. That is the same world the depth sweep, the room mesh, and the flat surfaces live in, so a body and a scanned room combine directly:

```swift
body.worldTransform                  // simd_float4x4, model space → world space
body.worldPosition(.head)            // Vector3?, one joint, standing in the room
body.worldCenter                     // Vector3, the centroid in the world
drawPointCloud(body.cloud().transformed(by: body.worldTransform))
```

### Joints that turn

Every joint carries its orientation beside its position, as a quaternion `(x, y, z, w)` in model space. Compose it with the position through `modelTransform(_:)` (or `worldTransform(ofJoint:)` to stand it in the room) and hand the result to [`transform(_:)`](3D.md#transforms) to pose a solid part at the joint:

```swift
body.orientation(.head)              // SIMD4<Float>?, the joint's quaternion
body.modelTransform(.head)           // simd_float4x4?, orientation + position composed
body.worldTransform(ofJoint: .head)       // simd_float4x4?, the same, stood in the world

if let pose = body.worldTransform(ofJoint: .head) {
    withState {
        transform(pose)              // the head's full pose, one call
        drawSphere(radius: 0.11)
    }
}
```

### The person's size, and what the camera saw

Two more readings ride each body. `scaleFactor` relates the person's estimated height to the default rig (1 = the default; a smaller person gives a smaller factor), so a figure's parts can size themselves to whoever steps in front of the camera. And `isJointTracked(_:)` says whether the camera actually observed a joint this frame; the rig fills unseen joints in from their neighbors, and those report `false`, so a sketch can tint guesswork apart from observation.

`latestBodies` is the whole set, empty when nobody is in view, so a person leaving clears the sketch rather than freezing the last pose. ARKit follows one body today; the list keeps the surface ready if that grows.

Two bundled examples read this section live. `Example-3D-Phone-PhoneBodyFigure` is a solid mannequin whose parts ride the joint orientations. It stands where the person stands, sized by the scale factor and tinted by the tracked flags. `Example-3D-Phone-PhoneCostume` puts a costume on the same skeleton: ribbon trails the joints leave as they move, and plumage that twists with the joint rotations. It is a homage after Universal Everything's *Super You*, credited in its header. `PhoneBody`'s init is public, so a pose can also be staged from a `PhonePoseSample` with no phone attached, which is how a test or a figure exercises the same drawing code.

## The face

In **Face** mode the phone tracks faces on the front TrueDepth camera, **up to 3 at once**. Each streams as a `PhoneFace`: the 52 expression **blendshapes**, the deforming **mesh** (with its texture coordinates), the **head pose**, the two **eye poses**, and the **look-at point** the eyes converge on. Read `latestFaces` for the whole set, or `latestFace` for just the most prominent one:

```swift
for face in device.latestFaces {     // up to 3 people
    face.isTracked                   // Bool, ARKit tracking vs. extrapolating
    face.blendShape(.jawOpen)        // Double 0…1, one expression coefficient
    face.blendShapes                 // [PhoneBlendShape: Double], all 52
    face.strongestBlendShapes()      // the few firing now, strongest first
    face.mesh()                      // Mesh, the triangle surface (draw solid/wireframe)
    face.meshPoints                  // [Vector3], the mesh vertices, face-local (meters)
    face.meshUVs                     // [Vector2], per-vertex texture coordinates
    face.headPosition                // Vector3, head position in world space
    face.headOrientation             // SIMD4<Float>, head rotation quaternion (x,y,z,w)
    face.headTransform               // simd_float4x4, both composed, for transform(_:)
}
```

`latestFaces` is the complete current set each frame, so a face leaving simply drops out and the list shrinks. ARKit's order isn't spatially meaningful, so sort by `headPosition.x` if you want each face to keep a steady color.

The blendshapes are the `PhoneBlendShape` set, ARKit's 52 named coefficients: `jawOpen`, `eyeBlinkLeft`, `mouthSmileLeft`, `browInnerUp`, `cheekPuff`, `tongueOut`, and the rest. Each runs `0` at neutral to `1` fully expressed. They're the cheap, expressive payload, so read one to drive a parameter, or `strongestBlendShapes()` to name the current expression.

Draw each face as a `mesh()`, its triangle surface, carrying the ARKit topology, computed normals, and the per-vertex texture coordinates. Draw it solid, textured, or as a `wireframe()`, the recognizable AR face net. The texture coordinates are the mapping every face shares and they never change frame to frame, so a mask image painted once (`face.mesh().textured(maskImage)`) fits every face and stays in place while the mesh deforms. The vertices are face-local, centered on the face, so add `face.headPosition` to place several people apart in space, then orbit their centroid:

```swift
// One face: face-local space, so orbit .zero
camera(.orbiting(target: .zero, radius: 0.42, azimuth: time * 0.4, elevation: 0.04))
wireframe()
drawMesh(face.mesh())
```

To stand the mesh where the head really is, turned the way the head turns, put `face.headTransform` on the transform stack instead and draw the mesh under it. `face.cloud()` draws the vertices as points instead, if you want the splat look. The bundled example is `swift run --package-path Examples Example-3D-Phone-PhoneFace`.

### The eyes and the gaze

Each face also carries its two eyes and where they look. The eye poses and the look-at point are **face-local** (relative to the head), and every reader has a world twin that stands it through the head pose:

```swift
face.eyePosition(.left)              // Vector3, face-local (meters)
face.worldEyePosition(.left)         // Vector3, stood through the head pose
face.eyeOrientation(.right)          // SIMD4<Float>, quaternion, identity = straight ahead
face.gazeDirection(.right)           // Vector3, unit, out of the face
face.worldGazeDirection(.right)      // Vector3, unit, in the room
face.lookAtPoint                     // Vector3, where the eyes converge, face-local
face.worldLookAtPoint                // Vector3, the same point in the room
```

The look-at point is the one to reach for first: one point in space that both eyes agree on, good for aiming a bead, steering a creature, or letting a viewer's glance push things around. The per-eye readers are for drawing the eyes themselves: an eyeball at `worldEyePosition`, a pupil a few millimeters along `gazeDirection`, a beam from each eye to `worldLookAtPoint`. The blink blendshapes (`.eyeBlinkLeft` / `.eyeBlinkRight`) pair naturally with them.

<img src="../../Guide/Images/27-DepthAndThePhone/GazeAsBeams.jpg" alt="A staged wireframe face shell on a dark ground, a small nose marker under its two white eyeballs, each pupil turned toward a warm bead floating off to the side, with a thin beam running from each eye to the bead where the two converge" width="680">

The bundled example is `swift run --package-path Examples Example-3D-Phone-PhoneGaze`: eyeballs standing at the streamed eye poses, beams converging on the look-at bead.

## The hands

In **Hands** mode the phone finds the hands in front of the rear camera, **up to 4 at once**, each a `PhoneHand`. A hand is a 21-joint skeleton: the wrist, then four joints along each finger from base to tip. The finding runs on the phone's own Neural Engine, so the Mac receives finished skeletons.

Every joint carries an upright 2D image point, already turned for how the phone is held. On a LiDAR phone each joint also carries a metric 3D position in **ARKit world space**. The phone reads the joint's depth pixel, unprojects it through the camera intrinsics, and stands it in the world with the camera pose. That is the same fixed, gravity-aligned world the [depth sweep](#world-fusion), the [room mesh](#the-room-mesh), and the body's anchor use. A live hand can reach into a scanned scene. Without LiDAR the hands arrive 2D-only and draw as a flat overlay.

```swift
for hand in device.latestHands {     // up to 4
    hand.chirality                   // .left / .right / .unknown, as the camera sees it
    hand.confidence                  // Double 0…1, the model's overall trust
    hand.position(.indexTip)         // Vector3?, metric ARKit world space (needs LiDAR)
    hand.point(.indexTip, in: bounds) // Vector2?, the 2D point mapped into a rectangle
    hand.bones()                     // [(Vector3, Vector3)], 3D bone segments
    hand.bones(in: bounds)           // [(Vector2, Vector2)], the flat skeleton
    hand.pinchDistance               // Double?, thumb tip to index tip, meters
    hand.cloud()                     // PointCloud, the lifted hand as splats
}
device.latestHand                    // PhoneHand?, the most confident one
```

`latestHands` is the complete current set each frame, so a hand leaving simply drops out and the list shrinks. A joint the model could not place is absent, and `has(_:)` says so. A joint whose depth pixel was a hole keeps its 2D point but returns `nil` from `position(_:)`. `hasWorldPositions` says whether a hand lifted at all, which is how a sketch picks between its 3D and 2D drawing.

`pinchDistance` is the gesture staple: thumb tip to index tip in meters, `nil` unless both lifted. Under about 2 cm reads as a closed pinch. `PhoneHand.skeleton` names the 20 bones, `PhoneHand.tips` the five fingertips, and `PhoneHand.fingerChains` each finger's chain wrist-first, ready to run a tube or a ribbon along.

<img src="../../Guide/Images/27-DepthAndThePhone/HandsAsSkeletons.jpg" alt="Two staged hands drawn as small solid skeletons on a dark ground: an open orange right hand with its thumb spread wide, and a blue left hand whose index finger curls to meet its thumb, a bright white bead sitting where the two fingertips pinch" width="680">

The bundled example is `swift run --package-path Examples Example-3D-Phone-PhoneHands`.

## The text in view

In **Text** mode the phone reads the text in front of the rear camera. Each line arrives as a `PhoneText` with its string, the reader's `confidence`, and its position. The recognizer is Apple's on-device one, the engine behind Live Text.

The four corners of a line are upright 2D image points, already turned for how the phone is held. On a LiDAR phone the corners also lift to metric 3D in **ARKit world space**. That is the same fixed world as the [depth sweep](#world-fusion) and the [hands](#the-hands). `worldTransform` turns the corners into one matrix for `transform(_:)`. Its origin is the line's center. Its x axis runs along the reading direction, y up the line, and z out of the surface. Without LiDAR the lines stay 2D and draw as a flat overlay.

```swift
for line in device.latestTexts {
    line.text                        // what the line says
    line.confidence                  // Double 0…1, the reader's trust
    line.corners(in: bounds)         // [Vector2], the quad mapped into a rectangle
    line.bounds(in: bounds)          // Rectangle, the box around it
    line.worldCorners                // [Vector3], metric ARKit world space (needs LiDAR)
    line.worldCenter                 // Vector3, the quad's center
    line.worldWidth                  // Double, meters along the reading direction
    line.worldTransform              // simd_float4x4?, the line's placement matrix
}
device.latestText                    // PhoneText?, the line filling the most of the picture
```

`latestTexts` is the complete current set each frame, so a sign that leaves the view drops out. A line lifts all four corners, never three. `hasWorldPlacement` says whether the lift happened. The recognizer completes a few readings per second, below camera rate, because it runs at the `.accurate` recognition level. The `.fast` level misses small text across a room.

The bundled example is `swift run --package-path Examples Example-3D-Phone-PhoneWorldText`.

## The pictures and objects it knows

In **Markers** mode the phone looks for things it has been given. A reference is a file in the capture app's own folder: any picture, or an `.arobject` a scan produced. Connect the cable, open the phone in Finder, then Files, then Ollin Capture, and drop the file in. AirDrop and the Files app work the same way. The app reads the folder when the mode starts, and the **Read the folder again** button picks up a file dropped in later.

A picture needs its printed width in meters, which no image file carries, so its own name states it. `poster@30cm.png`, `card-50mm.jpg`, `plate 12in.heic`, and `tile_0.4m.png` all say a size; centimeters, millimeters, inches, and meters are the units. A name that says nothing gets 15 cm and the app says so on its screen. What is left after the size is the marker's **name**, so `poster@30cm.png` is the marker `poster`.

Each find arrives as a `PhoneMarker` in ARKit world space, the same fixed world as the [depth sweep](#world-fusion), the room, and the hands. `placement` is the frame to draw through. Its origin sits at the middle of the thing, x runs across the width, y up the height, and z out of the face. It is orthonormal, so nothing drawn through it is scaled.

```swift
for marker in device.latestMarkers where marker.isTracked {
    marker.name                      // String, the reference file's own name
    marker.kind                      // .image or .object
    marker.width                     // Double, meters (what it really measures)
    marker.placement                 // simd_float4x4, ready for transform(_:)
    marker.position                  // Vector3, the middle of it
    marker.facing                    // Vector3, out of the printed face
    marker.corners                   // [Vector3], perimeter order (tl, tr, br, bl)
}
device.marker(named: "poster")       // PhoneMarker?, by name
device.latestMarker                  // PhoneMarker?, the biggest one being followed
```

`latestMarkers` is the complete current set each frame. A picture that leaves the view stays in it with `isTracked` off, holding its last placement, so a sketch decides whether to keep drawing on it.

Three things decide whether this works in a room:

- **A picture is found by its detail.** A photograph or a dense drawing is found across a room; a flat logo or a large plain area is not. ARKit checks each reference as it loads and the app prints what it complains about, so a picture that will never be found says so before you go looking for it.
- **The printed width is what places it.** A wrong width puts the picture at the wrong distance rather than losing it. ARKit also estimates the real size and reports it through `scaleFactor`, which `width` and `height` already carry.
- **An object is found, not followed.** ARKit tracks a picture while it stays in view; a scanned object gets one placement where it was found and keeps it. So an object marks a place, and a picture marks a moving thing.

The bundled example is `swift run --package-path Examples Example-3D-Phone-PhoneMarkers`.

<a name="the-phone-as-a-pointer"></a>

## The phone as a pointer

Every payload above describes the room. **Wand** mode describes the person holding the phone. The phone tracks its own place with plain world tracking, so it needs no LiDAR, and the screen under the thumb becomes the button.

```swift
guard let wand = device.latestWand, wand.isTracked else { return }

wand.position                        // Vector3, where the phone is (meters)
wand.pointing                        // Vector3, out of the back of it, length 1
wand.ray                             // Ray3, the beam: ask it what it hits
wand.point(at: 2)                    // Vector3, two meters out in front
wand.placement                       // simd_float4x4, ready for transform(_:)
wand.up                              // Vector3, up the screen
wand.across                          // Vector3, right across the screen
wand.isPressed                       // Bool, a finger is on the pad now
wand.pressCount                      // Int, presses so far, never falls
wand.touch                           // Vector2?, -1...1 across and up, nil when free
```

`ray` is what a sketch usually asks. It starts at the phone and runs the way the phone points, so [`Ray3`](../Drawing/Geometry.md#ray3) answers what the person is pointing at:

```swift
for (i, ball) in balls.enumerated() where wand.ray.hit(sphereAt: ball, radius: 0.13) != nil {
    aimed = i
}
```

Four things are worth knowing before you build on it:

- **The beam comes out of the back.** Point the rear camera at a thing and you are pointing at it. `placement` is the phone's own frame (x across the screen, y up it, z out of it toward you), so `pointing` is its **-z**, the same way a camera looks in [Ollin's own 3D](./3D.md).
- **The press is carried twice, on purpose.** `isPressed` is the state now, which is what a drag reads. `pressCount` only rises, so a tap that landed and left between two `draw()` calls is still seen: keep last frame's count and compare.
- **The thumb is a rate, not a place.** `touch` is where the thumb sits on the pad, and the pad is small while a room is not, so read it as a speed (`distance += touch.y * speed * deltaTime`) rather than as a position.
- **The room's origin is where the mode started.** Everything is in the same ARKit world space as the [depth sweep](#world-fusion) and the room, and that world begins where the phone stood when Wand mode began. So lay a scene out in front of that spot, or let the person walk to it.

`isTracked` goes off while the phone is finding its place, and the button keeps working through that, so a sketch can take presses while the pose is worth nothing.

The bundled example is `swift run --package-path Examples Example-3D-Phone-PhonePointer`.

## World depth

In **World** mode the phone's rear **LiDAR** streams a world-facing RGBD frame. It holds a metric depth map, the matching color image, the camera intrinsics, per-pixel confidence, and the camera's 6DoF pose. `PhoneDevice` exposes it as the source-agnostic core [`RGBDFrame`](../3D/RGBD.md), so it unprojects into a point cloud the same way every depth source does. It needs a LiDAR iPhone, meaning a Pro model.

```swift
if let cloud = device.pointCloud(depthRange: 0.3...5.0) {
    camera(.orbiting(target: .zero, radius: 2.5, azimuth: time * 0.3, elevation: 0.18))
    drawPointCloud(cloud)
}

device.latestFrame              // RGBDFrame?, depth + color + intrinsics
device.latestPose                    // simd_float4x4?, the camera's 6DoF pose
```

`pointCloud(...)` is sugar over `latestFrame?.pointCloud(...)` with rear-LiDAR defaults: `minConfidence: .medium` and an open depth range. See [`RGBD.md`](../3D/RGBD.md) for the full unprojection parameters and the coordinate space, which is camera-relative, +x right, +y up, looking −z. For finer control, like sampling a single depth point or lifting a 2D pose to metric 3D, reach for `latestFrame` and the `RGBDFrame` API directly.

`PhoneDevice` is also a `FrameSource` and a `VideoFeed` in this mode. A vision tracker can analyze the color feed and `drawFrame` can letterbox it. The color frame is only present while World mode is streaming.

The bundled example is `swift run --package-path Examples Example-3D-Phone-PhoneDepthCloud`.

## World fusion

A single depth frame is only the slice of the world in front of the lens. The camera's 6DoF pose, `latestPose`, is what turns slices into a whole. ARKit's world is fixed and gravity-aligned. Transforming each frame's camera-space cloud by its pose places it where it really is in the room. Sweep the phone and the slices stack up.

<img src="../../Guide/Images/27-DepthAndThePhone/SweepFuse.jpg" alt="Three tinted captures of the staged room fused into one cloud, coral from the left, green from the middle, blue from the right, each camera position marked with a small sphere and a sight line" width="680">

`WorldCloud`, in the core, does the fusing. It keeps one point per small cube of space, so re-seeing a wall refreshes it in place rather than piling up duplicates. The cloud's size is bounded by the scene's surface area, not the number of frames. A sweep can run as long as you like:

```swift
var world = WorldCloud(voxelSize: 0.025)   // fuse at 2.5 cm

override func draw() {
    // Fuse each fresh frame once, draw() runs faster than frames stream in.
    if let id = device.latestFrameVersion, id != lastFused,
       let pose = device.latestPose,
       let cameraCloud = device.pointCloud(minConfidence: .low, depthRange: 0.3...5.0) {
        world.add(cameraCloud, correcting: pose)
        lastFused = id
    }
    camera(.orbiting(target: center, radius: r, azimuth: time * 0.2, elevation: 0.22))
    drawPointCloud(world.cloud)            // the whole accumulated room
}
```

`add(_:transformedBy:)` applies the camera-to-world pose and merges in one pass, `add(_:correcting:)` corrects that pose first (see below), and `add(_:)` merges an already-world-space cloud. `latestFrameVersion` changes only when a new depth frame arrives, so comparing it against the last fused id adds each frame exactly once. `world.cloud` is the fused `PointCloud`, `world.count` its point total, and `world.reset()` starts a fresh scan. The placement primitive underneath, `PointCloud.transformed(by:)`, is public too, so any 4×4 matrix can be applied to a cloud's positions, and `Vector3.transformed(by:)` does the same for one point.

The bundled example is `swift run --package-path Examples Example-3D-Phone-PhoneWorldScan`. Sweep the phone, press **C** to turn the correction off, and **R** to reset.

<a name="drift"></a>
### Keeping a long sweep registered

ARKit reports its pose with a small error, and the error never goes away, so it piles up. Over a minute of sweeping it grows into tens of centimeters: a wall seen at the start of the scan and again at the end lands in two places, and the fused cloud thickens into a smear. That is drift, and it is the reason a long scan looks worse than a short one.

<img src="../../Guide/Images/27-DepthAndThePhone/DriftFixed.jpg" alt="The same staged room fused twice side by side: on the left a blurred, doubled ball and a ghosted crate over a smeared checkered floor, on the right the same ball and crate crisp and single, the checker squares clean" width="680">

`add(_:correcting:)` takes it out. Before each frame is merged, the frame is slid and turned until it sits on the surfaces already fused, and the fix that did it is kept and used as the starting guess for the next frame:

```swift
let fix = world.add(cameraCloud, correcting: pose)

fix.pose          // the pose the cloud actually went in at
fix.error         // what is left between the frame and the scan, in meters
fix.overlap       // how much of the frame found a surface to match, 0 to 1
fix.applied       // false when the fit was held back
world.correction  // the whole fix so far: placed = correction * reported
```

Two rules keep it honest. A frame that finds too little to match, or that asks for a jump rather than a nudge, is **held back**: the cloud still goes in, at the fix earlier frames established, and `applied` reads false. And a direction the geometry does not pin down is left alone rather than guessed, so sweeping one blank wall corrects across it and never slides along it.

The fit costs about half of what merging the frame costs, and it stops as soon as a round stops moving the cloud, so a well-tracked frame pays for one or two rounds. `CloudAlignment.Settings` has the parameters (how many points to fit through, how many rounds, how far to look, and the two guards); the defaults suit a hand-held sweep at a few centimeters per voxel.

Apply `world.correction` to anything else the phone reports in the same space, so it lands where the fused cloud does:

```swift
let whereTheCameraReallyIs = Vector3.zero.transformed(by: world.correction * pose)
```

To see the difference without a phone, `swift run --package-path Examples Example-3D-Depth-ClosedLoopScan` sweeps a made-up room twice, side by side, with C cycling the correction.

<a name="loops"></a>
### Recognizing a place already scanned

Correcting each frame removes the newest error. It does not revise the poses behind it. Each frame agrees with the frame before it, and the chain of them can still lean. Walk a full circle around a room and the far wall lands well away from where it is.

<img src="../../Guide/Images/27-DepthAndThePhone/LoopClosed.jpg" alt="Two overhead views of the same staged room scanned by a camera walking a full circle inside it. On the left the walls are drawn twice, thick and offset, and the ring of camera positions ends short of where it began. On the right the walls are single and clean and the ring closes on itself" width="680">

`ScanGraph` fixes that. It fuses and corrects exactly as `WorldCloud` does. It also keeps a **keyframe** every so often: the pose it went in at, and a thinned copy of what that frame saw. A new keyframe that lands where an old one stood is matched against it directly. The match ties a late pose to an early one, so the chain becomes a loop that does not quite close. That difference is shared out over every pose between the two, and the fused cloud is laid out again from the keyframes' new poses.

```swift
var scan = ScanGraph(voxelSize: 0.025)

let update = scan.add(cameraCloud, correcting: pose)
update.alignment            // the same CloudAlignment the frame-by-frame fit reports
update.keyframe             // the keyframe this frame became, if it was worth keeping
update.loop                 // set when the scan recognized a place

scan.cloud                  // the fused points, as WorldCloud's
scan.keyframes              // every kept moment: pose, reported pose, what it saw
scan.loops                  // every place recognized so far
scan.correction             // placed = correction * reported, straightenings included
```

A loop reports its match and its effect:

```swift
if let loop = update.loop {
    loop.keyframe           // the keyframe that turned out to be somewhere known
    loop.recognized         // the older keyframe it matched
    loop.overlap            // how much of the two views agreed, 0 to 1
    loop.error              // what the match left over, in meters
    loop.moved              // the biggest keyframe move the straightening made, in meters
}
```

**The envelope.** The search compares position and viewing direction, so `searchRadius`, 1.5 m by default, is the limit. A scan that drifts further than that before returning is out of its own reach. Each candidate is then fitted, twice: wide, then narrow. The wide pass finds an error too big for the narrow one to see. The narrow pass is the one that is scored, and a candidate that scores badly is refused.

**One guard is not obvious.** A camera facing one flat wall can slide along that wall and turn about its normal. Every such pose fits the wall equally well. Three of the six reported numbers are then unmeasured; they record drift as though it were measured. Overlap and leftover error both appear perfect. Only the fit's conditioning reveals this, reported as `stability` on `CloudAlignment`, and a match under `matching.minStability` is refused. A room with objects in it is therefore easier to scan than a bare corridor.

**A straightened scan is rebuilt from the keyframes.** So `keyframeDetail`, 4 cm by default, sets both the detail the finished scan holds and the memory the keyframes cost. Use a value near the fusion `voxelSize` for the most detail, or several times it to stay light. Frames after the last keyframe are not kept and are not laid down again; the sweep replaces their detail as it continues.

The rest are parameters on `ScanGraph.Settings`: the distance between keyframes, how far back to look, how many candidates to fit, how much the two views must agree, and the distance at which a turn is weighed. Leave that last one unset and the scan supplies it.

Without a phone, `swift run --package-path Examples Example-3D-Depth-ClosedLoopScan` walks a made-up hall twice, side by side. The left half lines up frame by frame, the right half also closes loops, and the true walls are drawn over both.

## The room mesh

In **Room** mode the phone stops sending you raw depth and sends you the room itself. ARKit reconstructs the space around it as a real triangle surface on the device, and labels each triangle with what it is. What arrives on the Mac already has normals, and already knows the floor from the wall. The same mode also reports [the flat surfaces](#the-flat-surfaces) in that room, from one session and one world origin, so the two always agree about where things are.

Where [world fusion](#world-fusion) builds a cloud of points on the Mac, this is a solid surface built on the phone. Both come from the same LiDAR, so pick by what you want to do with it. Points are for a cloud you scatter, deform, or reconstruct yourself. A mesh is for a surface you light, hide things behind, or bounce something off.

```swift
device.sceneMesh                     // PhoneSceneMesh, the room scanned so far
device.sceneMeshVersion              // Int?, changes when a block arrives or is retired
device.resetSceneMesh()              // forget it and collect the room again
```

The room arrives **in blocks**. ARKit divides the space into pieces, reports each as its own anchor, and keeps improving a piece as you look at it again. So a block turns up many times under the same identity, and the newest reading replaces the last. Blocks arrive at up to 15 a second while you walk.

**Rebuild the mesh when it changes, never once per frame.** A scanned room reaches hundreds of thousands of triangles, and `draw()` runs far faster than blocks arrive. `sceneMeshVersion` is the gate:

```swift
var room = Mesh(positions: [], indices: [])
var built: Int?

override func draw() {
    if device.sceneMeshVersion != built {
        built = device.sceneMeshVersion
        room = device.sceneMesh.mesh          // the whole room, one Mesh
    }
    drawMesh(room)
}
```

`PhoneSceneMesh` gives three shapes of the same room:

```swift
let scan = device.sceneMesh
scan.mesh                            // Mesh, the whole room, world space, meters
scan.mesh(of: .floor, .table)        // Mesh, only the labels you ask for
scan.mesh { surface in ... }         // Mesh, painted a color per triangle
```

Plus what you need to frame it and report it: `chunks`, `chunkCount`, `vertexCount`, `triangleCount`, `bounds`, `center`, `isEmpty`, and `foundSurfaces` (the labels the scan has actually produced).

A label is a `PhoneSurface`: `wall`, `floor`, `ceiling`, `table`, `seat`, `window`, `door`, or `unclassified`. **Early in a scan almost everything is `unclassified`**, because ARKit decides what a surface is only once it has seen enough of it. That is the honest picture rather than a fault, so a sketch that keys off labels should say so while the room fills in. `foundSurfaces` tells you what is available.

```swift
// A floor you could stand something on, and the rest of the room behind it.
fill(Color(white: 0.25)); drawMesh(scan.mesh)
fill(Color(hex: 0x4C9A6B)); drawMesh(scan.mesh(of: .floor))
```

Positions are in ARKit's fixed, gravity-aligned world space, in meters. That is the same space `latestPose` reports, so a mesh block and a fused cloud from one session line up.

Starting a scan resets that world origin, which would leave an older room floating in a space that no longer exists. So every block says which run of the scanner it came from, and `PhoneDevice` drops the room it was holding the moment a new run begins. Leaving Room mode and coming back is a new run.

Scene reconstruction needs a LiDAR sensor, so the surface is Pro-tier iPhones only. The flat surfaces below are not, so Room mode is worth opening on any phone. The bundled example is `swift run --package-path Examples Example-3D-Phone-PhoneRoomMesh`.

## The flat surfaces

Room mode reports one more thing: the flat surfaces in the room. ARKit finds a floor, a wall, a table top, or a seat as a single flat patch, and grows it as you look around. Each one carries a label, the same one it puts on a triangle of the surface.

The mesh is the whole shape of the room, down to the clutter. This is the handful of places worth putting something on or hanging something from. It also needs **no LiDAR**: plane detection runs on any phone the capture app installs on. That is what makes Room mode worth opening on a phone that cannot reconstruct anything.

<img src="../../Guide/Images/27-DepthAndThePhone/RoomAsPlanes.jpg" alt="Left, three flat surfaces of a staged room corner drawn as outlined polygons: a green floor, a blue-gray wall, a tan table top. Right, the same three in plain gray with a metal ball resting on the table. Below, three color swatches labeled lamp 480 lm 2700 K, room 1000 lm 5000 K, window 900 lm 9000 K, running from warm brown through cream to pale blue" width="680">

```swift
device.planes                        // PhonePlanes, every flat surface found so far
device.planesVersion                 // Int?, changes when one arrives, grows, or is retired
device.resetPlanes()                 // forget them and collect again
```

Each one is a `PhonePlane`, already in world space:

```swift
for plane in device.planes.flat {
    plane.surface                    // PhoneSurface: floor, table, seat, wall, …
    plane.center                     // Vector3, the middle of it
    plane.normal                     // Vector3, the way it faces
    plane.area                       // Double, square meters, measured on the outline
    plane.boundary                   // [Vector3], the real outline, a convex polygon
    plane.mesh                       // Mesh, the outline filled in
    plane.outline                    // [Vector3], a closed loop, ready for drawTube
}
```

The set is read the same way:

```swift
let room = device.planes
room.flat                            // [PhonePlane], floors, tables, seats
room.upright                         // [PhonePlane], walls
room.planes(of: .table, .seat)       // [PhonePlane], only these labels
room.largest                         // PhonePlane?, the most surface, by real area
room.largest(of: .table)             // PhonePlane?, the biggest of a label
room.floor                           // PhonePlane?, the labelled floor, or the lowest flat one
room.mesh { surface in ... }         // Mesh, every surface painted by what it is
```

**`largest` measures the outline, not the box around it.** A long thin shelf can have a big box and very little surface. Picking it as the ground would put your sketch on a shelf.

**`floor` answers before ARKit has decided.** A label arrives late, so `floor` gives you the labeled floor when there is one and the lowest flat surface until then. A sketch can stand something on the ground a second or two after the app opens.

```swift
// A ball resting on the biggest flat thing in the room.
if let ground = device.planes.largest(of: .table) ?? device.planes.floor {
    withState {
        translate(ground.center + ground.normal * 0.15)
        drawSphere(radius: 0.15)
    }
}
```

Surfaces share the room mesh's world space and its scan number, so a new run of the scanner clears both together. The bundled example is `swift run --package-path Examples Example-3D-Phone-PhoneRoomPlanes`.

## The room's light

The phone measures the light around it from its own camera image. It does this in **every** mode, a few times a second, so a sketch can match the light in the room.

```swift
if let light = device.latestLight {
    light.lumens                     // Double, as measured; 1000 is an ordinary room
    light.intensity                  // Double, the same scaled so 1 is an ordinary room
    light.kelvin                     // Double, color temperature; 6500 is neutral white
    light.color                      // Color, what a white wall in this room looks like
    light.ambient                    // Color, that white turned down by how bright it is
}
```

`ambient` is the one to reach for, because it carries both halves at once:

```swift
ambientLight(device.latestLight?.ambient ?? Color(white: 0.4))
```

The reading follows the room, so switching a lamp on warms the sketch with it.

**Face mode knows more.** ARKit reads the shading on a tracked face, so a front-camera session also reports where the light comes from:

```swift
light.direction                      // Vector3?, the way the strongest light travels
light.keyIntensity                   // Double?, how strong it is, on the same scale
light.sphericalHarmonics             // [Float]?, 27 coefficients, nine per channel
light.key                            // Light?, all of that, ready to add to a scene
```

```swift
if let key = device.latestLight?.key { light(key) }
```

A world-facing session has no face to read, so `direction` and `key` are `nil` there and the two ambient numbers arrive on their own. In Room mode a sketch can add its own directional light, in the room's measured color:

```swift
if let measured = device.latestLight {
    ambientLight(measured.ambient)
    light(.directional(measured.color, direction: Vector3(-0.35, -1, -0.25),
                       intensity: measured.intensity))
}
```

`PhoneLight` has a public initializer, so a sketch can be developed against a stand-in reading with no phone attached: `PhoneLight(lumens: 480, kelvin: 2700)` is a lamp-lit room.

## Segmentation

In **Segment** mode the phone's rear camera runs ARKit's on-device **person segmentation**. The Neural Engine separates the people in the scene from the background, and the phone streams the matte plus the color frame. `PhoneDevice` turns them into two drawable `Image`s:

```swift
device.latestSegmentationMatte       // Image?, a tintable white-alpha silhouette
device.latestSegmentationCutout      // Image?, the person, lifted off the background
```

Both are `nil` until a Segment-mode frame arrives, and both line up with each other when drawn into the same rectangle. The **matte** is white with the person's alpha, so `tint(_:)` recolors it into a silhouette, a drop shadow, or a colored glow. The **cutout** keeps the camera's own pixels where the matte is on and is transparent elsewhere: the person ready to composite over anything. The cutout costs a little more to build, since the color is masked, so it's produced only when you read it.

```swift
guard let cutout = device.latestSegmentationCutout else {
    return drawStatus(device.waitingMessage, style: .info)
}
let rect = Rectangle(fitting: Vector2(Double(cutout.width), Double(cutout.height)),
                     in: canvasRectangle)
drawImage(cutout, in: rect)           // the person over whatever you drew first
```

The matte and cutout come back **upright** for how the phone is held, and they stay aligned with each other. The capture app sends the device orientation and `PhoneDevice` rotates both to match. Rear-camera person segmentation needs an A12 or later iPhone. The bundled example is `swift run --package-path Examples Example-3D-Phone-PhoneSegmentation`, and it draws whichever camera is feeding it.

**Selfie** mode is the front-camera half. ARKit's person segmentation is rear-only, so the app runs the front camera through a plain capture session and computes the matte with Vision instead. The same two accessors update, and a sketch doesn't care which camera fed them. The feed arrives **mirrored**, like the phone's own front-camera preview, because that is how a person expects to see their own picture. For the unmirrored view, flip it when drawing: a negative x scale inside `withState { }`. Selfie runs no ARKit session, so `latestLight` pauses there and holds its last reading. It also needs no particular chip: any iPhone front camera will do.

## Where the eye goes

In **Attention** mode the phone maps what its picture draws the eye to. Vision's attention model (trained on human gaze, drawn to faces and contrast) runs on the phone's Neural Engine over the rear camera. Each analyzed frame streams a reading: a coarse **heat map** of visual attention, the bounding **regions** it peaks in, and the color frame it was read from. It is the on-device sibling of the Mac's own [saliency tracking](../Vision/Vision.md), for when the picture that matters is the one the phone is pointed at.

```swift
if let attention = device.latestSaliency {
    attention.salience(at: p, in: rect)  // Double 0…1, the pull under a canvas point
    attention.regions                    // [PhoneSalientRegion], what stands out
    attention.strongestRegion            // PhoneSalientRegion?, the model's best
    for region in attention.regions {
        region.bounds(in: rect)          // Rectangle, the box mapped into the frame
        region.confidence                // Double 0…1, the model's trust
        region.worldCenter               // Vector3, ARKit world space (needs LiDAR)
    }
}
device.latestSaliencyHeatMap             // Image?, a tintable white-alpha glow
device.latestSaliencyFrame               // Image?, the camera frame it was read from
```

The heat map is coarse on purpose (the model's own resolution, a few thousand pixels). Drawn into the frame's rectangle it stretches into a soft spotlight, and `tint(_:)` recolors it into a glow, a fog, a warm haze. `salience(at:in:)` reads the value under any canvas point, so the same surface is a density field for stippling or an attractor for particles. Everything arrives upright for how the phone is held. Map boxes and queries through the rectangle you draw the frame into and they line up.

On a LiDAR phone each region's **center** also lifts to a metric 3D position in ARKit world space (`hasWorldPlacement` says whether it did). That is the same world the depth sweep, the room, and the hands stand in, so the thing being looked at keeps a place in that scene. A box's corners land on the background, which is why only the center is lifted.

The model completes a few readings per second, below camera rate, and the last reading holds between them. The bundled example is `swift run --package-path Examples Example-3D-Phone-PhoneAttention`.

## Device motion

`PhoneMotion` is the CoreMotion sample: attitude as a quaternion, gravity, rotation rate, and user acceleration. It's the cheap payload that proves the USB transport before any model runs:

```swift
if let m = device.latestMotion {
    m.gravity                        // Vector3, gravity direction, in g
    m.attitude                       // SIMD4<Float>, orientation quaternion (x,y,z,w)
    m.rotationRate                   // Vector3, rad/s
    m.userAcceleration               // Vector3 in g, gravity removed
}
```

Tilt the phone and `gravity` swings, a one-line check that the wire is alive.

## Notes

- **The wire is Ollin's own, shared verbatim.** Both ends are Swift, so the protocol skips the packed-image trick cross-language tools use. It is a length-prefixed stream of tagged binary messages, `PhoneWire`. That one source file is compiled into *both* the Mac satellite and the iOS app, so the framing can't drift between them.
- **USB only.** The transport is the `usbmuxd` tunnel over the cable, on port 1338, distinct from Record3D's 1337. Wi-Fi is deliberately out.
- **Per-frame clouds are camera-relative, and fusion is world-space.** A single `pointCloud(...)` is in the camera's own frame, root at the lens, and the skeleton is in model space, root at the origin. [World fusion](#world-fusion) is what lifts a sweep into one fixed world cloud, by applying each frame's `latestPose`. It fuses several poses' clouds into a single *registered* scene. [Keeping a long sweep straight](#drift) and [recognizing a place already scanned](#loops) correct ARKit's own drift on top. The body's anchor lives in the same world, so a skeleton and a swept room combine directly.
- **Depth is raw over the wire.** The LiDAR depth map ships uncompressed, and a 256×192 frame is ~196 KB, comfortable over USB. LZFSE compression is a later optimization. The color image is sent as a downscaled JPEG.
- **A growing catalog.** Body pose, face, hands, the text in view, the pictures and objects it knows, where the eye goes, world depth, the room mesh, the flat surfaces, the room's light, person segmentation, and motion are the payloads today. Richer sensors are the same app sending new tagged payloads, not new pipelines.
- **A mesh block is carried raw, and sending is what is throttled.** The phone reads a block's geometry the moment ARKit hands it over, since those buffers belong to the session. It then queues the block and sends a few at a time. A block too big for one payload is skipped and counted on the app's own screen.
