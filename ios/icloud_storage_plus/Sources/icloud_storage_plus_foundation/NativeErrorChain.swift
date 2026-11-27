import Foundation

/// Why the plugin built an error itself instead of passing on Foundation's.
///
/// Plugin-built errors reuse `NSCocoaErrorDomain` codes such as
/// `NSFileReadUnknownError`, so their domain and code alone look exactly like
/// Foundation's own. The raw values are stable names on the Flutter channel.
enum PluginErrorReason: String {
    case invalidUTF8Text
    case invalidUTF8TextInFileWrapper
    case unsupportedDocumentContents
    case documentOpenFailed
    case documentSaveFailed
    case missingSourceURL
    case missingDestinationURL
    case invalidWritePayload
    case dataTierUnsupported
    case inputStreamOpenFailed
    case outputStreamOpenFailed
    case streamReadFailed
    case streamWriteFailed
    case observationWithoutFileURL
    case missingModificationDate
}

enum PluginError {
    static let reasonKey = "ICloudStoragePlusPluginErrorReason"

    static func make(
        _ reason: PluginErrorReason,
        code: Int,
        description: String
    ) -> NSError {
        NSError(
            domain: NSCocoaErrorDomain,
            code: code,
            userInfo: [
                NSLocalizedDescriptionKey: description,
                reasonKey: reason.rawValue,
            ]
        )
    }
}

/// Decodes file bytes as UTF-8 text for the text read APIs.
func decodeUTF8Text(_ data: Data) throws -> String {
    guard let text = String(data: data, encoding: .utf8) else {
        throw PluginError.make(
            .invalidUTF8Text,
            code: NSFileReadUnknownError,
            description: "Unsupported text encoding"
        )
    }
    return text
}

/// The domain and code of `error` and of each error nested under
/// `NSUnderlyingErrorKey`, outermost first, with the plugin reason of any
/// plugin-built link. It carries no descriptions, so no paths or file names.
func nativeErrorChain(_ error: NSError) -> [[String: Any]] {
    // Bounded because nothing stops an error from nesting itself.
    let maxDepth = 8
    var chain: [[String: Any]] = []
    var current: NSError? = error
    while let link = current, chain.count < maxDepth {
        var entry: [String: Any] = ["domain": link.domain, "code": link.code]
        if let reason = link.userInfo[PluginError.reasonKey] as? String {
            entry["pluginReason"] = reason
        }
        chain.append(entry)
        current = link.userInfo[NSUnderlyingErrorKey] as? NSError
    }
    return chain
}
