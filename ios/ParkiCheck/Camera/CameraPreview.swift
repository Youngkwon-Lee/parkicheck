import AVFoundation
import SwiftUI

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

/// Draws landmarks over an aspect-fill preview.
struct HandOverlay: View {
    let overlay: HandTracker.OverlayPoints?

    var body: some View {
        Canvas { context, size in
            guard let overlay, overlay.imageSize.width > 0, overlay.imageSize.height > 0 else { return }
            let scale = max(size.width / overlay.imageSize.width, size.height / overlay.imageSize.height)
            let drawn = CGSize(width: overlay.imageSize.width * scale, height: overlay.imageSize.height * scale)
            let origin = CGPoint(x: (size.width - drawn.width) / 2, y: (size.height - drawn.height) / 2)
            for p in overlay.points {
                let center = CGPoint(x: origin.x + p.x * drawn.width, y: origin.y + p.y * drawn.height)
                context.fill(Path(ellipseIn: CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8)),
                             with: .color(.accentColor))
            }
        }
        .allowsHitTesting(false)
    }
}
