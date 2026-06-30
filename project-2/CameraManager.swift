//
//  CameraManager.swift
//  project-2
//
//  Created by Lucius Scala on 4/17/26.
//

import AVFoundation
import Combine
import CoreML
import Vision

class CameraManager: NSObject,ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    @Published var bb: [CGRect] = [.zero]

    let captureSession = AVCaptureSession()
    private var visionRequest: VNCoreMLRequest?
    
    override init() {
            super.init()

            guard let model = try? yolo26s(configuration: MLModelConfiguration()),
                  let vnModel = try? VNCoreMLModel(for: model.model) else {
                fatalError("Failed to load model")
            }

            let request = VNCoreMLRequest(model: vnModel)
            request.imageCropAndScaleOption = .scaleFill
            self.visionRequest = request
        
        }

    
    private nonisolated(unsafe) var frameCount = 0
    private nonisolated let frameInterval = 30
    
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
            output.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            
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
        frameCount += 1
        if (frameCount % frameInterval != 0) { return }
        
        frameCount = 0
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        guard let request = visionRequest else { return }
        
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right)
        
      
        try? handler.perform([request])
        var results = request.results as? [VNRecognizedObjectObservation] ?? []
        
        results = results.filter{ obs in obs.confidence > 0.75 }
        
        let vsz = CGSize(width: 390, height: 763)
        let imgsz = CGSize(width: 1080, height: 1920)
        
        let boxes = results.map { rect in
            aspectFillDisplayRect(for: flipped(rect.boundingBox), imageSize: imgsz, viewSize: vsz)
        }
        Task { @MainActor in self.bb = boxes }
        
    }
    
    func aspectFillDisplayRect(for normalizedRect: CGRect, imageSize: CGSize, viewSize: CGSize)
      -> CGRect
    {
      guard imageSize.width > 0, imageSize.height > 0, viewSize.width > 0, viewSize.height > 0 else {
        return .zero
      }
      let scale = max(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
      let scaledImageSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
      let offset = CGPoint(
        x: (scaledImageSize.width - viewSize.width) / 2,
        y: (scaledImageSize.height - viewSize.height) / 2
      )
      return CGRect(
        x: normalizedRect.minX * imageSize.width * scale - offset.x,
        y: normalizedRect.minY * imageSize.height * scale - offset.y,
        width: normalizedRect.width * imageSize.width * scale,
        height: normalizedRect.height * imageSize.height * scale
      )
    }
    
    func flipped(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: 1 - rect.maxY, width: rect.width, height: rect.height)
    }
    
}
