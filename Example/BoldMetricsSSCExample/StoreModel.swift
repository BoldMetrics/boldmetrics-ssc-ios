import BoldMetricsSSC
import Foundation

/// One fixture product (`Fixtures/product.<slug>.json`).
struct FixtureProduct: Identifiable, Decodable {
    let locale: String
    let product: SSCProduct
    var id: String { product.id }

    static func loadAll() -> [FixtureProduct] {
        ["mens-nano-vest", "womens-nano-vest", "kids-test-product"].compactMap { slug in
            guard let url = Bundle.main.url(forResource: "product.\(slug)", withExtension: "json"),
                  let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(FixtureProduct.self, from: data)
        }
    }
}

enum EnvironmentChoice: String, CaseIterable, Identifiable {
    case local = "Local (localhost:1337)"
    case staging = "Staging"
    case production = "Production"
    var id: String { rawValue }

    var environment: SSCEnvironment {
        switch self {
        case .local: return .custom(URL(string: "http://localhost:1337/embed/index.html")!)
        case .staging: return .staging
        case .production: return .production
        }
    }
}

struct LogEntry: Identifiable {
    let id = UUID()
    let time = Date()
    let text: String
}

final class StoreModel: ObservableObject {
    let products = FixtureProduct.loadAll()
    @Published var productIndex = 0 { didSet { selectedSize = nil } }
    @Published var selectedSize: String?
    @Published var recommendedSize: String?
    @Published var cartCount = 0
    @Published var log: [LogEntry] = []

    // Debug drawer settings.
    @Published var environment: EnvironmentChoice = .local
    @Published var client = "bmi"
    @Published var locale = "en-US"
    @Published var useBridgeInit = false
    @Published var useUIKit = false

    init() {
        // Launch arguments (used by the UI tests), e.g. `-useUIKit YES -productIndex 2`.
        let args = UserDefaults.standard
        useUIKit = args.bool(forKey: "useUIKit")
        useBridgeInit = args.bool(forKey: "useBridgeInit")
        productIndex = args.integer(forKey: "productIndex")
    }

    var fixture: FixtureProduct? { products.indices.contains(productIndex) ? products[productIndex] : nil }

    var config: SSCConfig {
        SSCConfig(
            client: client,
            environment: environment.environment,
            locale: locale.isEmpty ? nil : locale,
            productDelivery: useBridgeInit ? .bridge : .userScript,
            debug: true
        )
    }

    func addLog(_ text: String) {
        log.insert(LogEntry(text: text), at: 0)
        print("[SSC] \(text)")
    }

    /// Callbacks drive the page the way a real integration would.
    var callbacks: SSCCallbacks {
        SSCCallbacks(
            onRecommendation: { [weak self] e in
                self?.recommendedSize = e.sizeId
                self?.select(e.sizeId)
            },
            onSelectSize: { [weak self] e in self?.select(e.sizeId) },
            onAddToCart: { [weak self] e in
                self?.select(e.sizeId)
                self?.cartCount += 1
            },
            onSelectedItem: { [weak self] item in
                self?.addLog("  ↳ matched variant \(item.variantId ?? "none")")
            },
            onClose: { [weak self] in self?.addLog("onClose") },
            onError: { [weak self] error in self?.addLog("onError \(error)") },
            onEvent: { [weak self] event, message in
                self?.addLog(Self.describe(event, message))
            }
        )
    }

    /// Selects a size only when it is one of the product's variants (matched on `sizeId`).
    func select(_ sizeId: String?) {
        guard let sizeId, fixture?.product.variants.contains(where: { $0.size == sizeId }) == true else { return }
        selectedSize = sizeId
    }

    func addToCart() {
        guard selectedSize != nil else { return }
        cartCount += 1
        addLog("Added \(selectedSize ?? "") from the product page")
    }

    static func describe(_ event: SSCEvent, _ message: SSCMessage) -> String {
        var parts = [message.type]
        switch event {
        case .recommendation(let e), .selectedSize(let e), .addToCart(let e):
            parts.append("sizeId=\(e.sizeId ?? "-")")
            if e.size != e.sizeId { parts.append("size=\(e.size ?? "-")") }
            if let rec = e.recId { parts.append("recId=\(rec.prefix(8))…") }
        case .selectedItem(let item):
            parts.append("variant=\(item.variantId ?? "-")")
        case .embedError(let code, _):
            parts.append("code=\(code)")
        case .openURL(let url):
            parts.append(url.absoluteString)
        default:
            break
        }
        return parts.joined(separator: " ")
    }
}
