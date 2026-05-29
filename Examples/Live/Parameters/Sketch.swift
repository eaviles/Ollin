import Foundation
import Ollin

// Parameters — tunable knobs with @Param. Run it under the live host to get
// live sliders in the inspector:
//
//   swift run OllinLive Examples/Live/Parameters/Sketch.swift
//
// Standalone (`swift run Example-Parameters`) just uses the default values.

@main
final class Parameters: Sketch {
    @Param(10...300) var radius = 140.0   // "Radius"
    @Param(0...4) var speed = 1.0         // "Speed"
    @Param(1...12) var rings = 5.0        // "Rings"

    override func draw() {
        background(.white)
        noFill()
        stroke(.black)
        strokeWeight(2)

        let count = Int(rings)
        for i in 0..<count {
            let t = Double(i) / Double(count)
            let phase: Double = time * speed + t * .tau
            let r: Double = radius * (0.25 + t) + sin(phase) * 24
            drawCircle(width / 2, height / 2, r)
        }
    }
}
