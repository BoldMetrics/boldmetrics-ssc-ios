import Foundation

/// Where the hosted embed page lives.
public enum SSCEnvironment: Equatable, Sendable {
    /// `https://ssc-assets.dev.boldmetrics.io/embed/index.html` (staging vSizer, no telemetry).
    case staging
    /// `https://ssc-assets.prd.boldmetrics.io/embed/index.html`.
    case production
    /// Any other embed page, e.g. a local dev server:
    /// `URL(string: "http://localhost:1337/embed/index.html")!`.
    case custom(URL)

    public var embedURL: URL {
        switch self {
        case .staging: return URL(string: "https://ssc-assets.dev.boldmetrics.io/embed/index.html")!
        case .production: return URL(string: "https://ssc-assets.prd.boldmetrics.io/embed/index.html")!
        case .custom(let url): return url
        }
    }
}

/// Measurement units shown by the widget. Overrides the client's default.
public enum SSCUnits: String, Sendable {
    case metric, imperial
}

/// How the product object reaches the page.
public enum SSCProductDelivery: Sendable {
    /// A `WKUserScript` at document start sets `window._boldmetrics` (default, per the plan for iOS).
    case userScript
    /// The page is opened with `init=bridge`, announces itself with `bmi_embed_boot`,
    /// and the SDK answers with `BoldMetricsEmbed.init({ product, locale })`.
    case bridge
}

/// SDK configuration. Set once with `SSC.configure(_:)`, or pass per presentation.
public struct SSCConfig: Sendable {
    /// Client name passed to get-feed (e.g. `"bmi"`).
    public var client: String
    public var environment: SSCEnvironment
    /// BCP 47 tag such as `en-US`. Supplied to the page with the product object.
    public var locale: String?
    public var units: SSCUnits?
    /// The host's own shopper ID (a UUID). When nil the SDK generates and stores one.
    public var anonId: String?
    public var productDelivery: SSCProductDelivery
    /// Seconds to wait for `bmi_ssc_loaded` before reporting `.timeout`.
    public var loadTimeout: TimeInterval
    /// Makes the web view inspectable in Safari (iOS 16.4+).
    public var debug: Bool

    public init(
        client: String,
        environment: SSCEnvironment = .production,
        locale: String? = nil,
        units: SSCUnits? = nil,
        anonId: String? = nil,
        productDelivery: SSCProductDelivery = .userScript,
        loadTimeout: TimeInterval = 10,
        debug: Bool = false
    ) {
        self.client = client
        self.environment = environment
        self.locale = locale
        self.units = units
        self.anonId = anonId
        self.productDelivery = productDelivery
        self.loadTimeout = loadTimeout
        self.debug = debug
    }
}

/// Global entry point.
public enum SSC {
    /// SDK version sent as `sdk_version`.
    public static let sdkVersion = "0.1.0"
    /// Bridge major this SDK speaks, sent as `bridge`.
    public static let bridgeVersion = 1

    private static let lock = NSLock()
    nonisolated(unsafe) private static var _config: SSCConfig?

    public static func configure(_ config: SSCConfig) {
        lock.lock(); defer { lock.unlock() }
        _config = config
    }

    public static var config: SSCConfig? {
        lock.lock(); defer { lock.unlock() }
        return _config
    }
}
