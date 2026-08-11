
import SwiftUI

struct CameraView: View {
    @ObservedObject var cameraManager: CameraManager
    @ObservedObject var bluetoothManager: BluetoothManager
    var onOpenLibrary: () -> Void

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black

                CameraPreview(captureSession: cameraManager.captureSession)
                    .overlay {
                        Path { path in
                            for box in cameraManager.bb {
                                path.addRect(box)
                            }
                        }
                        .stroke(.red, lineWidth: 2)
                    }
                    .onAppear {
                        cameraManager.viewSize = geometry.size
                        cameraManager.bluetoothManager = bluetoothManager
                        cameraManager.configuration()
                    }

                // Bottom controls
                VStack {
                    Spacer()

                    Button {
                        if cameraManager.isRecording {
                            cameraManager.stopRecording()
                        } else {
                            cameraManager.startRecording()
                        }
                    } label: {
                        RecordButton(isRecording: cameraManager.isRecording)
                    }
                    .buttonStyle(.plain)

                    // Mode selector
                    ModeSelector(onOpenLibrary: onOpenLibrary)
                    .padding(.top, 16)
                    .padding(.bottom, 36)
                }
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Mode Selector

private enum Mode: Int, CaseIterable {
    case camera, library
}

private struct ModeSelector: View {
    var onOpenLibrary: () -> Void
    @State private var selected: Mode = .camera
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 0) {
            modeLabel("CAMERA", mode: .camera)
            modeLabel("LIBRARY", mode: .library)
        }
        .glassEffect(.clear, in: .capsule)
        .contentShape(.capsule)
        .highPriorityGesture(
            DragGesture(minimumDistance: 12)
                .onEnded { value in
                    if value.translation.width < -12 {
                        select(.library)
                    } else if value.translation.width > 12 {
                        select(.camera)
                    }
                }
        )
    }

    private func modeLabel(_ title: String, mode: Mode) -> some View {
        Button {
            select(mode)
        } label: {
            Text(title)
                .font(.caption)
                .fontWeight(selected == mode ? .semibold : .medium)
                .foregroundStyle(selected == mode ? .yellow : .white.opacity(0.7))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background {
                    if selected == mode {
                        Capsule()
                            .fill(.white.opacity(0.15))
                            .matchedGeometryEffect(id: "selector", in: ns)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private func select(_ mode: Mode) {
        guard mode != selected else { return }
        withAnimation(.snappy(duration: 0.25)) {
            selected = mode
        }
        if mode == .library {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                onOpenLibrary()
                withAnimation(.snappy(duration: 0.25)) {
                    selected = .camera
                }
            }
        }
    }
}

// MARK: - Record Button

private struct RecordButton: View {
    let isRecording: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.3), lineWidth: 4)
                .frame(width: 70, height: 70)

            RoundedRectangle(cornerRadius: isRecording ? 8 : 30)
                .fill(Color.red)
                .frame(
                    width: isRecording ? 28 : 56,
                    height: isRecording ? 28 : 56
                )
                .animation(.easeInOut(duration: 0.2), value: isRecording)
        }
    }
}

