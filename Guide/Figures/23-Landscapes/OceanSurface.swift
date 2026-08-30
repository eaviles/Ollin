// figure: frame=150 probe
//
// Guide diagram (Chapter 23): a sea built from its own wave spectrum. One
// inverse Fourier transform on the GPU makes the whole surface, and the grid
// that draws it is worked out inside the draw call from nothing but vertex
// indices. Marked as a probe: it is the witness for the ocean draw path.
import Ollin

final class OceanSurface_Figure: Sketch {
    override var canvasSize: CanvasSize { .size(1180, 540) }

    override func draw() {
        background(Color(hex: 0x8FB6D4))
        toneMap(.aces)

        // The sky is set low, and the same elevation aims the light, so the
        // sparkle on the water and the sun above it are the same sun.
        let elevation = 0.14
        environment(.sky(turbidity: 2.5, sunElevation: elevation))
        light(.directional(Color(hex: 0xFFF1DC),
                           direction: Vector3(0, -sin(elevation), -cos(elevation)),
                           intensity: 1.1))

        camera(.perspective(eye: Vector3(0, 4.4, -95), target: Vector3(0, 2.4, 220),
                            fieldOfView: .pi / 3.2))

        let sea = makeOceanField(Ocean(waveHeight: 2.8, windSpeed: 12, windDirection: 90,
                                   choppiness: 1.25, patchSize: 170, smallestWave: 0.6,
                                   seed: 7),
                             resolution: 512)
        drawOcean(sea, segments: 360, tiles: 7)
    }
}
