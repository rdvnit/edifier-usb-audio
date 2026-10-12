import SwiftUI
import AppKit

@main
struct M60Entry {
    static func main() {
        if CommandLine.arguments.count > 1 { DiagnosticCommand.run() }
        M60AudioApp.main()
    }
}

struct M60AudioApp: App {
    @StateObject private var model = AppModel()
    var body: some Scene {
        WindowGroup("EDIFIER USB Audio") {
            ContentView().environmentObject(model)
        }
        .defaultSize(width: 380, height: 620)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(after: .pasteboard) {
                Button("Copy Audio Diagnostics") { model.copyDiagnostics() }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
            }
        }
    }
}
