import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var viewModel: MenuBarViewModel
    @State private var expandedAccountKey: String?
    @State private var pendingRemovalAccount: AccountSummary?

    var body: some View {
        ZStack {
            background

            switch viewModel.state {
            case .loading:
                loading
            case .failed:
                content(snapshot: nil)
            case .loaded(let snapshot):
                content(snapshot: snapshot)
            }
        }
        .frame(width: 372)
        .alert(
            "Remove account?",
            isPresented: Binding(
                get: { pendingRemovalAccount != nil },
                set: { if !$0 { pendingRemovalAccount = nil } }
            ),
            presenting: pendingRemovalAccount
        ) { account in
            Button("Remove", role: .destructive) {
                viewModel.removeAccount(account.accountKey)
                if expandedAccountKey == account.accountKey {
                    expandedAccountKey = nil
                }
                pendingRemovalAccount = nil
            }
            Button("Cancel", role: .cancel) {
                pendingRemovalAccount = nil
            }
        } message: { account in
            Text("This will log out \(account.displayName) from the local account list.")
        }
    }

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.08, blue: 0.10),
                    Color(red: 0.12, green: 0.12, blue: 0.15),
                    Color(red: 0.08, green: 0.08, blue: 0.10)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 220, height: 220)
                .blur(radius: 54)
                .offset(x: 118, y: -118)

            Circle()
                .fill(Color.white.opacity(0.05))
                .frame(width: 260, height: 260)
                .blur(radius: 62)
                .offset(x: -128, y: 144)
        }
    }

    private var loading: some View {
        mainCard {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading...")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.secondary.opacity(0.85))
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
    private func content(snapshot: AppSnapshot?) -> some View {
        ZStack {
            mainCard {
                VStack(alignment: .leading, spacing: 12) {
                    header(snapshot: snapshot)
                    usageSection(snapshot: snapshot)
                    accountsSection(snapshot: snapshot)
                    statusSection
                    actions
                }
            }

            if viewModel.isRefreshing {
                refreshOverlay
            }
        }
    }

    private func header(snapshot: AppSnapshot?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(snapshot?.activeAccount?.displayName ?? "Active account unavailable")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.96))
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            HStack(spacing: 8) {
                Text(snapshot?.activeAccount?.planLabel ?? "No plan")
                Text("•")
                    .foregroundStyle(.secondary.opacity(0.85))
                Text(snapshot?.activeAccount?.isActive == true ? "Active" : "No active account")
            }
            .font(.system(size: 10, weight: .regular))
            .foregroundStyle(.secondary.opacity(0.88))
            .lineLimit(1)
        }
    }

    private func usageSection(snapshot: AppSnapshot?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Usage")

            if let usage = snapshot?.usage {
                VStack(alignment: .leading, spacing: 8) {
                    UsageMeterCard(title: "5h left", usage: usage.primary, emptyText: "No 5h data")
                    UsageMeterCard(title: "Weekly left", usage: usage.secondary, emptyText: "No weekly data")
                }
            } else {
                Text("No usage data available")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary.opacity(0.85))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func accountsSection(snapshot: AppSnapshot?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Accounts")

            if let accounts = snapshot?.accounts, !accounts.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(accounts) { account in
                        if account.isActive {
                            activeAccountRow(account)
                        } else {
                            inactiveAccountRow(account)
                        }
                    }
                }
            } else {
                Text("No local accounts found")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary.opacity(0.85))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func activeAccountRow(_ account: AccountSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(account.displayName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.95))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Text(account.planLabel)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(.secondary.opacity(0.84))
                }

                Spacer(minLength: 0)

                Text("Active")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.green.opacity(0.96))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.14), in: Capsule())
            }

            Button("Logout account") {
                pendingRemovalAccount = account
            }
            .buttonStyle(AccountActionButtonStyle(tint: Color.red.opacity(0.88), background: Color.red.opacity(0.14)))
            .disabled(viewModel.isSwitching || viewModel.isRemoving || viewModel.isLoggingIn)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 1)
    }

    private func inactiveAccountRow(_ account: AccountSummary) -> some View {
        let isExpanded = expandedAccountKey == account.accountKey

        return VStack(alignment: .leading, spacing: 6) {
            Button {
                let nextExpandedKey = isExpanded ? nil : account.accountKey
                expandedAccountKey = nextExpandedKey
                if nextExpandedKey == account.accountKey, !account.isAccessInvalid {
                    viewModel.validateAccountAccess(account.accountKey)
                }
            } label: {
                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(account.displayName)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.95))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Text(account.planLabel)
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(.secondary.opacity(0.84))
                    }

                    Spacer(minLength: 0)

                    HStack(spacing: 6) {
                        Text(inactiveAccountStatusText(account))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(inactiveAccountStatusColor(account))
                            .frame(minWidth: 96, alignment: .trailing)

                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary.opacity(0.76))
                            .frame(width: 12, height: 12)
                            .fixedSize()
                    }
                    .frame(width: 118, alignment: .trailing)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    if let usage = account.usage {
                        VStack(alignment: .leading, spacing: 8) {
                            UsageMeterCard(title: "5h left", usage: usage.primary, emptyText: "No 5h data")
                            UsageMeterCard(title: "Weekly left", usage: usage.secondary, emptyText: "No weekly data")
                        }
                    } else {
                        Text("No usage history for this account")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary.opacity(0.85))
                    }

                    if let accessIssue = account.accessIssue {
                        Text(accessIssue)
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(Color.orange.opacity(0.92))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: 8) {
                        Button("Switch account") {
                            viewModel.switchAccount(account.accountKey)
                        }
                        .buttonStyle(
                            AccountActionButtonStyle(
                                tint: account.isAccessInvalid ? Color.secondary.opacity(0.72) : Color.white.opacity(0.94),
                                background: account.isAccessInvalid ? Color.white.opacity(0.08) : Color.white.opacity(0.12)
                            )
                        )
                        .disabled(viewModel.isSwitching || viewModel.isRemoving || viewModel.isLoggingIn || account.isAccessInvalid)

                        Button("Logout account") {
                            pendingRemovalAccount = account
                        }
                        .buttonStyle(AccountActionButtonStyle(tint: Color.red.opacity(0.88), background: Color.red.opacity(0.14)))
                    }
                    .disabled(viewModel.isSwitching || viewModel.isRemoving || viewModel.isLoggingIn)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let statusMessage = viewModel.statusMessage {
                Text(statusMessage)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(.secondary.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(Color.red.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if case .loaded(let snapshot) = viewModel.state,
               let accessIssue = snapshot.activeAccessIssue {
                Text(accessIssue)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(Color.orange.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func inactiveAccountStatusText(_ account: AccountSummary) -> String {
        if account.isAccessInvalid {
            return "Re-login required"
        }
        return account.usage != nil ? "Has history" : "No history"
    }

    private func inactiveAccountStatusColor(_ account: AccountSummary) -> Color {
        if account.isAccessInvalid {
            return Color.red.opacity(0.86)
        }
        return .secondary.opacity(0.88)
    }

    private var actions: some View {
        HStack(spacing: 8) {
            if viewModel.isLoggingIn {
                Button("Cancel login") {
                    viewModel.cancelLogin()
                }
                .disabled(viewModel.isSwitching)
                .disabled(viewModel.isSwitching || viewModel.isRemoving)
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary.opacity(0.85))
            } else {
                Button("Login new account") {
                    viewModel.loginNewAccount()
                }
                .disabled(viewModel.isSwitching || viewModel.isRemoving)
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.95))
            }

            Spacer(minLength: 0)

            Button("Refresh") {
                viewModel.refresh()
            }
            .disabled(viewModel.isSwitching || viewModel.isRemoving || viewModel.isLoggingIn)
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary.opacity(0.85))

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary.opacity(0.85))
        }
        .padding(.top, 2)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary.opacity(0.8))
            .textCase(.uppercase)
            .tracking(0.5)
    }

    private func mainCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.20), radius: 18, x: 0, y: 10)
    }

    private var refreshOverlay: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(Color.black.opacity(0.28))
            .overlay {
                VStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                    Text("Refreshing...")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.92))
                }
            }
            .allowsHitTesting(true)
    }
}

private struct UsageMeterCard: View {
    let title: String
    let usage: UsageWindow?
    let emptyText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary.opacity(0.82))

                    Text(usage?.resetText ?? emptyText)
                        .font(.system(size: 8, weight: .regular))
                        .foregroundStyle(.secondary.opacity(0.78))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }

                Spacer(minLength: 0)

                if let usage {
                    Text("\(usage.remainingPercent)%")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(UsagePalette.color(for: usage.remainingPercent))
                } else {
                    Text("--")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary.opacity(0.82))
                }
            }

            UsageBar(
                progress: usage.map { Double($0.remainingPercent) / 100.0 },
                tint: usage.map { UsagePalette.color(for: $0.remainingPercent) } ?? .secondary.opacity(0.55)
            )
        }
        .padding(.vertical, 1)
        .padding(.horizontal, 2)
    }
}

private struct AccountActionButtonStyle: ButtonStyle {
    let tint: Color
    let background: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(tint.opacity(configuration.role == .destructive ? 0.92 : 1))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(background.opacity(configuration.isPressed ? 0.72 : 1))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .contentShape(Capsule())
    }
}

private struct UsageBar: View {
    let progress: Double?
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.10))

                if let progress {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [tint.opacity(0.96), tint.opacity(0.64)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: proxy.size.width * max(0, min(progress, 1)))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 4)
    }
}

private enum UsagePalette {
    static func color(for remainingPercent: Int) -> Color {
        switch remainingPercent {
        case 67...100:
            return Color(red: 0.44, green: 0.86, blue: 0.62)
        case 34...66:
            return Color(red: 0.96, green: 0.76, blue: 0.31)
        default:
            return Color(red: 0.96, green: 0.44, blue: 0.39)
        }
    }
}
