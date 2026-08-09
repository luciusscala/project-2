
import AVFoundation
import CoreML
import UIKit
import Vision

/// Processes camera frames: runs YOLO inference, tracks targets for Bluetooth control,
/// and converts detections to display-space bounding boxes.
///
/// All methods must be called exclusively from the same serial queue (the inference queue).
final class FrameProcessor {
    
    // TODO: do not recalculate viewsize, should be calculated in camera manager or here not both
    var viewSize = CGSize(width: 390, height: 844)
    weak var bluetoothManager: BluetoothManager?

    /// Called on the inference queue with updated bounding boxes after each processed frame.
    var onBoxesUpdated: (([CGRect]) -> Void)?

    private let request: VNCoreMLRequest
    private var frameCount = 0
    private let frameInterval = 3
    private var smoothedOffset: Float?

    init() throws {
        let model = try yolo26s(configuration: MLModelConfiguration())
        let vnModel = try VNCoreMLModel(for: model.model)
        request = VNCoreMLRequest(model: vnModel)
        request.imageCropAndScaleOption = .scaleFit
    }

    /// Process a single camera frame. Must be called from the inference queue.
    func process(_ sampleBuffer: CMSampleBuffer) {
        frameCount += 1
        guard frameCount % frameInterval == 0 else { return }
        frameCount = 0

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
        try? handler.perform([request])

        let allResults = request.results as? [VNRecognizedObjectObservation] ?? []
        let visible = allResults.filter { $0.confidence > 0.75 } // TODO: look at confidence again later, make sure not too high

        updateTracking(from: allResults)

        // Swap width/height: the pixel buffer is landscape but the preview displays portrait.
        let imageSize = CGSize(
            width: CGFloat(CVPixelBufferGetHeight(pixelBuffer)),
            height: CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        )
        let vs = viewSize

        let boxes = visible.map { obs -> CGRect in
            let r = obs.boundingBox
            // Vision box is landscape (world-upright); portrait preview rotates it 90° CW.
            // That rotation plus Vision's bottom-left origin reduces to swapping x/y and w/h.
            let display = CGRect(x: r.minY, y: r.minX, width: r.height, height: r.width)
            return aspectFillRect(for: display, imageSize: imageSize, viewSize: vs)
        }

        onBoxesUpdated?(boxes)
    }

    // MARK: - Private
    // TODO: should be simpler when it's just ball but should also just reslove multiple detections
    private func updateTracking(from results: [VNRecognizedObjectObservation]) {
        let target = results
            .filter { $0.labels.first?.identifier == "person" && $0.confidence > 0.4 }
            .max { $0.confidence < $1.confidence }

        if let target {
            let raw = Float(target.boundingBox.midX - 0.5) * 2.0
            smoothedOffset = smoothedOffset.map { 0.7 * $0 + 0.3 * raw } ?? raw
            bluetoothManager?.sendMotorCommand(offset: smoothedOffset!)
        } else {
            smoothedOffset = nil
        }
    }

    /// Converts a normalized Vision rect to display coordinates accounting for aspect-fill scaling.
    private func aspectFillRect(for normalizedRect: CGRect, imageSize: CGSize, viewSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0,
              viewSize.width > 0, viewSize.height > 0 else { return .zero }
        let scale = max(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
        let scaledSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let offset = CGPoint(
            x: (scaledSize.width - viewSize.width) / 2,
            y: (scaledSize.height - viewSize.height) / 2
        )
        return CGRect(
            x: normalizedRect.minX * imageSize.width * scale - offset.x,
            y: normalizedRect.minY * imageSize.height * scale - offset.y,
            width: normalizedRect.width * imageSize.width * scale,
            height: normalizedRect.height * imageSize.height * scale
        )
    }
}
