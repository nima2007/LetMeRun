import SwiftUI

@main
struct LetMeRunApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 420, height: 340)
        .windowResizability(.contentSize)
    }
}
