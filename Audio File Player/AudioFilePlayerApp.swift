import SwiftUI

@main
struct AudioFilePlayerApp: App {
    @State private var library = AudioLibraryManager()   // @Observable
    @StateObject private var player = AudioPlayerManager() // ObservableObject

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(library)
                .environmentObject(player)
        }
    }
}
