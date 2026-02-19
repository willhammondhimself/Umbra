import SwiftUI
import TetherKit

struct SidebarView: View {
    @Binding var selectedTab: AppTab
    @Binding var isExpanded: Bool
    @Namespace private var sidebarAnimation
    @State private var hoverTask: Task<Void, Never>?
    @State private var isPinned = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(spacing: 8) {
            // Pin/unpin toggle
            Button {
                withAnimation(reduceMotion ? .none : .tetherSpring) {
                    isPinned.toggle()
                    isExpanded = isPinned
                }
            } label: {
                Image(systemName: isPinned ? "sidebar.left" : "sidebar.leading")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.tetherPressable)
            .help(isPinned ? "Collapse sidebar" : "Pin sidebar open")
            .accessibilityLabel(isPinned ? "Collapse sidebar" : "Pin sidebar open")
            .padding(.bottom, 4)

            ForEach(AppTab.allCases, id: \.self) { tab in
                sidebarItem(for: tab)
            }
            Spacer()
        }
        .padding(.vertical, 12)
        .padding(.horizontal, isExpanded ? 12 : 6)
        .frame(maxHeight: .infinity)
        .glassCard(cornerRadius: TetherRadius.sidebar)
        .onHover { hovering in
            guard !isPinned else { return }
            hoverTask?.cancel()
            hoverTask = Task {
                if hovering {
                    try? await Task.sleep(for: .milliseconds(200))
                }
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    withAnimation(reduceMotion ? .none : .tetherSpring) {
                        isExpanded = hovering
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func sidebarItem(for tab: AppTab) -> some View {
        let isSelected = selectedTab == tab

        Button {
            withAnimation(reduceMotion ? .none : .tetherSpring) {
                selectedTab = tab
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: tab.icon)
                    .font(.system(size: 18, weight: isSelected ? .semibold : .regular))
                    .frame(width: 24, height: 24)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)

                if isExpanded {
                    Text(tab.title)
                        .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .lineLimit(1)

                    Spacer()
                }
            }
            .padding(.horizontal, isExpanded ? 12 : 8)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.tetherPressable)
        .accessibilityLabel(tab.title)
        .accessibilityValue(isSelected ? "Selected" : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: TetherRadius.button, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
                    .interactiveGlass(cornerRadius: TetherRadius.button)
                    .matchedGeometryEffect(id: "selectedTab", in: sidebarAnimation)
            }
        }
    }
}
