//
//  CameraManager.swift
//  project-2
//
//  Created by Lucius Scala on 4/17/26.
//

import AVFoundation
import Combine

class CameraManager: ObservableObject {
    
    let captureSession = AVCaptureSession()
    
    func configuration() {
        
        //DispatchQueue is object that lets us add tasks to main (main) and backround (global) threads. .async means do not block thread that called it.
        //Need backround thread because we will be STARTING a capture sessino, not just initializng variables.
        DispatchQueue.global(qos: .userInitiated).async {
            //this is closure since this code could possibly be exectued after this object is deallocated, therefre we must explicitely declare use of self
            self.captureSession.beginConfiguration() //makes sure that we wait until all changes can be applied at once
            
            //guard ensures that optional type camera is either set or not we just return
            guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { return }
            guard let input = try? AVCaptureDeviceInput(device: camera) else { return } //? means make nil instead of crashing
            
            guard self.captureSession.canAddInput(input) else { return }
            self.captureSession.addInput(input)
            
            self.captureSession.commitConfiguration()
            
            self.captureSession.startRunning()
            
        }
        
    }
    
    
    
    
    
    
    
}
