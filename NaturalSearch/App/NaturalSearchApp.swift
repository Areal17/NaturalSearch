import AppIntents
import SwiftUI

@main
struct NaturalSearchApp: App {
    @State private var model: SearchModel

    init() {
        let model = SearchModel()
        _model = State(initialValue: model)
        // Früh registrieren: Kurzbefehle können die App „kalt“ starten und das Modell sofort brauchen.
        AppDependencyManager.shared.add(dependency: model)
    }

    var body: some Scene {
        Window("NaturalSearch", id: "main") {
            ContentView()
                .environment(model)
        }
        .defaultSize(width: 1500, height: 900)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Suche zurücksetzen", action: model.reset)
                    .keyboardShortcut("n")
            }
        }

        MenuBarExtra("NaturalSearch", systemImage: "sparkle.magnifyingglass") {
            MenuBarPanel()
                .environment(model)
        }
        .menuBarExtraStyle(.window)
    }
}
