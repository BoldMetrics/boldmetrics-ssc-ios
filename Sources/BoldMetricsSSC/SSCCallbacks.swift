import Foundation

/// Delegate API. Every method is optional.
public protocol SSCDelegate: AnyObject {
    func sscDidLoad()
    func sscDidRecommend(_ event: SSCSizeEvent)
    func sscDidSelectSize(_ event: SSCSizeEvent)
    func sscDidAddToCart(_ event: SSCSizeEvent)
    func sscDidSelectItem(_ item: SSCSelectedItem)
    func sscDidClose()
    func sscDidFail(_ error: SSCError)
    /// Every decoded message, including types the SDK doesn't know.
    func sscDidReceive(_ event: SSCEvent, message: SSCMessage)
}

public extension SSCDelegate {
    func sscDidLoad() {}
    func sscDidRecommend(_ event: SSCSizeEvent) {}
    func sscDidSelectSize(_ event: SSCSizeEvent) {}
    func sscDidAddToCart(_ event: SSCSizeEvent) {}
    func sscDidSelectItem(_ item: SSCSelectedItem) {}
    func sscDidClose() {}
    func sscDidFail(_ error: SSCError) {}
    func sscDidReceive(_ event: SSCEvent, message: SSCMessage) {}
}

/// Closure API, the alternative to `SSCDelegate`. Used by the SwiftUI wrapper.
public struct SSCCallbacks {
    public var onLoad: (() -> Void)?
    public var onRecommendation: ((SSCSizeEvent) -> Void)?
    public var onSelectSize: ((SSCSizeEvent) -> Void)?
    public var onAddToCart: ((SSCSizeEvent) -> Void)?
    public var onSelectedItem: ((SSCSelectedItem) -> Void)?
    public var onClose: (() -> Void)?
    public var onError: ((SSCError) -> Void)?
    public var onEvent: ((SSCEvent, SSCMessage) -> Void)?

    public init(
        onLoad: (() -> Void)? = nil,
        onRecommendation: ((SSCSizeEvent) -> Void)? = nil,
        onSelectSize: ((SSCSizeEvent) -> Void)? = nil,
        onAddToCart: ((SSCSizeEvent) -> Void)? = nil,
        onSelectedItem: ((SSCSelectedItem) -> Void)? = nil,
        onClose: (() -> Void)? = nil,
        onError: ((SSCError) -> Void)? = nil,
        onEvent: ((SSCEvent, SSCMessage) -> Void)? = nil
    ) {
        self.onLoad = onLoad
        self.onRecommendation = onRecommendation
        self.onSelectSize = onSelectSize
        self.onAddToCart = onAddToCart
        self.onSelectedItem = onSelectedItem
        self.onClose = onClose
        self.onError = onError
        self.onEvent = onEvent
    }
}
