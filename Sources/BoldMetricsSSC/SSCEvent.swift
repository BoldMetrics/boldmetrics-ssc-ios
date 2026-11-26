import Foundation

/// One bridge message as the page sends it: `{ v, type, ts, payload }`.
public struct SSCMessage: Codable, Equatable, Sendable {
    public let v: Int
    public let type: String
    public let ts: Double
    public let payload: SSCJSON

    public init(v: Int, type: String, ts: Double, payload: SSCJSON) {
        self.v = v
        self.type = type
        self.ts = ts
        self.payload = payload
    }

    /// Decodes the object a `WKScriptMessage` carries (iOS transport posts an object, not a string).
    public init?(body: Any) {
        let json: SSCJSON
        if let string = body as? String, let data = string.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(SSCJSON.self, from: data) {
            json = decoded
        } else {
            json = SSCJSON(any: body)
        }
        guard let type = json["type"]?.stringValue else { return nil }
        self.v = Int(json["v"]?.doubleValue ?? 1)
        self.type = type
        self.ts = json["ts"]?.doubleValue ?? 0
        self.payload = json["payload"] ?? .object([:])
    }
}

/// Payload shared by the widget's size events (`sendEvent` in the web repo).
/// Only the small stable set is typed; everything else is in `raw`.
public struct SSCSizeEvent: Equatable, Sendable {
    /// Size label. On `bmi_add_to_cart` this is the client's mapped label (e.g. `Medium`).
    public let size: String?
    /// The chart's size. Match on this (or the variant ID), not on `size`.
    public let sizeId: String?
    public let fit: SSCJSON?
    /// Recommendation ID. Keep it for purchase attribution.
    public let recId: String?
    /// `bm=<uuid>`.
    public let userId: String?
    /// The raw vSizer response (or `{}`), untyped.
    public let vsizer: SSCJSON?
    /// The whole payload.
    public let raw: SSCJSON

    init(_ payload: SSCJSON) {
        size = payload["size"]?.stringValue
        sizeId = payload["sizeId"]?.stringValue
        fit = payload["fit"]
        recId = payload["recId"]?.stringValue
        userId = payload["userId"]?.stringValue
        vsizer = payload["json"]
        raw = payload
    }
}

/// `bmi_selected_item`: the size picked and the product variant it matched.
public struct SSCSelectedItem: Equatable, Sendable {
    public let parentId: String?
    public let selectedSize: String?
    /// ID of the matched variant when exactly one variant matched.
    public let variantId: String?
    public let matchedToIndividualVariant: Bool
    public let raw: SSCJSON

    init(_ payload: SSCJSON) {
        let item = payload["selectedItem"] ?? .object([:])
        parentId = item["parentId"]?.stringValue
        selectedSize = item["selectedSize"]?.stringValue
        matchedToIndividualVariant = item["matchedToIndividualVariant"]?.boolValue ?? false
        variantId = item["matchingVariants"]?.arrayValue?.first?["id"]?.stringValue
        raw = payload
    }
}

/// Typed bridge events. Unknown types decode as `.unknown`, never fail.
public enum SSCEvent: Equatable, Sendable {
    case embedBoot
    case loaded(SSCSizeEvent)
    case continueClicked(SSCSizeEvent)
    case recommendation(SSCSizeEvent)
    case selectedSize(SSCSizeEvent)
    case formSubmission(SSCSizeEvent)
    case addToCart(SSCSizeEvent)
    case selectedItem(SSCSelectedItem)
    case close
    /// `bmi_ssc_error`: the widget showed its error screen.
    case widgetError(SSCSizeEvent)
    /// `bmi_error`: start-up failure (`missing_params`, `config_failed`, `no_size_chart`, `init_timeout`).
    case embedError(code: String, message: String?)
    case openURL(URL)
    case unknown(type: String, payload: SSCJSON)

    public init(_ message: SSCMessage) {
        let p = message.payload
        switch message.type {
        case "bmi_embed_boot": self = .embedBoot
        case "bmi_ssc_loaded": self = .loaded(SSCSizeEvent(p))
        case "bmi_continue_clicked": self = .continueClicked(SSCSizeEvent(p))
        case "bmi_recommendation_sent": self = .recommendation(SSCSizeEvent(p))
        case "bmi_selected_size": self = .selectedSize(SSCSizeEvent(p))
        case "bmi_form_submission": self = .formSubmission(SSCSizeEvent(p))
        case "bmi_add_to_cart": self = .addToCart(SSCSizeEvent(p))
        case "bmi_selected_item": self = .selectedItem(SSCSelectedItem(p))
        case "bmi_close": self = .close
        case "bmi_ssc_error": self = .widgetError(SSCSizeEvent(p))
        case "bmi_error":
            self = .embedError(code: p["code"]?.stringValue ?? "unknown", message: p["message"]?.stringValue)
        case "bmi_open_url":
            if let s = p["url"]?.stringValue, let url = URL(string: s) { self = .openURL(url) }
            else { self = .unknown(type: message.type, payload: p) }
        default: self = .unknown(type: message.type, payload: p)
        }
    }
}

/// Errors reported through `onError`.
public enum SSCError: Error, Equatable, Sendable {
    /// `bmi_error` from the page.
    case embed(code: String, message: String?)
    /// The page did not load (offline, DNS, HTTP failure). Holds the system description.
    case loadFailed(String)
    /// No `bmi_ssc_loaded` within `SSCConfig.loadTimeout`.
    case timeout
    /// `SSC.configure` was not called and no config was passed.
    case notConfigured
}
