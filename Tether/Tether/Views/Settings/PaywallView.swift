import StoreKit
import SwiftUI
import TetherKit

struct PaywallView: View {
    @State private var subscriptionManager = SubscriptionManager.shared
    @State private var selectedPlan: PlanChoice = .yearly
    @State private var isPurchasing = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    enum PlanChoice {
        case monthly, yearly
    }

    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "star.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)

                Text("Upgrade to Tether Pro")
                    .font(.title.bold())

                if subscriptionManager.isTrialActive {
                    Text("\(subscriptionManager.trialDaysRemaining) days left in trial")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            // Feature comparison
            VStack(alignment: .leading, spacing: 12) {
                featureRow("Unlimited session history", free: "30 days", pro: "Unlimited")
                featureRow("Friends", free: "3", pro: "Unlimited")
                featureRow("Blocking mode", free: "Soft warn only", pro: "All modes")
                featureRow("AI coaching", free: "Limited", pro: "Full access")
                featureRow("Data export", free: "CSV only", pro: "CSV + JSON")
                featureRow("Priority support", free: nil, pro: "Included")
            }
            .padding()
            .glassCard(cornerRadius: TetherRadius.button)

            // Plan selection
            HStack(spacing: 12) {
                planCard(
                    title: "Monthly",
                    price: subscriptionManager.monthlyProduct?.displayPrice ?? "$8/mo",
                    selected: selectedPlan == .monthly
                ) {
                    selectedPlan = .monthly
                }

                planCard(
                    title: "Yearly",
                    price: subscriptionManager.yearlyProduct?.displayPrice ?? "$60/yr",
                    badge: "Save 37%",
                    selected: selectedPlan == .yearly
                ) {
                    selectedPlan = .yearly
                }
            }

            // Purchase button
            Button {
                Task { await purchase() }
            } label: {
                if isPurchasing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("Subscribe Now")
                }
            }
            .buttonStyle(.borderedProminent)
            .buttonStyle(.tetherPressable)
            .controlSize(.large)
            .disabled(isPurchasing)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            // Restore + terms
            HStack {
                Button("Restore Purchases") {
                    Task { await subscriptionManager.restorePurchases() }
                }
                .font(.caption)

                Text("·").foregroundStyle(.secondary)

                Link("Terms", destination: URL(string: "https://tether.app/terms")!)
                    .font(.caption)

                Text("·").foregroundStyle(.secondary)

                Link("Privacy", destination: URL(string: "https://tether.app/privacy")!)
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
        }
        .padding(32)
        .frame(width: 480)
    }

    private func featureRow(_ feature: String, free: String?, pro: String) -> some View {
        HStack {
            Text(feature)
                .font(.subheadline)
            Spacer()
            if let free {
                Text(free)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 80)
            } else {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 80)
            }
            Text(pro)
                .font(.caption.bold())
                .foregroundStyle(Color.accentColor)
                .frame(width: 80)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(feature): Free \(free ?? "not available"), Pro \(pro)")
    }

    private func planCard(title: String, price: String, badge: String? = nil, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: {
            withAnimation(.tetherQuick) { action() }
        }) {
            VStack(spacing: 4) {
                if let badge {
                    Text(badge)
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.accentColor, in: Capsule())
                }
                Text(title)
                    .font(.headline)
                Text(price)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .glassCard(cornerRadius: TetherRadius.button)
            .overlay(
                RoundedRectangle(cornerRadius: TetherRadius.button, style: .continuous)
                    .stroke(selected ? Color.accentColor : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.tetherPressable)
        .accessibilityLabel("\(title) plan, \(price)")
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint("Select the \(title.lowercased()) subscription plan")
    }

    private func purchase() async {
        isPurchasing = true
        errorMessage = nil
        defer { isPurchasing = false }

        let product: Product?
        switch selectedPlan {
        case .monthly: product = subscriptionManager.monthlyProduct
        case .yearly: product = subscriptionManager.yearlyProduct
        }

        guard let product else {
            errorMessage = "Product not available"
            return
        }

        do {
            let success = try await subscriptionManager.purchase(product)
            if success {
                dismiss()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
