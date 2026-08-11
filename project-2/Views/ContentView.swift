
import SwiftUI

struct ContentView: View {
    @StateObject private var cameraManager: CameraManager
    @StateObject private var bluetoothManager = BluetoothManager()
    @State private var showLibrary = false

    private let videoLibrary: VideoLibrary

    init(videoLibrary: VideoLibrary) {
        self.videoLibrary = videoLibrary
        _cameraManager = StateObject(wrappedValue: CameraManager(videoLibrary: videoLibrary))
    }

    var body: some View {
        CameraView(
            cameraManager: cameraManager,
            bluetoothManager: bluetoothManager,
            onOpenLibrary: { showLibrary = true }
        )
        .fullScreenCover(isPresented: $showLibrary) {
            LibraryView(videoLibrary: videoLibrary)
        }
    }
}

#Preview {
    ContentView(videoLibrary: VideoLibrary())
}
