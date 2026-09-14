import Foundation
import COllinSourceKit

/// Code completion from the Swift toolchain's own SourceKit service, for a host
/// that edits a sketch inside its window. A sketch buffer gets every name the
/// compiler knows there: every `Sketch` method, every value type and its
/// members, whatever the buffer itself declares, each with the call pattern to
/// insert and the parameters as placeholders.
///
/// The toolchain ships the service as a framework with no header, so nothing is
/// linked at build time. `load()` finds the framework beside `swiftc`, opens it
/// with `dlopen`, and binds each entry point by name; a machine whose toolchain
/// lacks the service gets `nil` and the host runs without completion. The
/// out-of-process framework is tried first: a crash in the service then comes
/// back as a refused request rather than taking the stage down, which is the
/// difference that matters during a set. The in-process one is the fallback.
///
/// A completion runs as a **session** at one point in the text (the start of the
/// word being typed, or the position right after a member dot). `open` checks
/// the buffer once and returns the first list; `update` filters the same session
/// again with more of the word typed, which costs about a millisecond; `close`
/// ends it. A host opens when the caret enters a new word, updates per keystroke
/// inside it, and closes when the list is dismissed. Requests are synchronous,
/// so a host makes them off the main thread; the instance serializes them.
public final class CodeCompleter: @unchecked Sendable {

    /// One row the service offered.
    public struct Completion: Sendable, Equatable {
        /// The name as the service spells an overload: `drawCircle(:::)` for the
        /// positional form, `drawCircle(center:radius:)` for the labeled one.
        public let name: String
        /// The presentable signature: `drawCircle(x: Double, y: Double, radius: Double)`.
        public let label: String
        /// The text to insert, with each parameter as an editor placeholder:
        /// `drawCircle(<#x: Double#>, <#y: Double#>, <#radius: Double#>)`.
        public let insertion: String
        /// The type of the value the row produces: `Void` for a plain call,
        /// `Color` for a color, `Double` for a number.
        public let typeName: String
        public let kind: Kind
        /// How many UTF-8 bytes *before* the session's point the insertion
        /// replaces, when the service rewrites what is already there (a `.` that
        /// becomes `?.`, say). Zero for nearly every row.
        public let bytesToErase: Int

        public init(name: String, label: String, insertion: String, typeName: String,
                    kind: Kind, bytesToErase: Int = 0) {
            self.name = name
            self.label = label
            self.insertion = insertion
            self.typeName = typeName
            self.kind = kind
            self.bytesToErase = bytesToErase
        }
    }

    /// What kind of thing a row names, for the glyph a list shows beside it.
    public enum Kind: Sendable, Equatable {
        case function, initializer, property, type, enumCase, keyword, other
    }

    /// Where a session lives: the buffer's name (the path the host compiles it
    /// as, which is also what the compiler arguments name) and the UTF-8 byte
    /// offset of the completion point in the text handed to `open`.
    public struct Session: Sendable, Equatable {
        public let name: String
        public let offset: Int

        public init(name: String, offset: Int) {
            self.name = name
            self.offset = offset
        }
    }

    public enum Failure: Error, CustomStringConvertible, Sendable {
        /// The service answered the request with an error, given verbatim.
        case refused(String)

        public var description: String {
            switch self {
            case .refused(let message): return "completion refused: \(message)"
            }
        }
    }

    /// The framework this completer runs on, for a status line.
    public let frameworkPath: String

    private let api: API
    private let uid: UIDs
    private let lock = NSLock()

    // MARK: - Loading

    /// The frameworks to try, in order: the out-of-process service beside
    /// `swiftc`, then the in-process one. Empty when no toolchain answers.
    public static var frameworkPaths: [String] {
        guard let swiftc = xcrunFind("swiftc") else { return [] }
        let usr = ((swiftc as NSString).deletingLastPathComponent as NSString).deletingLastPathComponent
        let lib = (usr as NSString).appendingPathComponent("lib")
        return [
            (lib as NSString).appendingPathComponent("sourcekitd.framework/sourcekitd"),
            (lib as NSString).appendingPathComponent("sourcekitdInProc.framework/sourcekitdInProc"),
        ]
    }

    /// The completer over the first framework that loads, or `nil` when none
    /// does (a toolchain without the service). The load is a few milliseconds;
    /// the first request the service answers then costs seconds while it reads
    /// the framework's modules, which is why a host warms it up at launch.
    public static func load() -> CodeCompleter? {
        load(from: frameworkPaths)
    }

    /// `load()` over an explicit list of framework binaries.
    public static func load(from paths: [String]) -> CodeCompleter? {
        for path in paths {
            if let completer = loadOne(path) { return completer }
        }
        return nil
    }

    /// One instance per framework for the process's life: the service is
    /// initialized once per library, and `dlopen` hands back the same image.
    private static let registry = Registry()

    private final class Registry: @unchecked Sendable {
        let lock = NSLock()
        var loaded: [String: CodeCompleter] = [:]
    }

    private static func loadOne(_ path: String) -> CodeCompleter? {
        registry.lock.lock()
        defer { registry.lock.unlock() }
        if let existing = registry.loaded[path] { return existing }
        guard FileManager.default.fileExists(atPath: path),
              let handle = dlopen(path, RTLD_LAZY | RTLD_LOCAL),
              let api = API(handle: handle) else { return nil }
        api.initialize()
        let completer = CodeCompleter(frameworkPath: path, api: api)
        registry.loaded[path] = completer
        return completer
    }

    private init(frameworkPath: String, api: API) {
        self.frameworkPath = frameworkPath
        self.api = api
        self.uid = UIDs(api)
    }

    // MARK: - Sessions

    /// Start a session at `session.offset` in `source`, compiled with
    /// `arguments` (see `SketchLoader.completionArguments(sourceFile:)`), and
    /// return the rows matching `filter`, at most `limit` of them, in the
    /// service's own order: an exact and a short match ahead of a long one, a
    /// member of the buffer's own class ahead of a global.
    public func open(_ session: Session, source: String, arguments: [String],
                     filter: String, limit: Int = 60) throws -> [Completion] {
        lock.lock()
        defer { lock.unlock() }
        let request = api.dictionaryCreate(nil, nil, 0)
        defer { api.release(request) }
        api.setUID(request, uid.request, uid.open)
        source.withCString { api.setString(request, uid.sourceText, $0) }
        session.name.withCString {
            api.setString(request, uid.name, $0)
            api.setString(request, uid.sourceFile, $0)
        }
        api.setInt64(request, uid.offset, Int64(session.offset))
        let args = api.arrayCreate(nil, 0)
        for argument in arguments {
            // The append index is every bit set, which `Int` spells as -1.
            argument.withCString { api.arraySetString(args, -1, $0) }
        }
        api.setValue(request, uid.compilerArgs, args)
        api.release(args)   // the request holds its own reference now
        let options = optionsDictionary(filter: filter, limit: limit)
        api.setValue(request, uid.options, options)
        api.release(options)
        return try send(request)
    }

    /// Filter an open session again with more (or less) of the word typed.
    public func update(_ session: Session, filter: String, limit: Int = 60) throws -> [Completion] {
        lock.lock()
        defer { lock.unlock() }
        let request = api.dictionaryCreate(nil, nil, 0)
        defer { api.release(request) }
        api.setUID(request, uid.request, uid.update)
        session.name.withCString { api.setString(request, uid.name, $0) }
        api.setInt64(request, uid.offset, Int64(session.offset))
        let options = optionsDictionary(filter: filter, limit: limit)
        api.setValue(request, uid.options, options)
        api.release(options)
        return try send(request)
    }

    /// End a session. Closing one that is not open is not an error.
    public func close(_ session: Session) {
        lock.lock()
        defer { lock.unlock() }
        let request = api.dictionaryCreate(nil, nil, 0)
        defer { api.release(request) }
        api.setUID(request, uid.request, uid.close)
        session.name.withCString { api.setString(request, uid.name, $0) }
        api.setInt64(request, uid.offset, Int64(session.offset))
        let response = api.send(request)
        api.dispose(response)
    }

    /// The filter and the presentation options every session request carries.
    /// The filter matches by prefix, never fuzzily: a fuzzy match on a word
    /// with no real match dredges the longest system constants up from the
    /// bottom of the namespace, and on a stage an empty list is the honest
    /// answer. Names that start with an underscore are hidden, since a sketch
    /// never wants them, and the service's own order is kept (sorting by name
    /// would put every `init` ahead of a color).
    private func optionsDictionary(filter: String, limit: Int) -> osk_object_t? {
        let options = api.dictionaryCreate(nil, nil, 0)
        filter.withCString { api.setString(options, uid.filterText, $0) }
        api.setInt64(options, uid.requestLimit, Int64(limit))
        api.setInt64(options, uid.hideUnderscores, 1)
        api.setInt64(options, uid.fuzzyMatching, 0)
        api.setInt64(options, uid.addInnerOperators, 0)
        api.setInt64(options, uid.sortByName, 0)
        return options
    }

    private func send(_ request: osk_object_t?) throws -> [Completion] {
        let response = api.send(request)
        defer { api.dispose(response) }
        if api.isError(response) {
            let message = api.errorDescription(response).map { String(cString: $0) } ?? "unknown error"
            throw Failure.refused(message)
        }
        return completions(in: response)
    }

    private func completions(in response: osk_response_t?) -> [Completion] {
        let value = api.responseValue(response)
        let rows = api.dictionaryGetValue(value, uid.results)
        guard Int(api.variantType(rows)) == Int(OSK_VARIANT_ARRAY) else { return [] }
        let count = api.arrayCount(rows)
        var out: [Completion] = []
        out.reserveCapacity(count)
        for index in 0..<count {
            let row = api.arrayGetValue(rows, index)
            guard let name = string(api.dictionaryGetString(row, uid.name)) else { continue }
            if api.dictionaryGetBool(row, uid.notRecommended) { continue }
            let sourceText = string(api.dictionaryGetString(row, uid.sourceText)) ?? name
            let kindName = api.dictionaryGetUID(row, uid.kind)
                .flatMap { api.uidString($0) }.map { String(cString: $0) } ?? ""
            out.append(Completion(
                name: name,
                label: string(api.dictionaryGetString(row, uid.description)) ?? name,
                insertion: CompletionText.reducingPlaceholders(sourceText),
                typeName: string(api.dictionaryGetString(row, uid.typeName)) ?? "",
                kind: Self.kind(of: kindName),
                bytesToErase: Int(api.dictionaryGetInt64(row, uid.bytesToErase))))
        }
        return out
    }

    private func string(_ pointer: UnsafePointer<CChar>?) -> String? {
        pointer.map { String(cString: $0) }
    }

    /// The row kind from the service's kind name (`source.lang.swift.decl.var.instance`).
    static func kind(of uidName: String) -> Kind {
        let prefix = "source.lang.swift."
        guard uidName.hasPrefix(prefix) else { return .other }
        let rest = uidName.dropFirst(prefix.count)
        if rest.hasPrefix("decl.function.constructor") { return .initializer }
        if rest.hasPrefix("decl.function") { return .function }
        if rest.hasPrefix("decl.var") { return .property }
        if rest.hasPrefix("decl.enumelement") { return .enumCase }
        if rest.hasPrefix("decl.") { return .type }
        if rest.hasPrefix("keyword") { return .keyword }
        return .other
    }

    // MARK: - The bound interface

    /// The entry points, bound by name. `nil` when any is missing, which means
    /// the library at that path is not the service.
    private struct API {
        let initialize: osk_initialize_t
        let uidFromString: osk_uid_get_from_cstr_t
        let uidString: osk_uid_get_string_ptr_t
        let dictionaryCreate: osk_request_dictionary_create_t
        let setString: osk_request_dictionary_set_string_t
        let setInt64: osk_request_dictionary_set_int64_t
        let setUID: osk_request_dictionary_set_uid_t
        let setValue: osk_request_dictionary_set_value_t
        let arrayCreate: osk_request_array_create_t
        let arraySetString: osk_request_array_set_string_t
        let release: osk_request_release_t
        let send: osk_send_request_sync_t
        let dispose: osk_response_dispose_t
        let isError: osk_response_is_error_t
        let errorDescription: osk_response_error_get_description_t
        let responseValue: osk_response_get_value_t
        let variantType: osk_variant_get_type_t
        let dictionaryGetValue: osk_variant_dictionary_get_value_t
        let dictionaryGetString: osk_variant_dictionary_get_string_t
        let dictionaryGetInt64: osk_variant_dictionary_get_int64_t
        let dictionaryGetBool: osk_variant_dictionary_get_bool_t
        let dictionaryGetUID: osk_variant_dictionary_get_uid_t
        let arrayCount: osk_variant_array_get_count_t
        let arrayGetValue: osk_variant_array_get_value_t

        init?(handle: UnsafeMutableRawPointer) {
            func bind<T>(_ name: String, _: T.Type = T.self) -> T? {
                guard let symbol = dlsym(handle, "sourcekitd_" + name) else { return nil }
                return unsafeBitCast(symbol, to: T.self)
            }
            guard let initialize: osk_initialize_t = bind("initialize"),
                  let uidFromString: osk_uid_get_from_cstr_t = bind("uid_get_from_cstr"),
                  let uidString: osk_uid_get_string_ptr_t = bind("uid_get_string_ptr"),
                  let dictionaryCreate: osk_request_dictionary_create_t = bind("request_dictionary_create"),
                  let setString: osk_request_dictionary_set_string_t = bind("request_dictionary_set_string"),
                  let setInt64: osk_request_dictionary_set_int64_t = bind("request_dictionary_set_int64"),
                  let setUID: osk_request_dictionary_set_uid_t = bind("request_dictionary_set_uid"),
                  let setValue: osk_request_dictionary_set_value_t = bind("request_dictionary_set_value"),
                  let arrayCreate: osk_request_array_create_t = bind("request_array_create"),
                  let arraySetString: osk_request_array_set_string_t = bind("request_array_set_string"),
                  let release: osk_request_release_t = bind("request_release"),
                  let send: osk_send_request_sync_t = bind("send_request_sync"),
                  let dispose: osk_response_dispose_t = bind("response_dispose"),
                  let isError: osk_response_is_error_t = bind("response_is_error"),
                  let errorDescription: osk_response_error_get_description_t = bind("response_error_get_description"),
                  let responseValue: osk_response_get_value_t = bind("response_get_value"),
                  let variantType: osk_variant_get_type_t = bind("variant_get_type"),
                  let dictionaryGetValue: osk_variant_dictionary_get_value_t = bind("variant_dictionary_get_value"),
                  let dictionaryGetString: osk_variant_dictionary_get_string_t = bind("variant_dictionary_get_string"),
                  let dictionaryGetInt64: osk_variant_dictionary_get_int64_t = bind("variant_dictionary_get_int64"),
                  let dictionaryGetBool: osk_variant_dictionary_get_bool_t = bind("variant_dictionary_get_bool"),
                  let dictionaryGetUID: osk_variant_dictionary_get_uid_t = bind("variant_dictionary_get_uid"),
                  let arrayCount: osk_variant_array_get_count_t = bind("variant_array_get_count"),
                  let arrayGetValue: osk_variant_array_get_value_t = bind("variant_array_get_value")
            else { return nil }
            self.initialize = initialize
            self.uidFromString = uidFromString
            self.uidString = uidString
            self.dictionaryCreate = dictionaryCreate
            self.setString = setString
            self.setInt64 = setInt64
            self.setUID = setUID
            self.setValue = setValue
            self.arrayCreate = arrayCreate
            self.arraySetString = arraySetString
            self.release = release
            self.send = send
            self.dispose = dispose
            self.isError = isError
            self.errorDescription = errorDescription
            self.responseValue = responseValue
            self.variantType = variantType
            self.dictionaryGetValue = dictionaryGetValue
            self.dictionaryGetString = dictionaryGetString
            self.dictionaryGetInt64 = dictionaryGetInt64
            self.dictionaryGetBool = dictionaryGetBool
            self.dictionaryGetUID = dictionaryGetUID
            self.arrayCount = arrayCount
            self.arrayGetValue = arrayGetValue
        }
    }

    /// The interned names a request and a response speak in, made once.
    private struct UIDs {
        let request, name, sourceFile, sourceText, offset, compilerArgs, options: osk_uid_t
        let filterText, requestLimit, hideUnderscores, fuzzyMatching, addInnerOperators, sortByName: osk_uid_t
        let results, description, typeName, kind, bytesToErase, notRecommended: osk_uid_t
        let open, update, close: osk_uid_t

        init(_ api: API) {
            func uid(_ name: String) -> osk_uid_t {
                // The service interns every name it is given; a nil here would
                // mean the library is not the service, which `API.init` refused.
                name.withCString { api.uidFromString($0)! }
            }
            request = uid("key.request")
            name = uid("key.name")
            sourceFile = uid("key.sourcefile")
            sourceText = uid("key.sourcetext")
            offset = uid("key.offset")
            compilerArgs = uid("key.compilerargs")
            options = uid("key.codecomplete.options")
            filterText = uid("key.codecomplete.filtertext")
            requestLimit = uid("key.codecomplete.requestlimit")
            hideUnderscores = uid("key.codecomplete.hideunderscores")
            fuzzyMatching = uid("key.codecomplete.fuzzymatching")
            addInnerOperators = uid("key.codecomplete.addinneroperators")
            sortByName = uid("key.codecomplete.sort.byname")
            results = uid("key.results")
            description = uid("key.description")
            typeName = uid("key.typename")
            kind = uid("key.kind")
            bytesToErase = uid("key.num_bytes_to_erase")
            notRecommended = uid("key.not_recommended")
            open = uid("source.request.codecomplete.open")
            update = uid("source.request.codecomplete.update")
            close = uid("source.request.codecomplete.close")
        }
    }

    /// `xcrun --find <tool>`, or `nil` when there is no toolchain to ask.
    private static func xcrunFind(_ tool: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["--find", tool]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let path = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else { return nil }
        return path
    }
}

/// The text-side half of completion: where the word under the caret starts,
/// whether the caret follows a member dot, how a placeholder is spelled, and
/// where the next one is. Pure functions over the buffer's text, in the UTF-16
/// offsets an `NSTextView` addresses by, so a host and a test share one
/// reading of the text.
public enum CompletionText {

    /// The characters an identifier is made of. Swift admits more, but a sketch
    /// is written in these, and a name typed in anything else is not one the
    /// service can complete anyway.
    static func isIdentifier(_ character: Character) -> Bool {
        character == "_" || character.isLetter || character.isNumber
    }

    /// The UTF-16 offset where the word ending at `caret` begins: `caret`
    /// itself when no word ends there (after a space, a bracket, a dot), and
    /// also when what ends there starts with a digit, since that is a number.
    public static func wordStart(in text: String, caret: Int) -> Int {
        let caretIndex = index(of: caret, in: text)
        var start = caretIndex
        while start > text.startIndex {
            let before = text.index(before: start)
            guard isIdentifier(text[before]) else { break }
            start = before
        }
        guard start < caretIndex else { return caret }
        if text[start].isNumber { return caret }
        return start.utf16Offset(in: text)
    }

    /// The word typed so far before `caret`, empty at a word start.
    public static func prefix(in text: String, caret: Int) -> String {
        let start = wordStart(in: text, caret: caret)
        guard start < caret else { return "" }
        return String(text[index(of: start, in: text)..<index(of: caret, in: text)])
    }

    /// Whether the caret sits right after a member dot: `Color.` and
    /// `background(.` both, but not the dot of `0.5` or the second of `..<`.
    public static func isMemberAccess(in text: String, caret: Int) -> Bool {
        let caretIndex = index(of: caret, in: text)
        guard caretIndex > text.startIndex else { return false }
        let dot = text.index(before: caretIndex)
        guard text[dot] == "." else { return false }
        guard dot > text.startIndex else { return false }
        let before = text[text.index(before: dot)]
        return before != "." && !before.isNumber
    }

    /// The service spells a parameter as `<#T##x: Double##Double#>`, its display
    /// and its type in one token. The short editor form `<#x: Double#>` is what
    /// goes in the buffer: it reads as the slot it is, the compiler recognizes it
    /// and names its line when it is left behind, and Tab finds it.
    public static func reducingPlaceholders(_ sourceText: String) -> String {
        var out = ""
        var rest = sourceText[...]
        while let open = rest.range(of: "<#") {
            out += rest[..<open.lowerBound]
            guard let close = rest[open.upperBound...].range(of: "#>") else {
                out += rest[open.lowerBound...]
                return out
            }
            var inside = rest[open.upperBound..<close.lowerBound]
            if inside.hasPrefix("T##") { inside = inside.dropFirst(3) }
            if let separator = inside.range(of: "##") { inside = inside[..<separator.lowerBound] }
            out += "<#" + inside + "#>"
            rest = rest[close.upperBound...]
        }
        out += rest
        return out
    }

    private static let placeholderPattern = try! NSRegularExpression(pattern: "<#[^#\\n]*#>")

    /// The next placeholder at or after `caret`, wrapping to the top of the
    /// text when none follows; `nil` when the text holds none. A UTF-16 range,
    /// ready to select.
    public static func placeholder(in text: String, after caret: Int) -> NSRange? {
        let all = NSRange(location: 0, length: (text as NSString).length)
        let matches = placeholderPattern.matches(in: text, range: all).map(\.range)
        guard !matches.isEmpty else { return nil }
        return matches.first { $0.location >= caret } ?? matches[0]
    }

    /// The UTF-8 byte offset of a UTF-16 offset, which is what the service counts in.
    public static func utf8Offset(of utf16Offset: Int, in text: String) -> Int {
        text.utf8.distance(from: text.startIndex, to: index(of: utf16Offset, in: text))
    }

    /// The UTF-16 offset of a UTF-8 byte offset.
    public static func utf16Offset(ofUTF8 utf8Offset: Int, in text: String) -> Int {
        let clamped = max(0, min(utf8Offset, text.utf8.count))
        return text.utf8.index(text.startIndex, offsetBy: clamped).utf16Offset(in: text)
    }

    private static func index(of utf16Offset: Int, in text: String) -> String.Index {
        let clamped = max(0, min(utf16Offset, text.utf16.count))
        return String.Index(utf16Offset: clamped, in: text)
    }
}
