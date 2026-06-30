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
        GeometryReader{ geometry in
            ZStack {
                Color.black
                
                CameraPreview(captureSession: cameraManager.captureSession)
                    .ignoresSafeArea()
                    .overlay {
                        Path { path in
                            for box in cameraManager.bb {
                                path.addRect(box)
                            }
                        }
                        .stroke(.red, lineWidth: 2)
                    }
                    .onAppear {
                        cameraManager.configuration()
                        print("viewsize: \(geometry.size)")
                    }
            }
        }
    }
}

#Preview {
    ContentView()
}
