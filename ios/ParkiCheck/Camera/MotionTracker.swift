import AVFoundation
import Vision

/// Front-camera landmark tracking with Apple Vision (hand, body or face).
/// Frames are processed in memory only; nothing is recorded or uploaded.
///
/// The analysis buffer is rotated to portrait and NOT mirrored, so Vision's left/right joint
/// names are the person's own sides. The preview layer mirrors itself like a selfie camera,
/// and `HandOverlay` mirrors the points to match it.
final class MotionTracker: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    enum Status: Equatable { case idle, unauthorized, unavailable, running }

    struct Overlay: Equatable {
        var points: [CGPoint]   // normalized, top-left origin, unmirrored
        var imageSize: CGSize
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var overlay: Overlay?

    let session = AVCaptureSession()
    let tracking: TaskKind.Tracking
    /// Called on the main queue once per camera frame in which the target was found.
    var onFrame: ((TrackerFrame) -> Void)?

    private let queue = DispatchQueue(label: "app.parkicheck.motion-tracking")
    private var configured = false
    private let handRequest: VNDetectHumanHandPoseRequest = {
        let r = VNDetectHumanHandPoseRequest()
        r.maximumHandCount = 1
        return r
    }()
    private let bodyRequest = VNDetectHumanBodyPoseRequest()
    private let faceRequest = VNDetectFaceLandmarksRequest()

    init(tracking: TaskKind.Tracking) {
        self.tracking = tracking
    }

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
        DispatchQueue.main.async {
            self.overlay = nil
            if self.status == .running { self.status = .idle }
        }
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
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = false
            }
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

        var frame = TrackerFrame(timestamp: timestamp, imageSize: size)
        var overlayPoints: [CGPoint] = []

        func pixel(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * size.width, y: (1 - p.y) * size.height) }
        func normalized(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x, y: 1 - p.y) }

        switch tracking {
        case .hand:
            try? handler.perform([handRequest])
            if let obs = handRequest.results?.first, let all = try? obs.recognizedPoints(.all) {
                func pt(_ j: VNHumanHandPoseObservation.JointName) -> CGPoint? {
                    guard let p = all[j], p.confidence > 0.3 else { return nil }
                    return pixel(p.location)
                }
                if let wrist = pt(.wrist), let thumb = pt(.thumbTip),
                   let iM = pt(.indexMCP), let mM = pt(.middleMCP), let rM = pt(.ringMCP), let lM = pt(.littleMCP),
                   let iT = pt(.indexTip), let mT = pt(.middleTip), let rT = pt(.ringTip), let lT = pt(.littleTip) {
                    frame.hand = HandPoints(wrist: wrist, thumbTip: thumb, indexMCP: iM, middleMCP: mM, ringMCP: rM, littleMCP: lM,
                                            indexTip: iT, middleTip: mT, ringTip: rT, littleTip: lT)
                }
                overlayPoints = all.values.filter { $0.confidence > 0.3 }.map { normalized($0.location) }
            }
        case .body:
            try? handler.perform([bodyRequest])
            if let obs = bodyRequest.results?.first, let all = try? obs.recognizedPoints(.all) {
                let map: [BodyPoints.Joint: VNHumanBodyPoseObservation.JointName] = [
                    .nose: .nose, .leftShoulder: .leftShoulder, .rightShoulder: .rightShoulder,
                    .leftWrist: .leftWrist, .rightWrist: .rightWrist, .leftHip: .leftHip, .rightHip: .rightHip,
                    .leftKnee: .leftKnee, .rightKnee: .rightKnee, .leftAnkle: .leftAnkle, .rightAnkle: .rightAnkle,
                ]
                var points: [BodyPoints.Joint: CGPoint] = [:]
                for (joint, name) in map {
                    if let p = all[name], p.confidence > 0.3 { points[joint] = pixel(p.location) }
                }
                if !points.isEmpty { frame.body = BodyPoints(points: points) }
                overlayPoints = all.values.filter { $0.confidence > 0.3 }.map { normalized($0.location) }
            }
        case .face:
            try? handler.perform([faceRequest])
            if let obs = faceRequest.results?.first, let lm = obs.landmarks,
               let le = lm.leftEye, let re = lm.rightEye, let lb = lm.leftEyebrow, let rb = lm.rightEyebrow,
               let il = lm.innerLips, let ol = lm.outerLips {
                func img(_ region: VNFaceLandmarkRegion2D) -> [CGPoint] {
                    region.pointsInImage(imageSize: size).map { CGPoint(x: $0.x, y: size.height - $0.y) }
                }
                let box = obs.boundingBox
                let rect = CGRect(x: box.minX * size.width, y: (1 - box.maxY) * size.height,
                                  width: box.width * size.width, height: box.height * size.height)
                frame.face = FacePoints(boundingBox: rect, leftEye: img(le), rightEye: img(re), leftBrow: img(lb),
                                        rightBrow: img(rb), innerLips: img(il), outerLips: img(ol))
                overlayPoints = (lm.allPoints.map(img) ?? []).map { CGPoint(x: $0.x / size.width, y: $0.y / size.height) }
            }
        }

        let found = frame.hand != nil || frame.body != nil || frame.face != nil
        let overlay = overlayPoints.isEmpty ? nil : Overlay(points: overlayPoints, imageSize: size)
        DispatchQueue.main.async {
            self.overlay = overlay
            if found { self.onFrame?(frame) }
        }
    }
}
