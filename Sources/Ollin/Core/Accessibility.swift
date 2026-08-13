#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// The system accessibility settings a sketch can read.
///
/// Kept behind one seam so the platform difference lives in a single place.
enum OllinAccessibility {

    /// Whether the person using the machine has asked for less movement.
    ///
    /// A headless render reads `false` whatever the machine is set to, so an
    /// export is the same file wherever it runs.
    @MainActor
    static var prefersReducedMotion: Bool {
        if OllinApp.isRenderingHeadless { return false }
        #if canImport(AppKit)
        return NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        #elseif canImport(UIKit)
        return UIAccessibility.isReduceMotionEnabled
        #else
        return false
        #endif
    }
}
