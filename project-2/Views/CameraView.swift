
import SwiftUI

struct CameraView: View {
    @ObservedObject var cameraManager: CameraManager
    @ObservedObject var bluetoothManager: BluetoothManager

    @State private var showDropdown = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black

                if cameraManager.isPreviewEnabled {
                    CameraPreview(captureSession: cameraManager.captureSession)
                        .overlay {
                            if cameraManager.showBoundingBoxes {
                                Path { path in
                                    for box in cameraManager.bb {
                                        path.addRect(box)
                                    }
                                }
                                .stroke(.red, lineWidth: 2)
                            }
                        }
                        .transition(.opacity)
                }

                // Dismiss tap area
                if showDropdown {
                    Color.black.opacity(0.01)
                        .onTapGesture {
                            withAnimation(.snappy(duration: 0.3)) {
                                showDropdown = false
                            }
                        }
                }

                // Top-right controls
                VStack {
                    HStack {
                        Spacer()
                        VStack(alignment: .trailing, spacing: 8) {
                            Button {
                                withAnimation(.snappy(duration: 0.3)) {
                                    showDropdown.toggle()
                                }
                            } label: {
                                Image(systemName: "slider.horizontal.3")
                                    .font(.body)
                                    .foregroundStyle(.white)
                                    .frame(width: 36, height: 36)
                                    .contentShape(.rect)
                            }
                            .buttonStyle(.plain)

                            if showDropdown {
                                OptionsDropdown(
                                    cameraManager: cameraManager,
                                    bluetoothManager: bluetoothManager
                                )
                                .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .topTrailing)))
                            }
                        }
                        .padding(.trailing, 16)
                        .padding(.top, 56)
                    }
                    Spacer()
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
                    .padding(.bottom, 80)
                }
            }
            .onAppear {
                cameraManager.viewSize = geometry.size
                cameraManager.bluetoothManager = bluetoothManager
                cameraManager.configuration()
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Options Dropdown

private struct OptionsDropdown: View {
    @ObservedObject var cameraManager: CameraManager
    @ObservedObject var bluetoothManager: BluetoothManager

    private let timerPresets: [(String, TimeInterval)] = [
        ("30s", 30), ("1m", 60), ("5m", 300), ("10m", 600)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Bounding Boxes
            Toggle(isOn: $cameraManager.showBoundingBoxes) {
                Text("Bounding Boxes")
                    .font(.subheadline)
                    .foregroundStyle(.white)
            }
            .tint(.accentColor)

            Divider().overlay(.white.opacity(0.15))

            // Performance Mode
            Toggle(isOn: Binding(
                get: { !cameraManager.isPreviewEnabled },
                set: { cameraManager.isPreviewEnabled = !$0 }
            )) {
                Text("Performance Mode")
                    .font(.subheadline)
                    .foregroundStyle(.white)
            }
            .tint(.accentColor)

            Divider().overlay(.white.opacity(0.15))

            // Motor Control
            Toggle(isOn: $bluetoothManager.isMotorEnabled) {
                Text("Motor Movement")
                    .font(.subheadline)
                    .foregroundStyle(.white)
            }
            .tint(.accentColor)

            Divider().overlay(.white.opacity(0.15))

            // Schedule Recording
            VStack(alignment: .leading, spacing: 10) {
                Text("Start Timer")
                    .font(.subheadline)
                    .foregroundStyle(.white)

                if let scheduled = cameraManager.scheduledRecordingDate {
                    HStack {
                        Text(scheduled, style: .timer)
                            .monospacedDigit()
                            .font(.title3.weight(.medium))
                            .foregroundStyle(Color.accentColor)

                        Spacer()

                        Button {
                            cameraManager.cancelScheduledRecording()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    HStack(spacing: 8) {
                        ForEach(timerPresets, id: \.1) { preset in
                            Button {
                                cameraManager.scheduleRecording(
                                    at: Date().addingTimeInterval(preset.1)
                                )
                            } label: {
                                Text(preset.0)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                            }
                            .buttonStyle(.glass(.clear))
                        }
                    }
                }
            }

            Divider().overlay(.white.opacity(0.15))

            // Connection Status
            HStack {
                Text("Hardware")
                    .font(.subheadline)
                    .foregroundStyle(.white)
                Spacer()
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 7, height: 7)
                    Text(statusText)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .padding(14)
        .frame(width: 230)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }

    private var statusColor: Color {
        if bluetoothManager.isConnected { return .green }
        if bluetoothManager.isScanning { return .yellow }
        return .red
    }

    private var statusText: String {
        if bluetoothManager.isConnected { return "Connected" }
        if bluetoothManager.isScanning { return "Scanning" }
        return "Disconnected"
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

