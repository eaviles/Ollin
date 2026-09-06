// The web page's expander: the entry points the page calls into the shared
// expander (`Sources/OllinExpander`) once it is compiled to WebAssembly.
// Built by Scripts/build-web-expander.sh into the framework's resources as
// WebExpander.wasm, never by the package itself: the file uses the
// WebAssembly export attribute, and it is the player part of a page rather
// than a part of the framework.
//
// The page writes a run of source records (`WebSourceLayout`) into the
// buffer `ollin_input` hands out, calls `ollin_expand`, and reads the
// vertices back from `ollin_output`: seven floats each (the position, the
// coverage, and the color), the layout the page's triangle programs bind.
// Both buffers live in the module's own memory and are grown as needed; a
// pointer handed out stays good until the next call that hands one out.

nonisolated(unsafe) private var input: UnsafeMutablePointer<Float>? = nil
nonisolated(unsafe) private var inputCapacity = 0
nonisolated(unsafe) private var output: UnsafeMutablePointer<Float>? = nil
nonisolated(unsafe) private var outputCapacity = 0
nonisolated(unsafe) private var outputCount = 0

/// Room for `count` floats of records; the pointer the page writes them to.
@_expose(wasm, "ollin_input")
@_cdecl("ollin_input")
public func ollinInput(_ count: Int32) -> UnsafeMutablePointer<Float>? {
    let needed = Int(max(1, count))
    if needed > inputCapacity {
        input?.deallocate()
        input = UnsafeMutablePointer<Float>.allocate(capacity: needed)
        inputCapacity = needed
    }
    return input
}

/// Expand the first `count` floats of the input as records. Returns the
/// vertex count written to the output, or -1 when a record is malformed.
@_expose(wasm, "ollin_expand")
@_cdecl("ollin_expand")
public func ollinExpand(_ count: Int32) -> Int32 {
    outputCount = 0
    let n = Int(max(0, count))
    guard let input, n <= inputCapacity else { return -1 }
    let records = WebSourceExpander.expand(UnsafeBufferPointer(start: input, count: n)) { v in
        if outputCount + 7 > outputCapacity {
            let grown = max(outputCount * 2, 7 * 4096)
            let next = UnsafeMutablePointer<Float>.allocate(capacity: grown)
            if let output, outputCount > 0 { next.update(from: output, count: outputCount) }
            output?.deallocate()
            output = next
            outputCapacity = grown
        }
        let o = output!
        o[outputCount] = v.x
        o[outputCount + 1] = v.y
        o[outputCount + 2] = v.coverage
        o[outputCount + 3] = v.color.x
        o[outputCount + 4] = v.color.y
        o[outputCount + 5] = v.color.z
        o[outputCount + 6] = v.color.w
        outputCount += 7
    }
    guard records != nil else { return -1 }
    return Int32(outputCount / 7)
}

/// The vertices the last `ollin_expand` wrote.
@_expose(wasm, "ollin_output")
@_cdecl("ollin_output")
public func ollinOutput() -> UnsafeMutablePointer<Float>? {
    output
}
