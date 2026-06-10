//
//  Ollin Camera — host / installer.
//
//  A minimal app whose only job is to activate (install) the embedded CMIO
//  system extension via the SystemExtensions framework, then report status.
//  Must run as a bundled .app (the activation API reads the app bundle to find
//  the embedded extension), so launch it with `open OllinCamera.app`.
//

import AppKit
import SystemExtensions

let extensionIdentifier = "dev.ollin.OllinCamera.Extension"

final class AppDelegate: NSObject, NSApplicationDelegate, OSSystemExtensionRequestDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("[OllinCamera] Requesting activation of \(extensionIdentifier)…")
        let request = OSSystemExtensionRequest.activationRequest(forExtensionWithIdentifier: extensionIdentifier, queue: .main)
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    func request(_ request: OSSystemExtensionRequest,
                 actionForReplacingExtension existing: OSSystemExtensionProperties,
                 withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
        NSLog("[OllinCamera] Replacing existing \(existing.bundleVersion) with \(ext.bundleVersion)")
        return .replace
    }

    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        NSLog("[OllinCamera] Needs approval — System Settings ▸ General ▸ Login Items & Extensions ▸ Camera Extensions, allow ‘Ollin Camera’.")
    }

    func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        NSLog("[OllinCamera] Activation finished (result \(result.rawValue): 0 = completed, 1 = completes after reboot).")
        NSLog("[OllinCamera] Open Photo Booth or QuickTime ▸ New Movie Recording and pick ‘Ollin Camera’.")
    }

    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        NSLog("[OllinCamera] Activation FAILED: \(error.localizedDescription)  —  \(error)")
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
