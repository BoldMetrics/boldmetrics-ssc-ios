# Bold Metrics Smart Size Chart — iOS SDK

Swift Package that embeds the Bold Metrics Smart Size Chart (SSC) in native iOS apps.

The SDK opens the hosted SSC embed page in a `WKWebView` sheet, hands it your product object, and turns the page's bridge messages into native callbacks. It contains no sizing logic and no client-specific code: the client name is runtime config.

> **Status:** pre-release (`0.1.0`). The hosted embed page is not deployed yet, so today the example runs against a locally served embed page (see [Running the example](#running-the-example-against-the-local-embed)).

Requirements: iOS 15+, Swift 5.9+ (Xcode 15+).

## Installation

Swift Package Manager, in Xcode (**File › Add Package Dependencies…**) or in `Package.swift`:

```swift
.package(url: "https://github.com/BoldMetrics/boldmetrics-ssc-ios.git", from: "0.1.0")
```

Add the `BoldMetricsSSC` product to your app target. The package ships a privacy manifest (`PrivacyInfo.xcprivacy`).

## Quick start

### 1. Configure once (e.g. at app launch)

```swift
import BoldMetricsSSC

SSC.configure(SSCConfig(
    client: "bmi",                 // your Bold Metrics client name
    environment: .production,      // .staging, or .custom(URL) for a local page
    locale: "en-US"                // optional, BCP 47
))
```

### 2. Describe the product

Same shape as the `window._boldmetrics.product` object your website sets:

```swift
let product = SSCProduct(
    id: "Mens Nano Vest",
    sizechart: "mens_nano_vest",
    title: "Nano Vest",
    type: "BMI MENS > Vests",
    price: 129,
    variants: [
        .init(id: "mens-nano-vest-04", size: "M", fit: "Regular", available: true),
        .init(id: "mens-nano-vest-05", size: "L", fit: "Regular", available: true),
    ]
)
```

### 3a. SwiftUI

```swift
struct ProductView: View {
    @State private var showSizeChart = false
    @State private var size: String?

    var body: some View {
        Button("Find my size") { showSizeChart = true }
            .sscSizeChart(isPresented: $showSizeChart, product: product, callbacks: SSCCallbacks(
                onRecommendation: { size = $0.sizeId },
                onSelectSize: { size = $0.sizeId },
                onAddToCart: { event in cart.add(product.id, size: event.sizeId) },
                onClose: { print("closed") },
                onError: { print("size chart error: \($0)") }
            ))
    }
}
```

### 3b. UIKit

```swift
let sizeChart = SSCSizeChartViewController(product: product, callbacks: SSCCallbacks(
    onSelectSize: { [weak self] in self?.select($0.sizeId) },
    onAddToCart: { [weak self] in self?.addToCart(sizeId: $0.sizeId) }
))
sizeChart.present(from: self)
```

Or set `delegate` to an `SSCDelegate` (every method is optional). Create a new controller for every presentation: after a close the page is blank.

## Events

| Callback | Bridge message | Notes |
| --- | --- | --- |
| `onLoad` | `bmi_ssc_loaded` | Widget is ready; the loading spinner is hidden. |
| `onRecommendation` | `bmi_recommendation_sent` | `sizeId`, `recId`. |
| `onSelectSize` | `bmi_selected_size` | Best match set, or the shopper tapped a size. |
| `onAddToCart` | `bmi_add_to_cart` | Add the item to **your** cart. `size` is the client's display label (e.g. `Medium`); match on `sizeId`. |
| `onSelectedItem` | `bmi_selected_item` | `variantId` of the matched product variant. |
| `onClose` | `bmi_close` or native dismissal | Fires exactly once per presentation, however the sheet closed. |
| `onError` | `bmi_error`, load failure, timeout | `SSCError.embed(code:message:)` (`missing_params`, `config_failed`, `no_size_chart`, `init_timeout`), `.loadFailed`, `.timeout` (no `bmi_ssc_loaded` within `loadTimeout`, default 10 s), `.notConfigured`. |
| `onEvent` | every message | Typed `SSCEvent` plus the raw `SSCMessage`. Unknown types arrive as `.unknown`. |

Size events (`SSCSizeEvent`) type only the stable fields: `size`, `sizeId`, `fit`, `recId`, `userId`. The raw vSizer response is `vsizer` and the whole payload is `raw`, both untyped (`SSCJSON`). Keep `recId` if you want to attribute purchases later.

`bmi_open_url` and links in the page open in the system browser; the web view never leaves the embed origin.

### Inbound calls

```swift
sizeChart.setProduct(otherProduct) // re-runs the widget with another product
sizeChart.close()                  // same as the page's X
```

## Configuration reference

| `SSCConfig` field | Default | |
| --- | --- | --- |
| `client` | — | Required. |
| `environment` | `.production` | `.staging` (`ssc-assets.dev…`), `.production` (`ssc-assets.prd…`), or `.custom(URL)`. |
| `locale` | nil | BCP 47 tag. Sent with the product object and as `lang` / `locale` URL params. |
| `units` | nil | `.metric` / `.imperial`; overrides the client default. |
| `anonId` | nil | Your own shopper UUID. When nil the SDK generates one and keeps it in `UserDefaults` (not the Keychain, so it does not survive an uninstall). `SSCAnonID.reset()` forgets it. |
| `productDelivery` | `.userScript` | `.userScript` sets `window._boldmetrics` with a document-start `WKUserScript`. `.bridge` opens the page with `init=bridge` and answers `bmi_embed_boot` with `BoldMetricsEmbed.init(…)`. |
| `loadTimeout` | 10 | Seconds to wait for `bmi_ssc_loaded`. |
| `debug` | false | Makes the web view inspectable in Safari (iOS 16.4+). |

The SDK adds `platform=ios`, `sdk_version` and `bridge=1` to the embed URL.

## Running the example against the local embed

`Example/` is a one-screen store (product page, size picker, cart badge, "Find my size", product switcher, a debug drawer with settings and the bridge event log). It depends on this package by local path, uses client `bmi`, and bundles three `bmi` fixture products.

1. Serve the SSC embed page on port 1337. Until the hosted page is deployed this needs a local build of the page, which is available to Bold Metrics developers only. Check that `http://localhost:1337/embed/index.html?client=bmi&product_id=Mens%20Nano%20Vest` loads in a browser.

2. Open `Example/BoldMetricsSSCExample.xcodeproj`, pick an iOS Simulator and run. The simulator reaches the Mac's `localhost` directly. The default environment is **Local (localhost:1337)**; switch to staging or production in the debug drawer (🐞) once the embed is deployed.

Only the example app allows plain HTTP, and only to local hosts (`NSAllowsLocalNetworking` in `Example/Info.plist`). The SDK needs no ATS exception.

UI tests (`BoldMetricsSSCExampleUITests`) drive the whole flow against the local server: form → recommendation → add to cart → close, swipe-dismiss (one `onClose`), and the UIKit + `init=bridge` path:

```bash
xcodebuild test -project Example/BoldMetricsSSCExample.xcodeproj -scheme BoldMetricsSSCExample -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -skip-testing:BoldMetricsSSCExampleUITests/SizeChartFlowUITests/testExplore
```

## Development

```bash
swift test
```

```bash
xcodebuild test -scheme BoldMetricsSSC -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

`swift test` runs on macOS (the UIKit parts are compiled only for iOS). `Tests/BoldMetricsSSCTests/Fixtures/` holds recorded bridge message sequences (`bridge.*.json`) and product objects (`product.*.json`) from the embed page; refresh them when the page's bridge recordings change.

## Troubleshooting

- **Inspect the page:** set `debug: true`, then in Safari on the Mac open **Develop › Simulator › …** (enable the Develop menu in Safari settings). iOS 16.4+.
- **Blank sheet or `.loadFailed` on localhost:** the dev server is not running, or your app has no ATS exception for local networking.
- **`.embed(code: "no_size_chart")`:** the client config has no chart for that `product_id`; check `sizechart` on the product.
- **`.timeout`:** no `bmi_ssc_loaded` within 10 s (slow network, or the page failed before loading).
- **Recommended size isn't selected in my picker:** match on `sizeId` (or the variant ID from `onSelectedItem`), not on `size`.

## License

MIT, see [LICENSE](LICENSE).
