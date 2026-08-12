
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
        ZStack(alignment: .bottom) {
            CameraView(
                cameraManager: cameraManager,
                bluetoothManager: bluetoothManager
            )
            .allowsHitTesting(!showLibrary)

            if showLibrary {
                LibraryView(videoLibrary: videoLibrary)
                    .transition(.move(edge: .trailing))
            }

            ModeSelector(showLibrary: $showLibrary)
                .padding(.bottom, 36)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Mode Selector

private struct ModeSelector: View {
    @Binding var showLibrary: Bool
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 0) {
            modeButton("CAMERA", isSelected: !showLibrary) {
                showLibrary = false
            }
            modeButton("LIBRARY", isSelected: showLibrary) {
                showLibrary = true
            }
        }
        .glassEffect(.clear, in: .capsule)
        .contentShape(.capsule)
        .highPriorityGesture(
            DragGesture(minimumDistance: 12)
                .onEnded { value in
                    withAnimation(.snappy(duration: 0.3)) {
                        if value.translation.width < -12 {
                            showLibrary = true
                        } else if value.translation.width > 12 {
                            showLibrary = false
                        }
                    }
                }
        )
    }

    private func modeButton(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.3)) {
                action()
            }
        } label: {
            Text(title)
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .medium)
                .foregroundStyle(isSelected ? Color.accentColor : .white.opacity(0.7))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background {
                    if isSelected {
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
