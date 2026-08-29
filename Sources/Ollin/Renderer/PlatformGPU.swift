import Metal

/// The storage mode for a texture the CPU fills once and the GPU only reads:
/// an image, a glyph page, a stand-in.
///
/// A desktop machine can hold a discrete GPU, whose memory is its own, so the
/// texture keeps a copy on each side and the driver carries a write across. A
/// phone or a tablet has one memory for both, so the same texture is written
/// where it is read and no copy exists to carry.
#if os(macOS)
let ollinUploadStorageMode: MTLStorageMode = .managed
#else
let ollinUploadStorageMode: MTLStorageMode = .shared
#endif
