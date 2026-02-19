import SwiftUI
import TetherKit

struct OnboardingView: View {
    @State private var authManager = AuthManager.shared
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        Group {
            if !authManager.isAuthenticated {
                LoginView()
            } else if !hasCompletedOnboarding {
                OnboardingFlowView(onComplete: { hasCompletedOnboarding = true })
            } else {
                ContentView()
                    .onAppear {
                        // Check for incomplete sessions on authenticated launch
                        if SessionManager.shared.hasIncompleteSession {
                            // The main content view should handle showing the recovery dialog
                        }
                    }
            }
        }
    }
}

// MARK: - Onboarding Flow

struct OnboardingFlowView: View {
    let onComplete: () -> Void

    @State private var currentStep = 0
    @State private var brainDumpText = ""
    @State private var parsedTasks: [TetherTask] = []
    @State private var isParsing = false
    @State private var selectedBlocklistDefaults: Set<String> = [
        "twitter.com", "reddit.com", "youtube.com", "instagram.com", "tiktok.com", "discord.com"
    ]
    @State private var customBlocklistItem = ""

    private let totalSteps = 4
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            // Progress indicator
            HStack(spacing: 8) {
                ForEach(0..<totalSteps, id: \.self) { step in
                    Capsule()
                        .fill(step <= currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(height: 4)
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 20)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Onboarding progress")
            .accessibilityValue("Step \(currentStep + 1) of \(totalSteps)")

            Spacer()

            // Step content
            Group {
                switch currentStep {
                case 0: welcomeStep
                case 1: brainDumpStep
                case 2: blocklistStep
                case 3: readyStep
                default: EmptyView()
                }
            }
            .frame(maxWidth: 500)

            Spacer()

            // Navigation
            HStack {
                if currentStep > 0 {
                    Button("Back") {
                        withAnimation(reduceMotion ? .none : .tetherSpring) { currentStep -= 1 }
                    }
                    .buttonStyle(.bordered)
                    .buttonStyle(.tetherPressable)
                    .accessibilityHint("Go to previous step")
                }

                Spacer()

                if currentStep < totalSteps - 1 {
                    Button("Skip") {
                        withAnimation(reduceMotion ? .none : .tetherSpring) { currentStep += 1 }
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
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Step 1: Welcome

    private var welcomeStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "hand.wave.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)

            Text("Welcome to Tether!")
                .font(.largeTitle.bold())

            Text("Your productivity accountability coach. Let's set up your workspace in a few quick steps.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if SubscriptionManager.shared.isTrialActive {
                Label("You have a 14-day free trial of all Pro features", systemImage: "sparkles")
                    .font(.subheadline)
                    .foregroundStyle(Color.accentColor)
                    .padding(.top, 8)
            }
        }
    }

    // MARK: - Step 2: Brain Dump

    private var brainDumpStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "brain.head.profile.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.accentColor)

            Text("What's on your mind today?")
                .font(.title.bold())

            Text("Type everything you need to do. We'll turn it into a task list.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            TextEditor(text: $brainDumpText)
                .font(.body)
                .frame(height: 120)
                .scrollContentBackground(.hidden)
                .padding(8)
                .glassCard(cornerRadius: TetherRadius.small)

            if isParsing {
                ProgressView("Parsing tasks...")
            }

            if !parsedTasks.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tasks found:")
                        .font(.headline)

                    ForEach(parsedTasks) { task in
                        HStack {
                            Image(systemName: "checkmark.circle")
                                .foregroundStyle(Color.accentColor)
                            Text(task.title)
                                .font(.body)
                        }
                    }
                }
                .padding()
                .glassCard(cornerRadius: TetherRadius.small)
            }
        }
    }

    // MARK: - Step 3: Blocklist

    private var blocklistStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "shield.checkered")
                .font(.system(size: 48))
                .foregroundStyle(Color.accentColor)

            Text("Set Up Your Blocklist")
                .font(.title.bold())

            Text("Choose sites to block during focus sessions. You can always change these later.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            let defaults = [
                ("twitter.com", "Twitter / X"),
                ("reddit.com", "Reddit"),
                ("youtube.com", "YouTube"),
                ("instagram.com", "Instagram"),
                ("tiktok.com", "TikTok"),
                ("discord.com", "Discord"),
            ]

            VStack(spacing: 8) {
                ForEach(defaults, id: \.0) { domain, name in
                    HStack {
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
                                    .font(.body)
                                Spacer()
                                Text(domain)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    .accessibilityLabel(name)
                    .accessibilityValue(selectedBlocklistDefaults.contains(domain) ? "Selected" : "Not selected")
                    .accessibilityAddTraits(.isButton)
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding()
            .glassCard(cornerRadius: TetherRadius.small)

            HStack {
                TextField("Add custom domain...", text: $customBlocklistItem)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        if !customBlocklistItem.isEmpty {
                            selectedBlocklistDefaults.insert(customBlocklistItem)
                            customBlocklistItem = ""
                        }
                    }

                Button("Add") {
                    if !customBlocklistItem.isEmpty {
                        selectedBlocklistDefaults.insert(customBlocklistItem)
                        customBlocklistItem = ""
                    }
                }
                .disabled(customBlocklistItem.isEmpty)
            }
        }
    }

    // MARK: - Step 4: Ready

    private var readyStep: some View {
        VStack(spacing: 24) {
            Image(systemName: "bolt.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)

            Text("You're All Set!")
                .font(.largeTitle.bold())

            Text("Start your first focus session and see how Tether keeps you on track.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                saveOnboardingData()
                AnalyticsService.shared.trackOnboardingStep(4, name: "complete")
                onComplete()
            } label: {
                HStack {
                    Image(systemName: "play.fill")
                    Text("Get Started")
                }
                .frame(maxWidth: 280)
                .frame(height: 44)
            }
            .buttonStyle(.borderedProminent)
            .buttonStyle(.tetherPressable)
        }
    }

    // MARK: - Actions

    private func advanceStep() {
        AnalyticsService.shared.trackOnboardingStep(currentStep + 1, name: stepName(currentStep))

        if currentStep == 1 && !brainDumpText.isEmpty && parsedTasks.isEmpty {
            // Parse brain dump before advancing
            isParsing = true
            Task {
                let parsed = await NLParsingService.shared.parseTasks(from: brainDumpText)
                parsedTasks = parsed
                isParsing = false
                withAnimation(reduceMotion ? .none : .default) { currentStep += 1 }
            }
        } else {
            withAnimation(reduceMotion ? .none : .default) { currentStep += 1 }
        }
    }

    private func stepName(_ step: Int) -> String {
        switch step {
        case 0: "welcome"
        case 1: "brain_dump"
        case 2: "blocklist"
        case 3: "ready"
        default: "unknown"
        }
    }

    private func saveOnboardingData() {
        // Save parsed tasks
        for var task in parsedTasks {
            try? DatabaseManager.shared.saveTask(&task)
        }

        // Save blocklist items
        for domain in selectedBlocklistDefaults {
            var item = BlocklistItem(domain: domain, displayName: domain)
            try? DatabaseManager.shared.saveBlocklistItem(&item)
        }
    }
}
