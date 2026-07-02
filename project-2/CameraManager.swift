//
//  CameraManager.swift
//  project-2
//
//  Created by Lucius Scala on 4/17/26.
//

import AVFoundation
import Combine
import CoreML
import UIKit
import Vision

class CameraManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    @Published var bb: [CGRect] = []
    @Published var isRecording = false

    let captureSession = AVCaptureSession()
    private var visionRequest: VNCoreMLRequest?
    let movieOutput = AVCaptureMovieFileOutput()
    private var delegate: MovieCaptureDelegate?
    
    // The actual view size, set from GeometryReader before configuration
    var viewSize = CGSize(width: 390, height: 844)
    
    private var isConfigured = false
    
    override init() {
            super.init()

            guard let model = try? yolo26s(configuration: MLModelConfiguration()),
                  let vnModel = try? VNCoreMLModel(for: model.model) else {
                fatalError("Failed to load model")
            }

            let request = VNCoreMLRequest(model: vnModel)
            request.imageCropAndScaleOption = .scaleFit
            self.visionRequest = request
        }

    
    private nonisolated(unsafe) var frameCount = 0
    private nonisolated let frameInterval = 30
    private let inferenceQueue = DispatchQueue(label: "com.project2.inference")
    
    func configuration() {
        guard !isConfigured else { return }
        isConfigured = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            self.captureSession.beginConfiguration()
            
            guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { return }
            guard let videoInput = try? AVCaptureDeviceInput(device: camera) else { return }
            
            let output = AVCaptureVideoDataOutput()
            output.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            
            guard self.captureSession.canAddInput(videoInput) else { return }
            self.captureSession.addInput(videoInput)
            
            // Add microphone for audio in recordings
            if let mic = AVCaptureDevice.default(for: .audio),
               let audioInput = try? AVCaptureDeviceInput(device: mic),
               self.captureSession.canAddInput(audioInput) {
                self.captureSession.addInput(audioInput)
            }
            
            guard self.captureSession.canAddOutput(output) else { return }
            guard self.captureSession.canAddOutput(self.movieOutput) else { return }
            self.captureSession.addOutput(output)
            self.captureSession.addOutput(self.movieOutput)
            
            output.setSampleBufferDelegate(self, queue: self.inferenceQueue)
            
            self.captureSession.commitConfiguration()
            self.captureSession.startRunning()
        }
    }
    
    func startRecording() {
        guard !movieOutput.isRecording else { return }
        
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")
        
        delegate = MovieCaptureDelegate { [weak self] in
            DispatchQueue.main.async { self?.isRecording = false }
        }
        movieOutput.startRecording(to: url, recordingDelegate: delegate!)
        isRecording = true
    }
    
    func stopRecording() {
        guard movieOutput.isRecording else { return }
        movieOutput.stopRecording()
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
        
        results = results.filter { obs in obs.confidence > 0.75 }
        
        // Read actual pixel buffer dimensions (native landscape orientation)
        // and swap to portrait since we use orientation: .right
        let bufW = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let bufH = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        let imgsz = CGSize(width: bufH, height: bufW)
        
        let vsz = viewSize
        
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

// MARK: - Movie Capture Delegate

class MovieCaptureDelegate: NSObject, AVCaptureFileOutputRecordingDelegate {
    
    private let onFinish: () -> Void
    
    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }
    
    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: (any Error)?) {
        if let error {
            print("Recording error: \(error.localizedDescription)")
            onFinish()
            return
        }
        
        // Save to the photo library
        UISaveVideoAtPathToSavedPhotosAlbum(outputFileURL.path, nil, nil, nil)
        print("Video saved to photo library")
        onFinish()
    }
}
