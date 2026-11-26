#if canImport(UIKit) && canImport(WebKit) && canImport(SwiftUI)
import SwiftUI
import UIKit

/// SwiftUI wrapper over `SSCSizeChartViewController`. Usually used through
/// the `.sscSizeChart(isPresented:product:...)` modifier.
public struct SSCSizeChartSheet: UIViewControllerRepresentable {
    let product: SSCProduct
    let config: SSCConfig?
    let callbacks: SSCCallbacks
    let onDismissRequest: () -> Void

    public init(
        product: SSCProduct,
        config: SSCConfig? = nil,
        callbacks: SSCCallbacks,
        onDismissRequest: @escaping () -> Void
    ) {
        self.product = product
        self.config = config
        self.callbacks = callbacks
        self.onDismissRequest = onDismissRequest
    }

    public func makeUIViewController(context: Context) -> SSCSizeChartViewController {
        let vc = SSCSizeChartViewController(product: product, config: config, callbacks: callbacks)
        vc.dismissHandler = onDismissRequest
        return vc
    }

    public func updateUIViewController(_ vc: SSCSizeChartViewController, context: Context) {
        vc.callbacks = callbacks
        vc.dismissHandler = onDismissRequest
    }
}

public extension View {
    /// Presents the size chart as a sheet while `isPresented` is true. A fresh web view is
    /// created for every presentation. `onClose` fires once however the sheet is closed.
    func sscSizeChart(
        isPresented: Binding<Bool>,
        product: SSCProduct,
        config: SSCConfig? = nil,
        callbacks: SSCCallbacks
    ) -> some View {
        sheet(isPresented: isPresented) {
            SSCSizeChartSheet(
                product: product,
                config: config,
                callbacks: callbacks,
                onDismissRequest: { isPresented.wrappedValue = false }
            )
            .ignoresSafeArea()
            .modifier(SSCSheetChrome())
        }
    }
}

private struct SSCSheetChrome: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        } else {
            content
        }
    }
}
#endif
