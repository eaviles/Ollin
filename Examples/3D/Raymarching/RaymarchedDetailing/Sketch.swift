import Ollin
import Foundation

// The raymarched detailing ops: a columns-union joint flutes the seam where a bar meets
// its post; an engraved ring and a grooved band score a sphere; a tongue ridge wraps a
// box like beading; and a pipe bead traces the crossing of a sphere and a plane-cut,
// hanging in space after both bodies vanish. The rib count breathes so the fluting works.
@main
final class RaymarchedDetailing: Sketch {
    override func draw() {
        raymarchResolution(0.5)   // several fields on screen at once
        background(Color(hex: 0x11141a))
        let t = time

        cameraShowcase(.turntable(period: .tau / 0.35), target: Vector3(0.4, 0.2, 0), radius: 9.6,
                    elevation: 0.32, fieldOfView: .pi / 4, near: 0.1, far: 40)

        directionalLight(.white, direction: Vector3(-0.5, 0.8, 0.4),
                         intensity: 1.2, softness: 0.3)
        ambientLight(Color(white: 0.18))
        material(.glossy)

        // A fluted joint: the crossbar meets the post through a row of ribs, the count
        // stepping over time so the flutes re-space live.
        let ribs = 3 + Int(t * 0.7) % 4
        let post = SDF3D.cylinder(radius: 0.42, height: 2.6).at(-2.9, 0.2, 0)
            .colored(Color(hex: 0x9adcf0))
        let bar = SDF3D.box(width: 2.2, height: 0.55, depth: 0.55).at(-2.2, 0.75, 0)
            .colored(Color(hex: 0xffb454))
        drawSDF3D(post.columnsUnion(bar, radius: 0.28, count: ribs))

        // A scored sphere: an engraved equator ring plus a grooved band above it, the
        // detailing surfaces two thin planes through the body.
        let globe = SDF3D.sphere(radius: 1.0).colored(Color(hex: 0xff6f61))
            .engrave(.plane(normal: Vector3(0, 1, 0), offset: 0.0).at(0, 0.2, 0),
                     depth: 0.05)
            .groove(.plane(normal: Vector3(0, 1, 0), offset: 0.0).at(0, 0.75, 0),
                    depth: 0.06, width: 0.07)
        drawSDF3D(globe.at(-0.3, 0.2, 0))

        // A beaded box: a tongue ridge wraps it where a sphere's surface crosses.
        let beaded = SDF3D.box(width: 1.2, height: 1.2, depth: 1.2)
            .rotatedY(t * 0.4)
            .tongue(.sphere(radius: 0.85), height: 0.08, width: 0.06)
            .colored(Color(hex: 0x46c2ff))
        drawSDF3D(beaded.at(2.0, 0.2, 0))

        // The pipe: only the bead along a sphere/plane crossing survives, a floating
        // ring traced where the two surfaces met.
        let ring = SDF3D.sphere(radius: 0.8)
            .pipe(.plane(normal: Vector3(0, 1, 0), offset: 0), radius: 0.09)
            .colored(Color(hex: 0xb6ff5a))
        drawSDF3D(ring.rotatedZ(0.5).at(3.7, 0.6, 0))
    }
}
