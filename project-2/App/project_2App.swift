
import SwiftData
import SwiftUI

@main
struct project_2App: App {
    private let videoLibrary = VideoLibrary()

    var body: some Scene {
        WindowGroup {
            ContentView(videoLibrary: videoLibrary)
        }
        .modelContainer(videoLibrary.modelContainer)
    }
}
