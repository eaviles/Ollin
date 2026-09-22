import CoreGraphics
import Foundation
import Metal

/// Where a headless drive's frame memory comes from, when something other
/// than the system wants to own it.
///
/// A frame on its way out of an export takes two frame-sized allocations:
/// the shared buffer the GPU reads the picture back into, and the copy a
/// `CGImage` is built over for the writer. Both are ordinarily the system's,
/// and both die inside the frame they were made for. Installing one of these
/// on `OllinApp.frameMemory` hands out that memory instead and hears each
/// piece come back, which is what lets a test count how many frames are
/// alive at any moment of a run from memory it owns, rather than from a
/// process-wide number every other suite in the process moves. Nothing is
/// installed in a normal run, and the drives read it once per frame.
package protocol ExportFrameMemory: AnyObject, Sendable {
    /// Memory of at least `byteCount` bytes, page-aligned: a readback buffer
    /// wraps it without a copy, and Metal asks for whole pages.
    func allocate(byteCount: Int) -> UnsafeMutableRawPointer
    /// Memory `allocate` handed out, read by nothing any more, on whichever
    /// thread let go of it last.
    func release(_ pointer: UnsafeMutableRawPointer, byteCount: Int)
}

extension OllinApp {
    /// The frame memory the headless drives draw on, when a test installs one.
    package nonisolated(unsafe) static var frameMemory: (any ExportFrameMemory)?
}

/// What a frame image's bytes belong to, carried by the image's data
/// provider until the image is let go.
private final class FrameCopyOwner {
    let memory: (any ExportFrameMemory)?
    init(memory: (any ExportFrameMemory)?) { self.memory = memory }
}

/// Called by the system when a frame image's bytes are let go.
private func releaseFrameCopy(_ info: UnsafeMutableRawPointer?, _ data: UnsafeRawPointer, _ size: Int) {
    guard let info else { return }
    let owner = Unmanaged<FrameCopyOwner>.fromOpaque(info).takeRetainedValue()
    let pointer = UnsafeMutableRawPointer(mutating: data)
    if let memory = owner.memory {
        memory.release(pointer, byteCount: size)
    } else {
        pointer.deallocate()
    }
}

extension MetalRenderer {
    /// A shared buffer the GPU reads a frame back into: the system's own
    /// unless frame memory is installed, in which case the buffer wraps that
    /// memory without a copy and hands it back when Metal lets the buffer go.
    func makeReadbackBuffer(byteCount: Int) -> MTLBuffer? {
        guard let memory = OllinApp.frameMemory else {
            return device.makeBuffer(length: byteCount, options: .storageModeShared)
        }
        let page = Int(getpagesize())
        let length = (byteCount + page - 1) / page * page
        let pointer = memory.allocate(byteCount: length)
        return device.makeBuffer(bytesNoCopy: pointer, length: length, options: .storageModeShared) { _, _ in
            memory.release(pointer, byteCount: length)
        }
    }

    /// The bytes of a frame copied into memory of their own and wrapped for
    /// a `CGImage`. The copy is let go when the image is, and installed
    /// frame memory hears it.
    nonisolated static func frameDataProvider(copying bytes: UnsafeRawPointer, byteCount: Int) -> CGDataProvider? {
        let memory = OllinApp.frameMemory
        let pointer = memory?.allocate(byteCount: byteCount)
            ?? UnsafeMutableRawPointer.allocate(byteCount: byteCount, alignment: 16)
        pointer.copyMemory(from: bytes, byteCount: byteCount)
        let owner = FrameCopyOwner(memory: memory)
        guard let provider = CGDataProvider(dataInfo: Unmanaged.passRetained(owner).toOpaque(),
                                            data: pointer, size: byteCount,
                                            releaseData: releaseFrameCopy) else {
            releaseFrameCopy(Unmanaged.passUnretained(owner).toOpaque(), pointer, byteCount)
            return nil
        }
        return provider
    }
}
