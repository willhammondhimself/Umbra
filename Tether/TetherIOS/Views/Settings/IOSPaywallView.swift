import StoreKit
import SwiftUI
import TetherKit

struct IOSPaywallView: View {
    @State private var subscriptionManager = SubscriptionManager.shared
    @State private var selectedPlan: PlanChoice = .yearly
    @State private var isPurchasing = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    enum PlanChoice {
        case monthly, yearly
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "star.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)

                    Text("Tether Pro")
                        .font(.largeTitle.bold())

                    if subscriptionManager.isTrialActive {
                        Text("\(subscriptionManager.trialDaysRemaining) days left in trial")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 20)

                // Features
                VStack(alignment: .leading, spacing: 16) {
                    proFeature("chart.bar.fill", "Unlimited session history")
                    proFeature("person.2.fill", "Unlimited friends")
                    proFeature("shield.fill", "All blocking modes")
                    proFeature("brain.head.profile.fill", "Full AI coaching")
                    proFeature("square.and.arrow.up.fill", "CSV + JSON export")
                }
                .padding()

                // Plan cards
                VStack(spacing: 12) {
                    planButton("Yearly — Save 37%",
                               price: subscriptionManager.yearlyProduct?.displayPrice ?? "$60/yr",
                               selected: selectedPlan == .yearly) {
                        selectedPlan = .yearly
                    }

                    planButton("Monthly",
                               price: subscriptionManager.monthlyProduct?.displayPrice ?? "$8/mo",
                               selected: selectedPlan == .monthly) {
                        selectedPlan = .monthly
                    }
                }
                .padding(.horizontal)

                // Purchase
                Button {
                    Task { await purchase() }
                } label: {
                    if isPurchasing {
                        ProgressView()
                    } else {
                        Text("Subscribe Now")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .buttonStyle(.tetherPressable)
                .controlSize(.large)
                .padding(.horizontal)
                .disabled(isPurchasing)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Button("Restore Purchases") {
                    Task { await subscriptionManager.restorePurchases() }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)

                HStack {
                    Link("Terms", destination: URL(string: "https://tether.app/terms")!)
                    Text("·")
                    Link("Privacy", destination: URL(string: "https://tether.app/privacy")!)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.bottom)
            }
        }
        .navigationTitle("Upgrade")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func proFeature(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(text)
                .font(.body)
        }
        .accessibilityElement(children: .combine)
    }

    private func planButton(_ title: String, price: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: {
            withAnimation(.tetherQuick) { action() }
        }) {
            HStack {
                VStack(alignment: .leading) {
                    Text(title).font(.headline)
                    Text(price).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding()
            .glassCard(cornerRadius: TetherRadius.button)
            .overlay(
                RoundedRectangle(cornerRadius: TetherRadius.button, style: .continuous)
                    .stroke(selected ? Color.accentColor : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.tetherPressable)
        .accessibilityLabel("\(title), \(price)")
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint("Select this subscription plan")
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
            if success { dismiss() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
