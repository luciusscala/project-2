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
        ZStack {
            Color.black
            
            CameraPreview(captureSession: cameraManager.captureSession)
                .ignoresSafeArea()
        }
        .onAppear {
            cameraManager.configuration()
        }
    }
}

#Preview {
    ContentView()
}
