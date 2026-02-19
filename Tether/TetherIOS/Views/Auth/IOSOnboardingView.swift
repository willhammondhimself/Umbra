import SwiftUI
import TetherKit

struct IOSOnboardingView: View {
    let onComplete: () -> Void

    @State private var currentStep = 0
    @State private var brainDumpText = ""
    @State private var parsedTasks: [TetherTask] = []
    @State private var isParsing = false
    @State private var selectedBlocklistDefaults: Set<String> = [
        "twitter.com", "reddit.com", "youtube.com", "instagram.com", "tiktok.com", "discord.com"
    ]

    private let totalSteps = 4
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            // Progress
            HStack(spacing: 6) {
                ForEach(0..<totalSteps, id: \.self) { step in
                    Capsule()
                        .fill(step <= currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(height: 4)
                }
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Onboarding progress")
            .accessibilityValue("Step \(currentStep + 1) of \(totalSteps)")

            TabView(selection: $currentStep) {
                welcomeStep.tag(0)
                brainDumpStep.tag(1)
                blocklistStep.tag(2)
                readyStep.tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            // Navigation
            HStack {
                if currentStep > 0 {
                    Button("Back") {
                        withAnimation(reduceMotion ? .none : .default) { currentStep -= 1 }
                    }
                    .accessibilityHint("Go to previous step")
                }

                Spacer()

                if currentStep < totalSteps - 1 {
                    Button("Skip") {
                        withAnimation(reduceMotion ? .none : .default) { currentStep += 1 }
                    }
                    .foregroundStyle(.secondary)
                    .accessibilityHint("Skip this step")

                    Button("Next") {
                        advanceStep()
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonStyle(.tetherPressable)
                }
            }
            .padding()
        }
    }

    private var welcomeStep: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "hand.wave.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            Text("Welcome to Tether!")
                .font(.largeTitle.bold())
            Text("Your productivity accountability coach.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if SubscriptionManager.shared.isTrialActive {
                Label("14-day Pro trial active", systemImage: "sparkles")
                    .font(.subheadline)
                    .foregroundStyle(Color.accentColor)
            }
            Spacer()
        }
        .padding()
    }

    private var brainDumpStep: some View {
        VStack(spacing: 16) {
            Text("What's on your mind?")
                .font(.title.bold())
            Text("Type everything you need to do.")
                .font(.body)
                .foregroundStyle(.secondary)

            TextEditor(text: $brainDumpText)
                .frame(height: 150)
                .scrollContentBackground(.hidden)
                .padding(8)
                .glassCard(cornerRadius: TetherRadius.small)

            if isParsing {
                ProgressView("Parsing tasks...")
            }

            if !parsedTasks.isEmpty {
                ForEach(parsedTasks) { task in
                    HStack {
                        Image(systemName: "checkmark.circle")
                            .foregroundStyle(Color.accentColor)
                        Text(task.title)
                    }
                }
            }
        }
        .padding()
    }

    private var blocklistStep: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("Block Distractions")
                    .font(.title.bold())

                let defaults = [
                    ("twitter.com", "Twitter / X"),
                    ("reddit.com", "Reddit"),
                    ("youtube.com", "YouTube"),
                    ("instagram.com", "Instagram"),
                    ("tiktok.com", "TikTok"),
                    ("discord.com", "Discord"),
                ]

                ForEach(defaults, id: \.0) { domain, name in
                    Button {
                        if selectedBlocklistDefaults.contains(domain) {
                            selectedBlocklistDefaults.remove(domain)
                        } else {
                            selectedBlocklistDefaults.insert(domain)
                        }
                    } label: {
                        HStack {
                            Image(systemName: selectedBlocklistDefaults.contains(domain) ? "checkmark.square.fill" : "square")
                                .foregroundStyle(Color.accentColor)
                            Text(name)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(name)
                    .accessibilityValue(selectedBlocklistDefaults.contains(domain) ? "Selected" : "Not selected")
                    .accessibilityAddTraits(.isButton)
                }
            }
            .padding()
        }
    }

    private var readyStep: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "bolt.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            Text("You're All Set!")
                .font(.largeTitle.bold())

            Button {
                saveOnboardingData()
                AnalyticsService.shared.trackOnboardingStep(4, name: "complete")
                onComplete()
            } label: {
                Text("Get Started")
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
            }
            .buttonStyle(.borderedProminent)
            .buttonStyle(.tetherPressable)
            .padding(.horizontal, 40)
            Spacer()
        }
    }

    private func advanceStep() {
        AnalyticsService.shared.trackOnboardingStep(currentStep + 1, name: "step_\(currentStep)")

        if currentStep == 1 && !brainDumpText.isEmpty && parsedTasks.isEmpty {
            isParsing = true
            Task {
                parsedTasks = await NLParsingService.shared.parseTasks(from: brainDumpText)
                isParsing = false
                withAnimation(reduceMotion ? .none : .default) { currentStep += 1 }
            }
        } else {
            withAnimation(reduceMotion ? .none : .default) { currentStep += 1 }
        }
    }

    private func saveOnboardingData() {
        for var task in parsedTasks {
            try? DatabaseManager.shared.saveTask(&task)
        }
        for domain in selectedBlocklistDefaults {
            var item = BlocklistItem(domain: domain, displayName: domain)
            try? DatabaseManager.shared.saveBlocklistItem(&item)
        }
    }
}
