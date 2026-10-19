import SwiftUI

@main
struct NaturalSearchApp: App {
    @State private var model = SearchModel()

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
    }
}
