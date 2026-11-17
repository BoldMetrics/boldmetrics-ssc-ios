# Bold Metrics Smart Size Chart — iOS SDK

Swift Package that embeds the Bold Metrics Smart Size Chart (SSC) in native iOS apps.

> **Status:** pre-release. The package scaffold and CI land in SMA-678.

## Installation (planned)

Swift Package Manager:

```swift
.package(url: "https://github.com/BoldMetrics/boldmetrics-ssc-ios.git", from: "1.0.0")
```

Product: `BoldMetricsSSC`. Minimum iOS version: 15.

## How it works

The SDK hosts the SSC page in embed mode and talks to it over a message bridge. The host app passes the same product object a web integration uses (product ID, size chart name, and variants with size, fit and availability). Client-specific behaviour comes from config, never from a custom SDK build.
