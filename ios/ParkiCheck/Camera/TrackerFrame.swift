import CoreGraphics
import Foundation

/// Landmarks for one camera frame, in image pixels with a top-left origin (y grows downward),
/// so "up" is a decrease in y, as in the web version. The image is not mirrored: left/right
/// joint names refer to the person's own left and right.
struct TrackerFrame {
    let timestamp: TimeInterval
    let imageSize: CGSize
    var hand: HandPoints?
    var body: BodyPoints?
    var face: FacePoints?
}

struct HandPoints {
    var wrist: CGPoint
    var thumbTip: CGPoint
    var indexMCP: CGPoint, middleMCP: CGPoint, ringMCP: CGPoint, littleMCP: CGPoint
    var indexTip: CGPoint, middleTip: CGPoint, ringTip: CGPoint, littleTip: CGPoint

    var handSize: Double { wrist.distance(to: middleMCP) }
    var mcps: [CGPoint] { [indexMCP, middleMCP, ringMCP, littleMCP] }
    var tips: [CGPoint] { [indexTip, middleTip, ringTip, littleTip] }
}

struct BodyPoints {
    var points: [Joint: CGPoint]

    enum Joint: String, CaseIterable {
        case nose, leftShoulder, rightShoulder, leftWrist, rightWrist
        case leftHip, rightHip, leftKnee, rightKnee, leftAnkle, rightAnkle
    }

    subscript(_ joint: Joint) -> CGPoint? { points[joint] }
}

struct FacePoints {
    var boundingBox: CGRect
    var leftEye: [CGPoint]
    var rightEye: [CGPoint]
    var leftBrow: [CGPoint]
    var rightBrow: [CGPoint]
    var innerLips: [CGPoint]
    var outerLips: [CGPoint]
}

extension CGPoint {
    func distance(to other: CGPoint) -> Double { Double(hypot(x - other.x, y - other.y)) }
    static func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
    static func mean(_ points: [CGPoint]) -> CGPoint {
        guard !points.isEmpty else { return .zero }
        let n = CGFloat(points.count)
        return CGPoint(x: points.map(\.x).reduce(0, +) / n, y: points.map(\.y).reduce(0, +) / n)
    }
}

extension Array where Element == CGPoint {
    /// Height / width of the points' bounding box (eye openness, mouth openness).
    var aspect: Double {
        guard let minX = map(\.x).min(), let maxX = map(\.x).max(),
              let minY = map(\.y).min(), let maxY = map(\.y).max(), maxX > minX else { return 0 }
        return Double((maxY - minY) / (maxX - minX))
    }

    var height: Double {
        guard let minY = map(\.y).min(), let maxY = map(\.y).max() else { return 0 }
        return Double(maxY - minY)
    }
}
