import Foundation
import UIKit

/// The number of 90-degree clockwise turns that stand the rear camera's
/// sensor-landscape buffer upright for the current device hold: the count the
/// segmentation stream carries on the wire, and the count the hand-pose pass
/// uses to orient the model and read depth pixels. The rear sensor is
/// landscape-right, so landscape-right is 0 turns and portrait is one CW turn.
/// (If a hold ever reads rotated the wrong way on-device, flip the mapping here;
/// every streamer reads it from this one spot.)
func captureQuarterTurns() -> UInt8 {
    // ARKit delivers its delegate callbacks on the main thread, so this runs
    // there; assume the main actor to read the interface orientation.
    let orientation = MainActor.assumeIsolated {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.interfaceOrientation ?? .portrait
    }
    switch orientation {
    case .portrait:           return 1
    case .landscapeLeft:      return 2
    case .landscapeRight:     return 0
    case .portraitUpsideDown: return 3
    default:                  return 1
    }
}
