//
//  CameraManager.swift
//  project-2
//
//  Created by Lucius Scala on 4/17/26.
//

import AVFoundation
import Combine

class CameraManager: NSObject,ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    
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
            let output = AVCaptureVideoDataOutput()
            
            guard self.captureSession.canAddInput(input) else { return }
            self.captureSession.addInput(input)
            
            guard self.captureSession.canAddOutput(output) else { return }
            self.captureSession.addOutput(output)
            
            output.setSampleBufferDelegate(self, queue: DispatchQueue.global(qos: .userInitiated)) //set the delegate to be CameraManager and run on backround thread
            
            self.captureSession.commitConfiguration()
            
            self.captureSession.startRunning()
            
        }
    }
    
    //nonisolated means any thread can call. In newer swift, it is assumed that the function is tied to the main actor (CameraManager, which runs on main thread), but is being called on a backround thread.
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        print("frame received")
    }

    
    
    
    
    
    
    
}
