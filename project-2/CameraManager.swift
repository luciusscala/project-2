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

/// Manages camera capture, YOLO object detection, and video recording.
class CameraManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    @Published var bb: [CGRect] = []
    @Published var isRecording = false

    let captureSession = AVCaptureSession()
    let movieOutput = AVCaptureMovieFileOutput()
    var bluetoothManager: BluetoothManager?
    
    /// Set from GeometryReader before calling configuration().
    var viewSize = CGSize(width: 390, height: 844)
    
    private var visionRequest: VNCoreMLRequest?
    private var delegate: MovieCaptureDelegate?
    private var isConfigured = false
    
    // nonisolated(unsafe) because this is mutated on the inference queue,
    // not the main actor. Safe here since only captureOutput touches it.
    private nonisolated(unsafe) var frameCount = 0
    private nonisolated let frameInterval = 10
    private let inferenceQueue = DispatchQueue(label: "com.project2.inference")
    
    override init() {
        super.init()

        guard let model = try? best(configuration: MLModelConfiguration()),
              let vnModel = try? VNCoreMLModel(for: model.model) else {
            fatalError("Failed to load model")
        }

        let request = VNCoreMLRequest(model: vnModel)
        request.imageCropAndScaleOption = .scaleFit
        self.visionRequest = request
    }
    
    // MARK: - Camera Setup
    
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
    
    // MARK: - Recording
    
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
    
    // MARK: - Frame Processing
    
    // nonisolated: this delegate method is called on the inference queue, not the main actor.
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
        
        // Send motor offset to ESP32: negative = ball is left, positive = right.
        // Multiplied by 2 to map the 0.0–0.5 half-range to a full -1.0 to +1.0.
        for obs in results {
            if let topLabel = obs.labels.first, topLabel.identifier == "ball" {
                let centerX = obs.boundingBox.midX
                let offset = Float(centerX - 0.5) * 2.0
                bluetoothManager?.sendMotorCommand(offset: offset)
            }
        }
        
        // Swap width/height because the pixel buffer is landscape but we display portrait.
        let bufW = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let bufH = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        let imgsz = CGSize(width: bufH, height: bufW)
        
        let vsz = viewSize
        
        let boxes = results.map { rect in
            aspectFillDisplayRect(for: flipped(rect.boundingBox), imageSize: imgsz, viewSize: vsz)
        }
        Task { @MainActor in self.bb = boxes }
    }
    
    // MARK: - Coordinate Mapping
    
    /// Converts a normalized Vision rect to display coordinates, accounting for aspect-fill scaling.
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
    
    /// Flips a normalized rect's Y axis (Vision uses bottom-left origin, UIKit uses top-left).
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
        
        UISaveVideoAtPathToSavedPhotosAlbum(outputFileURL.path, nil, nil, nil)
        onFinish()
    }
}
