import SwiftUI

@main
struct BrewlightApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model: AppModel

    init() {
        let model = AppModel()
        _model = State(initialValue: model)
        AppDelegate.model = model
    }

    var body: some Scene {
        Window(AppInfo.name, id: "main") {
            MainWindow()
                .environment(model)
                .task { await model.start() }
        }
        .defaultSize(width: 1440, height: 900)
        // Only the minimum size comes from content; .automatic re-measures the whole view tree for
        // ideal/max sizes on every update, which was the single biggest cost in the profiler.
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .commands { BrewlightCommands(model: model) }

        WindowGroup(String(localized: "Package"), id: "package", for: String.self) { $id in
            if let id {
                PackageDetailWindow(packageID: id)
                    .environment(model)
            }
        }
        .defaultSize(width: 760, height: 820)

        Window(String(localized: "About \(AppInfo.name)"), id: "about") {
            AboutView().environment(model)
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)

        Settings {
            SettingsView().environment(model)
        }
    }
}
