import SwiftUI

@main
struct TadoApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            RootView()
                .environment(model)
                .frame(width: 340)
        } label: {
            Image(systemName: model.isAnyZoneHeating ? "flame.fill" : "thermometer.medium")
        }
        .menuBarExtraStyle(.window)
    }
}
