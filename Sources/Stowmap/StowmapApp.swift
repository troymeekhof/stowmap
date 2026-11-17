import SwiftUI
import AppKit
import Sparkle

@main
struct StowmapApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()

    init() {
        _ = Updater.shared   // start Sparkle at launch so daily background checks run
    }

    var body: some Scene {
        Window("Stowmap", id: "main") {
            ContentView()
                .environmentObject(model)
                .environmentObject(Updater.shared)
                .frame(minWidth: 960, minHeight: 640)
                .background(Theme.windowBackground)
                .ignoresSafeArea()
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1200, height: 780)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { Updater.shared.checkForUpdates() }
            }
            CommandGroup(replacing: .newItem) {
                Button("Scan a Folder…") { model.chooseFolder() }
                    .keyboardShortcut("o", modifiers: .command)
                Button("Scan All Drives") { model.scanAll() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

// MARK: - Updates (Sparkle; feed + public key in Info.plist)

@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()

    private let controller = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    @Published private(set) var canCheck = false

    private init() {
        controller.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheck)
    }

    func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }
}
