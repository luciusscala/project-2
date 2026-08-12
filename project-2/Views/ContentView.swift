
import SwiftUI

struct ContentView: View {
    @StateObject private var cameraManager: CameraManager
    @StateObject private var bluetoothManager = BluetoothManager()
    @State private var selectedTab = 0

    private let videoLibrary: VideoLibrary

    init(videoLibrary: VideoLibrary) {
        self.videoLibrary = videoLibrary
        _cameraManager = StateObject(wrappedValue: CameraManager(videoLibrary: videoLibrary))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                CameraView(
                    cameraManager: cameraManager,
                    bluetoothManager: bluetoothManager
                )
                .tag(0)

                LibraryView(videoLibrary: videoLibrary)
                    .tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            ModeSelector(selectedTab: $selectedTab)
                .padding(.bottom, 36)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Mode Selector

private struct ModeSelector: View {
    @Binding var selectedTab: Int
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 0) {
            modeLabel("CAMERA", tab: 0)
            modeLabel("LIBRARY", tab: 1)
        }
        .glassEffect(.clear, in: .capsule)
        .contentShape(.capsule)
        .highPriorityGesture(
            DragGesture(minimumDistance: 12)
                .onEnded { value in
                    withAnimation(.snappy(duration: 0.25)) {
                        if value.translation.width < -12 {
                            selectedTab = 1
                        } else if value.translation.width > 12 {
                            selectedTab = 0
                        }
                    }
                }
        )
    }

    private func modeLabel(_ title: String, tab: Int) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.25)) {
                selectedTab = tab
            }
        } label: {
            Text(title)
                .font(.caption)
                .fontWeight(selectedTab == tab ? .semibold : .medium)
                .foregroundStyle(selectedTab == tab ? Color.accentColor : .white.opacity(0.7))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background {
                    if selectedTab == tab {
                        Capsule()
                            .fill(.white.opacity(0.15))
                            .matchedGeometryEffect(id: "selector", in: ns)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ContentView(videoLibrary: VideoLibrary())
}
