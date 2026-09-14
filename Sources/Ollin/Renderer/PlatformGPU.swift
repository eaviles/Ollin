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

/// The options every runtime shader compile passes.
///
/// The compiler picks a language version of its own when none is named. On the
/// desk and the phone that is the newest one, which is what the built-in library
/// is written for; an iPad app running on the Mac gets a compiler whose default
/// is Metal 2.2, older than the ray-tracing namespace and the mesh stages the
/// library uses. The version is raised to the one the platform floor guarantees
/// only when the default sits below it; a compiler already past it keeps its
/// own, so the desk and the phone compile exactly as they would with no options.
package func ollinShaderCompileOptions() -> MTLCompileOptions {
    let options = MTLCompileOptions()
    let floor = MTLLanguageVersion.version4_0
    if options.languageVersion.rawValue < floor.rawValue {
        options.languageVersion = floor
    }
    return options
}
