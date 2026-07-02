//
//  ContentView.swift
//  project-2
//
//  Created by Lucius Scala on 4/1/26.
//

import SwiftUI

struct ContentView: View {
    
    @StateObject var cameraManager = CameraManager()
    
    
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
                        cameraManager.configuration()
                    }
                
                // Record button
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
                    .padding(.bottom, 40)
                }
            }
        }
        .ignoresSafeArea()
    }
}

// iOS Camera-style record button
struct RecordButton: View {
    let isRecording: Bool
    
    var body: some View {
        ZStack {
            // Outer white ring
            Circle()
                .stroke(Color.white, lineWidth: 4)
                .frame(width: 70, height: 70)
            
            // Inner shape: circle when idle, rounded square when recording
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

#Preview {
    ContentView()
}
