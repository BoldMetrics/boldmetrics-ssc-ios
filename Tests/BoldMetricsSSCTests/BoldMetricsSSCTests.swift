import XCTest
@testable import BoldMetricsSSC

private func fixture(_ name: String) throws -> Data {
    let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

private func query(_ url: URL) -> [String: String] {
    let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
}

final class EmbedURLTests: XCTestCase {
    let anon = "3f2b8c1e-7a4d-4e9b-9c55-0d6a1b2c3d4e"

    func testRequiredParams() {
        let url = SSCEmbedURL.build(config: SSCConfig(client: "bmi"), productId: "Mens Nano Vest", anonId: anon)
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "ssc-assets.prd.boldmetrics.io")
        XCTAssertEqual(url.path, "/embed/index.html")
        XCTAssertEqual(query(url), [
            "client": "bmi",
            "product_id": "Mens Nano Vest",
            "anon_id": anon,
            "platform": "ios",
            "sdk_version": SSC.sdkVersion,
            "bridge": "1",
        ])
    }

    func testEnvironments() {
        let staging = SSCEmbedURL.build(config: SSCConfig(client: "bmi", environment: .staging), productId: "p", anonId: anon)
        XCTAssertEqual(staging.host, "ssc-assets.dev.boldmetrics.io")
        let local = SSCEmbedURL.build(
            config: SSCConfig(client: "bmi", environment: .custom(URL(string: "http://localhost:1337/embed/index.html")!)),
            productId: "p", anonId: anon)
        XCTAssertTrue(local.absoluteString.hasPrefix("http://localhost:1337/embed/index.html?client=bmi&"))
    }

    func testEveryValueIsPercentEncodedIncludingPlus() {
        let url = SSCEmbedURL.build(config: SSCConfig(client: "a&b"), productId: "Tee+Shirt / 50% #1", anonId: anon)
        XCTAssertTrue(url.absoluteString.contains("client=a%26b"))
        XCTAssertTrue(url.absoluteString.contains("product_id=Tee%2BShirt%20%2F%2050%25%20%231"))
        XCTAssertEqual(query(url)["product_id"], "Tee+Shirt / 50% #1")
    }

    func testLocaleUnitsAndBridgeInit() {
        let config = SSCConfig(client: "bmi", locale: "fr-CA", units: .metric, productDelivery: .bridge)
        let q = query(SSCEmbedURL.build(config: config, productId: "p", anonId: anon))
        XCTAssertEqual(q["lang"], "fr")
        XCTAssertEqual(q["locale"], "ca")
        XCTAssertEqual(q["units"], "metric")
        XCTAssertEqual(q["init"], "bridge")
    }

    func testLanguageOnlyLocale() {
        let q = query(SSCEmbedURL.build(config: SSCConfig(client: "bmi", locale: "de"), productId: "p", anonId: anon))
        XCTAssertEqual(q["lang"], "de")
        XCTAssertNil(q["locale"])
        XCTAssertNil(q["init"])
    }
}

final class AnonIDTests: XCTestCase {
    var defaults: UserDefaults!

    override func setUp() {
        defaults = UserDefaults(suiteName: "SSCAnonIDTests")!
        defaults.removePersistentDomain(forName: "SSCAnonIDTests")
    }

    func testGeneratesLowercaseUUIDOnceAndPersists() {
        let first = SSCAnonID.resolve(defaults: defaults)
        XCTAssertNotNil(UUID(uuidString: first))
        XCTAssertEqual(first, first.lowercased())
        XCTAssertEqual(defaults.string(forKey: SSCAnonID.defaultsKey), first)
        XCTAssertEqual(SSCAnonID.resolve(defaults: defaults), first)
    }

    func testHostIdWinsAndIsLowercased() {
        let stored = SSCAnonID.resolve(defaults: defaults)
        let host = "3F2B8C1E-7A4D-4E9B-9C55-0D6A1B2C3D4E"
        XCTAssertEqual(SSCAnonID.resolve(hostId: host, defaults: defaults), host.lowercased())
        XCTAssertEqual(SSCAnonID.resolve(defaults: defaults), stored, "host ID must not overwrite the stored one")
    }

    func testMalformedHostIdFallsBackToStored() {
        let stored = SSCAnonID.resolve(defaults: defaults)
        XCTAssertEqual(SSCAnonID.resolve(hostId: "not-a-uuid", defaults: defaults), stored)
    }

    func testCorruptStoredValueIsReplacedAndReset() {
        defaults.set("garbage", forKey: SSCAnonID.defaultsKey)
        let id = SSCAnonID.resolve(defaults: defaults)
        XCTAssertNotNil(UUID(uuidString: id))
        SSCAnonID.reset(defaults: defaults)
        XCTAssertNotEqual(SSCAnonID.resolve(defaults: defaults), id)
    }
}

final class ProductTests: XCTestCase {
    func testFixtureProductsRoundTrip() throws {
        struct Injected: Decodable { let locale: String; let product: SSCProduct }
        for slug in ["mens-nano-vest", "womens-nano-vest", "kids-test-product"] {
            let injected = try JSONDecoder().decode(Injected.self, from: fixture("product.\(slug)"))
            XCTAssertFalse(injected.product.variants.isEmpty, slug)
            let json = try SSCInjectedObject(product: injected.product, locale: injected.locale).jsonString()
            let back = try JSONDecoder().decode(Injected.self, from: Data(json.utf8))
            XCTAssertEqual(back.product, injected.product, slug)
            XCTAssertEqual(back.locale, "en-US")
        }
    }

    func testInjectedJSONEscapesLineSeparators() throws {
        let json = try SSCInjectedObject(product: SSCProduct(id: "a\u{2028}b"), locale: nil).jsonString()
        XCTAssertFalse(json.contains("\u{2028}"))
        XCTAssertTrue(json.contains("\\u2028"))
    }
}

final class BridgeFixtureTests: XCTestCase {
    func messages(_ slug: String) throws -> [SSCMessage] {
        try JSONDecoder().decode([SSCMessage].self, from: fixture("bridge.\(slug)"))
    }

    func typeName(_ e: SSCEvent) -> String {
        switch e {
        case .embedBoot: return "boot"
        case .loaded: return "loaded"
        case .continueClicked: return "continue"
        case .recommendation: return "recommendation"
        case .selectedSize: return "selectedSize"
        case .formSubmission: return "form"
        case .addToCart: return "addToCart"
        case .selectedItem: return "selectedItem"
        case .close: return "close"
        case .widgetError: return "widgetError"
        case .embedError: return "embedError"
        case .openURL: return "openURL"
        case .unknown(let t, _): return "unknown:\(t)"
        }
    }

    func testMensNanoVest() throws {
        let msgs = try messages("mens-nano-vest")
        let events = msgs.map(SSCEvent.init)
        XCTAssertEqual(events.map(typeName), [
            "boot", "loaded", "recommendation", "selectedSize", "selectedSize", "selectedSize",
            "addToCart", "selectedSize", "selectedItem", "close",
        ])
        XCTAssertTrue(msgs.allSatisfy { $0.v == 1 && $0.ts > 0 })

        guard case .recommendation(let rec) = events[2] else { return XCTFail() }
        XCTAssertEqual(rec.sizeId, "M")
        XCTAssertNotNil(rec.recId)
        XCTAssertEqual(rec.userId, "bm=3f2b8c1e-7a4d-4e9b-9c55-0d6a1b2c3d4e")
        XCTAssertEqual(rec.fit, .bool(false))
        XCTAssertEqual(rec.vsizer?["code"], .number(200))

        guard case .addToCart(let cart) = events[6] else { return XCTFail() }
        XCTAssertEqual(cart.size, "Medium", "add to cart carries the mapped label")
        XCTAssertEqual(cart.sizeId, "M")
        XCTAssertEqual(cart.recId, rec.recId)

        guard case .selectedItem(let item) = events[8] else { return XCTFail() }
        XCTAssertEqual(item.parentId, "Mens Nano Vest")
        XCTAssertEqual(item.variantId, "mens-nano-vest-04")
        XCTAssertTrue(item.matchedToIndividualVariant)
    }

    func testWomensNanoVest() throws {
        let events = try messages("womens-nano-vest").map(SSCEvent.init)
        XCTAssertEqual(events.map(typeName), ["boot", "loaded", "recommendation", "selectedSize", "selectedSize", "close"])
    }

    func testKidsProductWithPipesAndOpenURL() throws {
        let events = try messages("kids-test-product").map(SSCEvent.init)
        XCTAssertEqual(events.map(typeName), [
            "loaded", "recommendation", "selectedSize", "openURL", "selectedSize",
            "selectedSize", "addToCart", "selectedSize", "selectedItem", "close",
        ])
        guard case .recommendation(let rec) = events[1] else { return XCTFail() }
        XCTAssertEqual(rec.sizeId, "Big Girls (7-16) | REGULAR | XL(16/18)")
        guard case .openURL(let url) = events[3] else { return XCTFail() }
        XCTAssertEqual(url.absoluteString, "https://boldmetrics.com/")
    }

    func testEveryFixtureDecodesFromWebKitStyleObjects() throws {
        // WKScriptMessage.body gives Foundation objects, not JSON text.
        for slug in ["mens-nano-vest", "womens-nano-vest", "kids-test-product"] {
            let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: fixture("bridge.\(slug)")) as? [Any])
            let fromCodable = try messages(slug)
            let fromBody = raw.compactMap { SSCMessage(body: $0) }
            XCTAssertEqual(fromBody.map(\.type), fromCodable.map(\.type), slug)
            XCTAssertEqual(fromBody.map { SSCEvent($0) }, fromCodable.map { SSCEvent($0) }, slug)
        }
    }

    func testUnknownTypesAndFieldsAreTolerated() {
        let body: [String: Any] = ["v": 1, "type": "bmi_from_the_future", "ts": 1, "payload": ["x": 1]]
        let msg = SSCMessage(body: body)!
        XCTAssertEqual(SSCEvent(msg), .unknown(type: "bmi_from_the_future", payload: .object(["x": .number(1)])))

        let extra: [String: Any] = ["v": 1, "type": "bmi_selected_size", "ts": 1,
                                    "payload": ["sizeId": "M", "brandNew": ["a": true]]]
        guard case .selectedSize(let e) = SSCEvent(SSCMessage(body: extra)!) else { return XCTFail() }
        XCTAssertEqual(e.sizeId, "M")
        XCTAssertNil(e.recId)

        XCTAssertNil(SSCMessage(body: ["payload": [:]]), "no type → ignored")
        XCTAssertNil(SSCMessage(body: 42))
    }

    func testWidgetError() {
        // No recording has bmi_ssc_error since the returning-shopper fix; shape from the older recording.
        let body: [String: Any] = ["v": 1, "type": "bmi_ssc_error", "ts": 1,
                                   "payload": ["fit": false, "userId": "bm=x", "json": [:]]]
        guard case .widgetError(let e) = SSCEvent(SSCMessage(body: body)!) else { return XCTFail() }
        XCTAssertEqual(e.userId, "bm=x")
        XCTAssertEqual(e.vsizer, .object([:]))
    }

    func testEmbedError() {
        let body: [String: Any] = ["v": 1, "type": "bmi_error", "ts": 1,
                                   "payload": ["code": "init_timeout", "message": "late"]]
        XCTAssertEqual(SSCEvent(SSCMessage(body: body)!), .embedError(code: "init_timeout", message: "late"))
    }

    func testBoolAndNumberAreDistinguishedInWebKitBodies() {
        XCTAssertEqual(SSCJSON(any: NSNumber(value: true)), .bool(true))
        XCTAssertEqual(SSCJSON(any: NSNumber(value: 1)), .number(1))
    }
}
