import Foundation
import Ollin
#if canImport(FoundationModels)
import FoundationModels
#endif

/// The machine's own language model as a `TuningModel`: Apple's on-device model,
/// so an ask never leaves the Mac and needs no account or key. It answers under
/// a schema built from the request, one optional property per parameter typed
/// by its kind (a number held to its range, a choice held to its menu), so a
/// reply is always well-formed and only the parameters the model chose to move
/// come back.
///
/// It is available where Apple Intelligence is on; `availability` says when it
/// is not, and why, in a sentence the inspector can show.
public struct OnDeviceModel: TuningModel {

    public init() {}

    /// Whether the model can answer here, and the sentence to show when it cannot.
    public static var availability: TuningAvailability {
        #if canImport(FoundationModels)
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return .unavailable(reason: "This Mac cannot run the on-device model.")
            case .appleIntelligenceNotEnabled:
                return .unavailable(reason: "Apple Intelligence is off. Turn it on in System Settings to describe a look.")
            case .modelNotReady:
                return .unavailable(reason: "The on-device model is still downloading. Try again in a few minutes.")
            @unknown default:
                return .unavailable(reason: "The on-device model is not available right now.")
            }
        }
        #else
        return .unavailable(reason: "This platform has no on-device language model.")
        #endif
    }

    public func propose(_ request: TuningRequest) async throws -> TuningReply {
        #if canImport(FoundationModels)
        guard case .available = Self.availability else {
            if case .unavailable(let reason) = Self.availability { throw TuningError.unavailable(reason) }
            throw TuningError.unavailable("The on-device model is not available right now.")
        }
        do {
            return try await answer(request, guided: true)
        } catch let error as TuningError {
            throw error
        } catch {
            // A range guide the installed model does not support fails the whole
            // ask; the ranges are in the prompt's words too, and every value is
            // clamped on the way in, so ask again with the plain types.
            if String(reflecting: error).contains("UnsupportedGuide") {
                do { return try await answer(request, guided: false) } catch { throw Self.translate(error) }
            }
            throw Self.translate(error)
        }
        #else
        throw TuningError.unavailable("This platform has no on-device language model.")
        #endif
    }

    #if canImport(FoundationModels)

    private func answer(_ request: TuningRequest, guided: Bool) async throws -> TuningReply {
        let schema = try Self.schema(for: request, guided: guided)
        let session = LanguageModelSession(instructions: TuningRequest.instructions)
        // The lowest temperature: the same words over the same panel should
        // move the same parameters the same way.
        let options = GenerationOptions(temperature: 0)
        let response = try await session.respond(to: request.promptText, schema: schema, options: options)
        return Self.reply(from: response.rawContent)
    }

    /// The schema the model answers under: one optional property per parameter,
    /// typed by its kind. `guided` adds the numeric range guides; without them
    /// the range is in the description only.
    package static func schema(for request: TuningRequest, guided: Bool = true) throws -> GenerationSchema {
        let properties = request.parameters.map { parameter -> DynamicGenerationSchema.Property in
            let schema: DynamicGenerationSchema
            switch parameter.kind {
            case .number(let range, _):
                schema = DynamicGenerationSchema(type: Double.self, guides: guided ? [.range(range)] : [])
            case .integer(let range, _):
                schema = DynamicGenerationSchema(type: Int.self, guides: guided ? [.range(range)] : [])
            case .bool:
                schema = DynamicGenerationSchema(type: Bool.self)
            case .choice(let options, _):
                schema = DynamicGenerationSchema(name: parameter.name + "Choice", anyOf: options)
            case .color, .text:
                schema = DynamicGenerationSchema(type: String.self)
            }
            let place = parameter.group.map { " (\($0))" } ?? ""
            return DynamicGenerationSchema.Property(name: parameter.name,
                                                    description: "\(parameter.label)\(place): \(parameter.description)",
                                                    schema: schema, isOptional: true)
        }
        let root = DynamicGenerationSchema(
            name: "ParameterChanges",
            description: "The parameters to change, each with its new value. A parameter the look does not call for is left out entirely.",
            properties: properties)
        return try GenerationSchema(root: root, dependencies: [])
    }

    /// The model's answer as values by name. A property the model left out, or
    /// answered with null, is a parameter it did not move.
    package static func reply(from content: GeneratedContent) -> TuningReply {
        guard case .structure(let properties, let keys) = content.kind else { return [:] }
        var reply: TuningReply = [:]
        for key in keys {
            guard let value = properties[key] else { continue }
            switch value.kind {
            case .number(let number): reply[key] = .number(number)
            case .bool(let flag): reply[key] = .bool(flag)
            case .string(let text): reply[key] = .text(text)
            case .null, .array, .structure: continue
            @unknown default: continue
            }
        }
        return reply
    }

    /// The system's error as the sentence the inspector shows. The cases are
    /// told apart by name rather than by type, since the error type was renamed
    /// between system versions and this code runs on both.
    static func translate(_ error: Error) -> TuningError {
        let name = String(reflecting: error).lowercased()
        if name.contains("contextsizeexceeded") || name.contains("exceededcontextwindow") { return .tooMuchToDescribe }
        if name.contains("guardrail") || name.contains("refusal") { return .refused }
        if name.contains("unsupportedlanguage") { return .unsupportedLanguage }
        return .failed(error.localizedDescription)
    }

    #endif
}
