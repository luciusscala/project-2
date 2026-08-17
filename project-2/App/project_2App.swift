
import SwiftData
import SwiftUI

@main
struct project_2App: App {
    private let videoLibrary = VideoLibrary()

    init() {
        // Reset any uploads that were interrupted (e.g. app crash, phone died)
        let context = ModelContext(videoLibrary.modelContainer)
        let predicate = #Predicate<VideoRecord> { $0.uploadStatus == "uploading" }
        let descriptor = FetchDescriptor<VideoRecord>(predicate: predicate)
        if let stale = try? context.fetch(descriptor) {
            for record in stale {
                record.uploadStatus = "failed"
            }
            try? context.save()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(videoLibrary: videoLibrary)
        }
        .modelContainer(videoLibrary.modelContainer)
    }
}
