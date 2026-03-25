import AppKit
import SwiftUI

@main
struct CodexAuthMacOSBarApp: App {
    @StateObject private var viewModel = MenuBarViewModel()

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(viewModel: viewModel)
        } label: {
            Label(viewModel.menuBarTitle, systemImage: "person.crop.circle.badge.checkmark")
        }
        .menuBarExtraStyle(.window)

        Settings {
            EmptyView()
        }
    }
}
