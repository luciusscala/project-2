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
    private nonisolated let frameInterval = 3

    // EMA of the tracking offset, mutated only on the inference queue.
    // nil whenever no chair is being tracked.
    private nonisolated(unsafe) var smoothedOffset: Float?
    private let inferenceQueue = DispatchQueue(label: "com.project2.inference")
    
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
        
        // .up because the phone is held landscape (charging port on the right) while
        // recording, which matches the back camera's native sensor orientation.
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
        
        try? handler.perform([request])
        let allResults = request.results as? [VNRecognizedObjectObservation] ?? []

        let results = allResults.filter { obs in obs.confidence > 0.75 }

        // Track the single best chair, with a lower confidence bar than drawing:
        // the servo needs a steady stream of offsets more than confident ones.
        // Offset: negative = chair is left, positive = right; ×2 maps the
        // 0.0–0.5 half-range to a full -1.0 to +1.0.
        let target = allResults
            .filter { $0.labels.first?.identifier == "chair" && $0.confidence > 0.4 }
            .max { $0.confidence < $1.confidence }

        if let target {
            let raw = Float(target.boundingBox.midX - 0.5) * 2.0
            let smoothed = smoothedOffset.map { 0.7 * $0 + 0.3 * raw } ?? raw
            smoothedOffset = smoothed
            bluetoothManager?.sendMotorCommand(offset: smoothed)
        } else {
            // No chair in sight: stop commanding (the servo holds position) and
            // reset the filter so a stale value doesn't bias reacquisition.
            smoothedOffset = nil
        }
        
        // Swap width/height because the pixel buffer is landscape but we display portrait.
        let bufW = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let bufH = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        let imgsz = CGSize(width: bufH, height: bufW)
        
        let vsz = viewSize
        
        let boxes = results.map { obs in
            let r = obs.boundingBox
            // Vision box is in the landscape (world-upright) buffer; the portrait
            // preview shows that buffer rotated 90° CW. That rotation plus Vision's
            // bottom-left origin reduce to swapping x/y and width/height.
            let display = CGRect(x: r.minY, y: r.minX, width: r.height, height: r.width)
            return aspectFillDisplayRect(for: display, imageSize: imgsz, viewSize: vsz)
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
