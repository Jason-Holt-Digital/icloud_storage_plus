import Foundation

/// Why the plugin built an error itself instead of passing on Foundation's.
///
/// These errors reuse `NSCocoaErrorDomain` codes such as
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

/// An `NSCocoaErrorDomain` error the plugin built, marked with its reason.
///
/// The reason is a property rather than a userInfo entry so the error's
/// domain, code, userInfo and description stay exactly what they were before
/// the reason existed.
final class PluginError: NSError, @unchecked Sendable {
    let reason: PluginErrorReason

    private static let reasonCoderKey = "ICloudStoragePlusPluginErrorReason"

    override class var supportsSecureCoding: Bool { true }

    private init(_ reason: PluginErrorReason, code: Int, description: String) {
        self.reason = reason
        super.init(
            domain: NSCocoaErrorDomain,
            code: code,
            userInfo: [NSLocalizedDescriptionKey: description]
        )
    }

    static func make(
        _ reason: PluginErrorReason,
        code: Int,
        description: String
    ) -> PluginError {
        PluginError(reason, code: code, description: description)
    }

    required init?(coder: NSCoder) {
        guard let rawValue = coder.decodeObject(
            of: NSString.self,
            forKey: Self.reasonCoderKey
        ) as String?,
              let reason = PluginErrorReason(rawValue: rawValue)
        else { return nil }
        self.reason = reason
        super.init(coder: coder)
    }

    override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        coder.encode(reason.rawValue as NSString, forKey: Self.reasonCoderKey)
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
/// `NSUnderlyingErrorKey`, outermost first, with the reason of any
/// `PluginError` link. It carries no descriptions, so no paths or file names.
/// It stops after `nativeErrorChainMaxDepth` links.
func nativeErrorChain(_ error: NSError) -> [[String: Any]] {
    var chain: [[String: Any]] = []
    var current: NSError? = error
    while let link = current, chain.count < nativeErrorChainMaxDepth {
        var entry: [String: Any] = ["domain": link.domain, "code": link.code]
        if let pluginError = link as? PluginError {
            entry["pluginReason"] = pluginError.reason.rawValue
        }
        chain.append(entry)
        current = link.userInfo[NSUnderlyingErrorKey] as? NSError
    }
    return chain
}

/// Bounded because nothing stops an error from nesting itself.
let nativeErrorChainMaxDepth = 8
