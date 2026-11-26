import Foundation
import os

/// The camera's picture, sent up the cable as video to a sketch that reads it.
///
/// A sketch on the Mac that reads `device.latestCamera?.picture` opens a
/// connection of its own to `PhoneWire.cameraPort`, and that connection is the
/// asking: while a client is on it, each camera frame of whichever ARKit mode
/// is running is compressed and sent with its own camera record, so the Mac
/// holds a picture and where the camera stood for it as one thing. With no
/// client nothing is compressed, so a sketch that wants only the tracking costs
/// the phone no video and no heat.
///
/// The work is `PhoneCameraSender`, in the file this app shares with the Mac,
/// so the Mac's tests run it: it skips a frame before compressing it while the
/// pictures before it have not left, since a picture built on the one before
/// cannot be dropped once it is made. This class is the phone's part: the
/// listener, and telling the sender when a sketch comes and goes.
final class CameraVideoStreamer: Sendable {

    /// Takes every frame of the camera; see `PhoneCameraSender.frame`.
    let sender: PhoneCameraSender
    private let server: SensorServer

    init() throws {
        // The sender writes through the server and the server tells the sender
        // who is there, so the server is handed over once both exist.
        let link = OSAllocatedUnfairLock<SensorServer?>(uncheckedState: nil)
        let sender = PhoneCameraSender { frame, whenTaken in
            guard let server = link.withLockUnchecked({ $0 }) else { return whenTaken() }
            server.send(frame, whenTaken: whenTaken)
        }
        let server = try SensorServer(port: PhoneWire.cameraPort, keepsOnlyNewest: true,
                                      onClientCountChange: { count in
            if count > 0 { sender.clientArrived() } else { sender.clientLeft() }
        })
        link.withLockUnchecked { $0 = server }
        self.sender = sender
        self.server = server
    }
}
