import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct RTXConfigMakerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    init() {
        // 動作確認用: `--dump` でデフォルト設定のコンフィグを標準出力して終了
        if CommandLine.arguments.contains("--dump") {
            let m = ConfigModel()
            print(ConfigGenerator.generate(m))
            exit(0)
        }
    }

    var body: some Scene {
        WindowGroup("RTX1220 ConfigMaker") {
            ContentView()
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
