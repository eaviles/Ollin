//
//  Ollin Camera — system extension entry point.
//
//  Publishes a virtual camera device through Core Media I/O and hands control
//  to the extension service run loop. The system launches this process on
//  demand when a client opens the camera; we never run it directly.
//
//  Phase A: the device emits a generated test pattern, so the bundle / sign /
//  activate pipeline can be proven end to end before real sketch frames are
//  wired in over a sink stream.
//

import Foundation
import CoreMediaIO

let providerSource = OllinCameraProviderSource(clientQueue: nil)
CMIOExtensionProvider.startService(provider: providerSource.provider)

CFRunLoopRun()
