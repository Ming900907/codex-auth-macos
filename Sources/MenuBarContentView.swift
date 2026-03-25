import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var viewModel: MenuBarViewModel

    var body: some View {
        Group {
            switch viewModel.state {
            case .loading:
                ProgressView("读取中...")
                    .frame(width: 320)
                    .padding()

            case .failed:
                content(snapshot: nil)

            case .loaded(let snapshot):
                content(snapshot: snapshot)
            }
        }
    }

    @ViewBuilder
    private func content(snapshot: AppSnapshot?) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            header(snapshot: snapshot)
            usage(snapshot: snapshot)
            accounts(snapshot: snapshot)
            if let statusMessage = viewModel.statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            actions
        }
        .frame(width: 340)
        .padding(16)
    }

    private func header(snapshot: AppSnapshot?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(snapshot?.activeAccount?.displayName ?? "未识别当前账号")
                .font(.headline)
            Text(snapshot?.activeAccount?.planLabel ?? "无套餐信息")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func usage(snapshot: AppSnapshot?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("当前额度")
                .font(.subheadline.weight(.semibold))
            usageRow(
                title: "5h 剩余",
                usage: snapshot?.usage?.primary,
                emptyText: "暂无 5h 数据"
            )
            usageRow(
                title: "周剩余",
                usage: snapshot?.usage?.secondary,
                emptyText: "暂无周数据"
            )
        }
    }

    private func usageRow(title: String, usage: UsageWindow?, emptyText: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            if let usage {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(usage.remainingPercent)%")
                        .monospacedDigit()
                    Text(usage.resetText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(emptyText)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 13))
    }

    private func accounts(snapshot: AppSnapshot?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("本地账号")
                .font(.subheadline.weight(.semibold))

            if let accounts = snapshot?.accounts, !accounts.isEmpty {
                ForEach(accounts) { account in
                    HStack(alignment: .center, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(account.displayName)
                                    .font(.system(size: 13, weight: account.isActive ? .semibold : .regular))
                                if account.isActive {
                                    Text("当前")
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.accentColor.opacity(0.15))
                                        .clipShape(Capsule())
                                }
                            }
                            Text(account.planLabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button(account.isActive ? "已激活" : "切换") {
                            viewModel.switchAccount(account.accountKey)
                        }
                        .disabled(account.isActive || viewModel.isSwitching || viewModel.isLoggingIn)
                    }
                }
            } else {
                Text("未找到本地账号")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 13))
            }
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 10) {
            if viewModel.isLoggingIn {
                Button("取消登录") {
                    viewModel.cancelLogin()
                }
                .disabled(viewModel.isSwitching)
            } else {
                Button("登录新账号") {
                    viewModel.loginNewAccount()
                }
                .disabled(viewModel.isSwitching)
            }

            HStack {
                Button("刷新") {
                    viewModel.refresh()
                }
                .disabled(viewModel.isSwitching || viewModel.isLoggingIn)

                Spacer()

                Button("退出") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
    }
}
