import Foundation

/// The product object, same shape a retailer sets as `window._boldmetrics.product` on the web.
public struct SSCProduct: Codable, Equatable, Sendable {
    public struct Variant: Codable, Equatable, Sendable {
        public var id: String
        public var size: String
        public var fit: String?
        public var available: Bool

        public init(id: String, size: String, fit: String? = nil, available: Bool = true) {
            self.id = id
            self.size = size
            self.fit = fit
            self.available = available
        }
    }

    public var id: String
    public var sizechart: String?
    public var title: String?
    public var type: String?
    public var price: Double?
    public var variants: [Variant]

    public init(
        id: String,
        sizechart: String? = nil,
        title: String? = nil,
        type: String? = nil,
        price: Double? = nil,
        variants: [Variant] = []
    ) {
        self.id = id
        self.sizechart = sizechart
        self.title = title
        self.type = type
        self.price = price
        self.variants = variants
    }
}

/// `window._boldmetrics` / the `init()` payload: `{ product, locale }`.
struct SSCInjectedObject: Encodable {
    let product: SSCProduct
    let locale: String?

    func jsonString() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(self)
        // U+2028/2029 are valid JSON but end a line in older JS parsers.
        return String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
    }
}
