import AVFoundation
import Vision

/// Front-camera hand tracking with Apple Vision. Frames are processed in memory only;
/// nothing is recorded or uploaded.
final class HandTracker: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    enum Status: Equatable { case idle, unauthorized, unavailable, running }

    /// Landmarks in Vision's normalized, top-left-origin space, for drawing the overlay.
    struct OverlayPoints: Equatable {
        var points: [CGPoint]
        var imageSize: CGSize
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var overlay: OverlayPoints?

    let session = AVCaptureSession()
    /// Called on the main queue for every frame with a confidently detected hand.
    var onSample: ((HandSample) -> Void)?

    private let queue = DispatchQueue(label: "app.parkicheck.hand-tracking")
    private var configured = false
    private let request: VNDetectHumanHandPoseRequest = {
        let r = VNDetectHumanHandPoseRequest()
        r.maximumHandCount = 1
        return r
    }()

    func start() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else { return await setStatus(.unauthorized) }
        default:
            return await setStatus(.unauthorized)
        }
        guard configureIfNeeded() else { return await setStatus(.unavailable) }
        queue.async { [session] in session.startRunning() }
        await setStatus(.running)
    }

    func stop() {
        queue.async { [session] in session.stopRunning() }
        DispatchQueue.main.async { self.overlay = nil; if self.status == .running { self.status = .idle } }
    }

    @MainActor private func setStatus(_ s: Status) { status = s }

    private func configureIfNeeded() -> Bool {
        if configured { return true }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: device) else { return false }
        session.beginConfiguration()
        session.sessionPreset = .high
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddInput(input), session.canAddOutput(output) else {
            session.commitConfiguration()
            return false
        }
        session.addInput(input)
        session.addOutput(output)
        if let connection = output.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
            if connection.isVideoMirroringSupported { connection.isVideoMirrored = true }
        }
        session.commitConfiguration()
        configured = true
        return true
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let size = CGSize(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
        try? handler.perform([request])

        guard let observation = request.results?.first,
              let all = try? observation.recognizedPoints(.all),
              let thumb = all[.thumbTip], let index = all[.indexTip],
              let wrist = all[.wrist], let middleMCP = all[.middleMCP],
              [thumb, index, wrist, middleMCP].allSatisfy({ $0.confidence > 0.3 }) else {
            DispatchQueue.main.async { self.overlay = nil }
            return
        }

        // Vision uses a bottom-left origin; flip to top-left and scale to pixels for distances.
        func normalized(_ p: VNRecognizedPoint) -> CGPoint { CGPoint(x: p.location.x, y: 1 - p.location.y) }
        func pixels(_ p: VNRecognizedPoint) -> CGPoint {
            let n = normalized(p)
            return CGPoint(x: n.x * size.width, y: n.y * size.height)
        }

        let sample = HandSample(timestamp: timestamp, thumbTip: pixels(thumb), indexTip: pixels(index),
                                wrist: pixels(wrist), middleMCP: pixels(middleMCP))
        let overlay = OverlayPoints(points: all.values.filter { $0.confidence > 0.3 }.map(normalized), imageSize: size)
        DispatchQueue.main.async {
            self.overlay = overlay
            self.onSample?(sample)
        }
    }
}
