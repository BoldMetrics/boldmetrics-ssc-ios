import BoldMetricsSSC
import SwiftUI
import UIKit

@main
struct StoreApp: App {
    @StateObject private var model = StoreModel()

    var body: some Scene {
        WindowGroup {
            NavigationView { ProductPage() }
                .navigationViewStyle(.stack)
                .environmentObject(model)
        }
    }
}

struct ProductPage: View {
    @EnvironmentObject var model: StoreModel
    @State private var showSizeChart = false
    @State private var showDrawer = false

    var body: some View {
        ScrollView {
            if let fixture = model.fixture {
                content(fixture.product)
            } else {
                Text("No fixture products in the bundle.").padding()
            }
        }
        .navigationTitle("SSC Store")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Menu {
                    ForEach(Array(model.products.enumerated()), id: \.offset) { index, item in
                        Button(item.product.id) { model.productIndex = index }
                    }
                } label: { Label("Product", systemImage: "list.bullet") }
                .accessibilityIdentifier("productSwitcher")
            }
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button { showDrawer = true } label: { Image(systemName: "ladybug") }
                    .accessibilityIdentifier("debugDrawer")
                HStack(spacing: 2) {
                    Image(systemName: "cart")
                    if model.cartCount > 0 {
                        Text("\(model.cartCount)")
                            .font(.caption.bold()).foregroundColor(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Color.red))
                    }
                }
                .accessibilityIdentifier("cartBadge")
                .accessibilityValue("\(model.cartCount)")
            }
        }
        .sscSizeChart(
            isPresented: $showSizeChart,
            product: model.fixture?.product ?? SSCProduct(id: ""),
            config: model.config,
            callbacks: model.callbacks
        )
        .sheet(isPresented: $showDrawer) { DebugDrawer().environmentObject(model) }
    }

    @ViewBuilder
    private func content(_ product: SSCProduct) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
                .frame(height: 220)
                .overlay(Image(systemName: "tshirt").font(.system(size: 72)).foregroundColor(.secondary))

            VStack(alignment: .leading, spacing: 4) {
                Text(product.title ?? product.id).font(.title2.bold())
                Text(product.id).font(.subheadline).foregroundColor(.secondary)
                if let price = product.price {
                    Text(price, format: .currency(code: "USD")).font(.title3)
                }
            }

            sizePicker(product)

            Button {
                if model.useUIKit { presentWithUIKit() } else { showSizeChart = true }
                model.addLog("Find my size (\(model.useUIKit ? "UIKit" : "SwiftUI"))")
            } label: {
                Label("Find my size", systemImage: "ruler").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("findMySize")

            Button {
                model.addToCart()
            } label: {
                Text(model.selectedSize == nil ? "Select a size" : "Add to cart – \(model.selectedSize!)")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.selectedSize == nil)

            EventLog(entries: model.log)
        }
        .padding()
    }

    private func sizePicker(_ product: SSCProduct) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Size").font(.headline)
                if let rec = model.recommendedSize {
                    Text("Recommended: \(rec)").font(.caption).foregroundColor(.green)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(product.variants, id: \.id) { variant in
                        let selected = model.selectedSize == variant.size
                        Button { model.selectedSize = variant.size } label: {
                            Text(variant.size)
                                .strikethrough(!variant.available)
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(RoundedRectangle(cornerRadius: 8)
                                    .stroke(selected ? Color.accentColor : Color.secondary, lineWidth: selected ? 2 : 1))
                        }
                        .disabled(!variant.available)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
            }
        }
    }

    /// The UIKit integration style, same SDK core.
    private func presentWithUIKit() {
        guard let product = model.fixture?.product,
              let root = UIApplication.shared.connectedScenes
                .compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController }).first
        else { return }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        SSCSizeChartViewController(product: product, config: model.config, callbacks: model.callbacks)
            .present(from: top)
    }
}

struct EventLog: View {
    let entries: [LogEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Bridge events (\(entries.count))").font(.headline)
            if entries.isEmpty {
                Text("Nothing yet. Tap “Find my size”.").font(.caption).foregroundColor(.secondary)
            }
            ForEach(entries) { entry in
                Text(entry.text).font(.system(.caption, design: .monospaced))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(.secondarySystemBackground)))
        .accessibilityIdentifier("eventLog")
    }
}

struct DebugDrawer: View {
    @EnvironmentObject var model: StoreModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section("Settings") {
                    Picker("Environment", selection: $model.environment) {
                        ForEach(EnvironmentChoice.allCases) { Text($0.rawValue).tag($0) }
                    }
                    TextField("Client", text: $model.client).autocapitalization(.none)
                    TextField("Locale (BCP 47)", text: $model.locale).autocapitalization(.none)
                    Toggle("Deliver product with init=bridge", isOn: $model.useBridgeInit)
                    Toggle("Present with UIKit", isOn: $model.useUIKit)
                }
                Section("Shopper") {
                    Text("anon_id \(SSCAnonID.resolve())").font(.caption.monospaced())
                    Button("Reset anon_id") { SSCAnonID.reset() }
                }
                Section("Callback log") {
                    Button("Clear") { model.log.removeAll() }
                    ForEach(model.log) { Text($0.text).font(.caption.monospaced()) }
                }
            }
            .navigationTitle("Debug")
            .toolbar { Button("Done") { dismiss() } }
        }
    }
}
