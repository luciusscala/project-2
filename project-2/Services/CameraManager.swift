
import AVFoundation
import Combine

/// Manages the AVCaptureSession lifecycle and video recording.
/// Delegates per-frame ML processing to FrameProcessor and video storage to VideoLibrary.
final class CameraManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {

    @Published var bb: [CGRect] = []
    @Published var isRecording = false
    @Published var showBoundingBoxes = true
    @Published var isPreviewEnabled = true
    @Published var scheduledRecordingDate: Date? = nil

    let captureSession = AVCaptureSession()
    
    // TODO: make viewSize adaptable to different screen sizes, fixed for now is fine
    var viewSize = CGSize(width: 390, height: 844) {
        didSet { frameProcessor.viewSize = viewSize }
    }

    var bluetoothManager: BluetoothManager? {
        didSet { frameProcessor.bluetoothManager = bluetoothManager }
    }

    private let movieOutput = AVCaptureMovieFileOutput()
    private let inferenceQueue = DispatchQueue(label: "com.project2.inference")

    // nonisolated(unsafe): accessed from the nonisolated captureOutput delegate,
    // always on the inference queue. Safe because process() is only ever called there.
    private nonisolated(unsafe) let frameProcessor: FrameProcessor

    private let videoLibrary: VideoLibrary
    private var captureDelegate: MovieCaptureDelegate?
    private var isConfigured = false
    private var scheduledTimer: Timer?

    init(videoLibrary: VideoLibrary) {
        self.videoLibrary = videoLibrary
        do {
            frameProcessor = try FrameProcessor()
        } catch {
            fatalError("Failed to load YOLO model: \(error)")
        }
        super.init()

        frameProcessor.onBoxesUpdated = { [weak self] boxes in
            guard let self else { return }
            Task { @MainActor in self.bb = boxes }
        }
    }

    // MARK: - Camera Setup

    func configuration() {
        guard !isConfigured else { return }
        isConfigured = true

        DispatchQueue.global(qos: .userInitiated).async {
            self.captureSession.beginConfiguration()

            guard let camera = AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back),
                  let videoInput = try? AVCaptureDeviceInput(device: camera) else { return }

            let output = AVCaptureVideoDataOutput()
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]

            guard self.captureSession.canAddInput(videoInput) else { return }
            self.captureSession.addInput(videoInput)

            if let mic = AVCaptureDevice.default(for: .audio),
               let audioInput = try? AVCaptureDeviceInput(device: mic),
               self.captureSession.canAddInput(audioInput) {
                self.captureSession.addInput(audioInput)
            }

            guard self.captureSession.canAddOutput(output),
                  self.captureSession.canAddOutput(self.movieOutput) else { return }
            self.captureSession.addOutput(output)
            self.captureSession.addOutput(self.movieOutput)

            output.setSampleBufferDelegate(self, queue: self.inferenceQueue)

            self.captureSession.commitConfiguration()
            self.captureSession.startRunning()
        }
    }

    // MARK: - Recording

    func scheduleRecording(at date: Date) {
        scheduledTimer?.invalidate()
        let interval = date.timeIntervalSinceNow
        guard interval > 0 else { return }
        scheduledRecordingDate = date
        scheduledTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.scheduledRecordingDate = nil
                self?.startRecording()
            }
        }
    }

    func cancelScheduledRecording() {
        scheduledTimer?.invalidate()
        scheduledTimer = nil
        scheduledRecordingDate = nil
    }

    func startRecording() {
        cancelScheduledRecording()
        guard !movieOutput.isRecording else { return }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")

        captureDelegate = MovieCaptureDelegate(
            videoLibrary: videoLibrary,
            startTime: .now,
            onFinish: { [weak self] in
                DispatchQueue.main.async { self?.isRecording = false }
            }
        )
        movieOutput.startRecording(to: url, recordingDelegate: captureDelegate!)
        isRecording = true
    }

    func stopRecording() {
        guard movieOutput.isRecording else { return }
        movieOutput.stopRecording()
    }

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        frameProcessor.process(sampleBuffer)
    }
}

// MARK: - MovieCaptureDelegate

/// Handles recording completion: moves the file to persistent storage via VideoLibrary.
private final class MovieCaptureDelegate: NSObject, AVCaptureFileOutputRecordingDelegate {

    private let videoLibrary: VideoLibrary
    private let startTime: Date
    private let onFinish: () -> Void

    init(videoLibrary: VideoLibrary, startTime: Date, onFinish: @escaping () -> Void) {
        self.videoLibrary = videoLibrary
        self.startTime = startTime
        self.onFinish = onFinish
    }

    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: (any Error)?) {
        defer { onFinish() }

        if let error {
            print("Recording error: \(error.localizedDescription)")
            return
        }

        videoLibrary.save(tempURL: outputFileURL, duration: Date.now.timeIntervalSince(startTime))
    }
}
