import Ollin

/// Volumes: a plume of smoke rising over a pedestal, a ball hanging in it, a
/// lamp above throwing the ball's shadow down through the smoke, and the
/// smoke's own shadow on the pedestal and the floor.
///
/// The smoke is a grid of density samples. Here the grid is a
/// `ComputeTexture3D` that a compute kernel of the sketch's own (`Plume.metal`)
/// fills every frame, 96 by 144 by 96 samples, with noise over the box's width
/// and depth that repeats from the bottom row to the top, read scrolled upward
/// and shaped into a column that widens and thins as it rises. The grid never
/// leaves the GPU, so the refill costs under a millisecond where a `Volume`
/// filled on the CPU (`Volume(width:height:depth:_:)`, the other way to build
/// one) holds 60 frames a second to about 32 samples a side. The
/// scroll comes back to where it started every twelve seconds, so the plume
/// rises without end and an export loops.
///
/// `drawVolume` marches each pixel's ray through the box after the solids are
/// drawn, reading their depth: the ball inside the plume is veiled only by the
/// smoke in front of it and hides the smoke behind it. Along the ray the smoke
/// takes light away (Beer's law) and gives back the lamp's light and the
/// ambient it scatters toward the eye; the lamp's light reaching each point has
/// crossed the smoke between, so the plume shades itself, and the ball's
/// shadow cuts a dark shaft down through it. With `castShadows()` on, the same
/// light-transmittance grid that shades the plume darkens the pedestal and the
/// floor under it, so a thick plume stands in its own shadow.
///
/// The `medium` parameter says what the plume is made of: gray `smoke`, a white
/// `cloud` that scatters nearly everything, `fire` glowing from inside, `ink`
/// that only darkens, a faint violet `nebula`. `thickness` scales the medium's
/// density, and the lamp can be swung around above the plume.
@main
final class Volumes: Sketch {

    @Param var medium: Medium = .smoke
    @Param(0.2 ... 3, icon: "aqi.medium", group: "Smoke") var thickness = 1.0
    @Param(0 ... 6.28, icon: "lamp.desk", group: "Lamp") var lampAround = 0.8

    /// The plume's grid, and the kernel that fills it each frame.
    private let plume = ComputeTexture3D(width: 96, height: 144, depth: 96)
    private let plumeKernel = try? ComputeKernel(entry: "plume", resource: "Plume", in: .module)

    override func draw() {
        background(Color(hex: 0x0E1014))
        toneMap(.aces)
        cameraShowcase(.turntable(period: 48), target: Vector3(0, 2.5, 0),
                       radius: 7.6, elevation: 0.14, fieldOfView: .pi / 4)
        // Each temporal sample starts the march at its own offsets, so the
        // resolve averages the march's fine grain away.
        temporalAntialiasing()

        ambientLight(Color(hex: 0x1B2230))
        castShadows()
        let lamp = Vector3(cos(lampAround) * 1.1, 6.4, sin(lampAround) * 1.1)
        spotLight(Color(hue: 0.08, saturation: 0.3, brightness: 1), at: lamp,
                  direction: Vector3(0, 1.5, 0) - lamp, coneAngle: 0.42, penumbra: 0.35,
                  intensity: 2.4)

        noStroke()
        fill(Color(hex: 0x3A3F47))
        drawGround(size: 20)
        withState {
            translate(0, 0.35, 0)
            fill(Color(hex: 0x6E737B))
            drawCylinder(radius: 0.55, height: 0.7)
        }
        // The ball hangs inside the plume, below the lamp.
        withState {
            translate(0.1, 3.0 + sin(time * 0.6) * 0.12, 0.05)
            fill(Color(hex: 0xC9A27A))
            drawSphere(radius: 0.2)
        }

        // The plume: the kernel refills the grid with its noise scrolled up one
        // grid height every twelve seconds, then the grid draws as the medium.
        if let plumeKernel {
            var params = ComputeParams()
            params.append(SIMD4<Float>(Float((time / 12).truncatingRemainder(dividingBy: 1)), 0, 0, 0))
            compute(plumeKernel, writing: plume, params: params)
        }
        var look = medium
        look.density *= thickness
        withState {
            translate(0, 0.7 + 2.1, 0)
            drawVolume(plume, width: 2.8, height: 4.2, depth: 2.8, medium: look)
        }

        withOverlay { drawCaption("Volumes: smoke a kernel writes, lit, shadowed, and casting its shadow") }
    }
}
