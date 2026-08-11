
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

                // Status indicator — top right
                VStack {
                    HStack {
                        Spacer()
                        Circle()
                            .fill(bluetoothManager.isConnected ? .green : .red)
                            .frame(width: 10, height: 10)
                            .padding(.trailing, 20)
                            .padding(.top, 60)
                    }
                    Spacer()
                }

                // Bottom controls
                VStack {
                    Spacer()
                    HStack {
                        Button(action: onOpenLibrary) {
                            Image(systemName: "square.grid.2x2")
                                .font(.title2)
                                .foregroundStyle(.white)
                        }
                        .padding(.leading, 40)

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

                        Spacer()

                        // Placeholder for symmetry
                        Color.clear
                            .frame(width: 24, height: 24)
                            .padding(.trailing, 40)
                    }
                    .padding(.bottom, 40)
                }
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Record Button

private struct RecordButton: View {
    let isRecording: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white, lineWidth: 4)
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
