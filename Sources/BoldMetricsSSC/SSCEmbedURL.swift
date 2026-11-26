import Foundation

/// Builds the embed page URL (plan: "Reference: embed contract").
public enum SSCEmbedURL {
    // RFC 3986 unreserved characters. Everything else is percent-encoded, `+` included:
    // the page reads params with URLSearchParams, which turns a bare `+` into a space.
    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    public static func build(config: SSCConfig, productId: String, anonId: String) -> URL {
        var items: [(String, String)] = [
            ("client", config.client),
            ("product_id", productId),
            ("anon_id", anonId),
        ]
        if let tag = config.locale, let parts = localeParts(tag) {
            items.append(("lang", parts.language))
            if let region = parts.region { items.append(("locale", region)) }
        }
        if let units = config.units { items.append(("units", units.rawValue)) }
        items.append(("platform", "ios"))
        items.append(("sdk_version", SSC.sdkVersion))
        items.append(("bridge", String(SSC.bridgeVersion)))
        if config.productDelivery == .bridge { items.append(("init", "bridge")) }

        let query = items.map { "\(encode($0.0))=\(encode($0.1))" }.joined(separator: "&")
        var components = URLComponents(url: config.environment.embedURL, resolvingAgainstBaseURL: false)!
        let existing = components.percentEncodedQuery.map { $0.isEmpty ? "" : $0 + "&" } ?? ""
        components.percentEncodedQuery = existing + query
        return components.url!
    }

    static func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
    }

    /// `en-US` → (`en`, `us`); `fr` → (`fr`, nil). The page wants a bare region for `locale`.
    static func localeParts(_ tag: String) -> (language: String, region: String?)? {
        let pieces = tag.replacingOccurrences(of: "_", with: "-").split(separator: "-")
        guard let first = pieces.first, first.count >= 2 else { return nil }
        let region = pieces.dropFirst().first { $0.count == 2 && $0.allSatisfy(\.isLetter) }
        return (first.lowercased(), region.map { $0.lowercased() })
    }
}
