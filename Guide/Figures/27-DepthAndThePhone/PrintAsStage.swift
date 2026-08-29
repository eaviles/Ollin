// figure: frame=0
//
// Guide figure (Chapter 27): two printed pictures the phone knows, each carrying
// the same little city of columns. One card lies flat on a table, one poster hangs
// on the wall behind it. The drawing code is identical for both: it works in the
// marker's own frame, where the print is the x-y plane and z rises off the paper.
//
// The finds are staged rather than read, the way this chapter's other figures stage
// a depth camera: the same PhoneMarker a phone fills in, built by hand from a
// PhoneMarkerSample so the figure renders anywhere.
import Foundation
import simd
import Ollin
import OllinPhone

final class PrintAsStage: Sketch {
    override var canvasSize: CanvasSize { .size(880, 520) }

    let stageColor = Color(hex: 0x252B3D)
    let towerColor = Color(hex: 0x6FD6C4)
    let frameColor = Color(hex: 0xFFB347)

    /// A staged find. The basis is what ARKit reports for a picture: the print lies
    /// in the anchor's x-z plane, and the anchor's y axis points out of the printed
    /// face, so `across` is the anchor's x and the print's up direction is its -z.
    static func stagedPrint(_ name: String, at position: SIMD3<Float>,
                            across: SIMD3<Float>, outOfTheFace: SIMD3<Float>,
                            width: Float, height: Float) -> PhoneMarker {
        let z = simd_cross(across, outOfTheFace)
        return PhoneMarker(PhoneMarkerSample(
            tracked: true, timestamp: 0, id: UUID(), name: name, kind: .image,
            transform: simd_float4x4(SIMD4(across, 0), SIMD4(outOfTheFace, 0),
                                     SIMD4(z, 0), SIMD4(position, 1)),
            size: SIMD3<Float>(width, height, 0)))
    }

    /// A card lying face up on the table, its top edge pointing away from us.
    let card = stagedPrint("card", at: SIMD3<Float>(-0.02, 0.75, 0.18),
                           across: SIMD3<Float>(1, 0, 0),
                           outOfTheFace: SIMD3<Float>(0, 1, 0),
                           width: 0.26, height: 0.18)

    /// A poster on the wall behind it, facing the room.
    let poster = stagedPrint("poster", at: SIMD3<Float>(0, 1.35, -1.2),
                             across: SIMD3<Float>(1, 0, 0),
                             outOfTheFace: SIMD3<Float>(0, 0, 1),
                             width: 0.42, height: 0.3)

    override func draw() {
        background(Color(hex: 0x0D1017))
        camera(.orbiting(target: Vector3(0.02, 1.0, -0.45), radius: 1.95,
                         azimuth: 0.5, elevation: 0.3, fieldOfView: .pi / 4))
        environment(.studio.intensity(1.0).lightingOnly())

        // The surfaces the prints sit on, hinted: a wall pane and a table slab.
        material(.clay)
        fill(Color(white: 0.16))
        withState {
            translate(0, 1.3, -1.24)
            drawBox(width: 1.5, height: 1.0, depth: 0.03)
        }
        withState {
            translate(-0.03, 0.71, 0.18)
            drawBox(width: 0.85, height: 0.06, depth: 0.5)
        }

        for marker in [card, poster] { drawCity(on: marker) }

        drawCaption("PrintAsStage: one placement per print, the same city on both")
    }

    /// The same drawing the PhoneMarkers example does: work in the marker's frame,
    /// where the print is the x-y plane and anything with a positive z stands off
    /// the paper.
    private func drawCity(on marker: PhoneMarker) {
        let width = marker.width, height = marker.height
        withState {
            transform(marker.placement)
            material(.clay)
            fill(stageColor)
            drawBox(width: width, height: height, depth: width * 0.004)

            let across = 12
            let down = max(2, Int((Double(across) * height / width).rounded()))
            let cell = width / Double(across)
            fill(towerColor)
            for row in 0..<down {
                for column in 0..<across {
                    let x = (Double(column) + 0.5) / Double(across) - 0.5
                    let y = (Double(row) + 0.5) / Double(down) - 0.5
                    let wave = noise(Double(column) * 0.35, Double(row) * 0.35)
                    let tall = width * 0.28 * (0.15 + wave * wave)
                    withState {
                        translate(x * width, y * height, tall / 2)
                        drawBox(width: cell * 0.55, height: cell * 0.55, depth: tall)
                    }
                }
            }
        }
        // The print's own edge, standing a whisker off the paper.
        withState {
            fill(frameColor)
            material(.clay)
            drawTube(marker.corners.map { $0 + marker.facing * 0.002 },
                     radius: width * 0.012, sides: 6, closed: true)
        }
    }
}
