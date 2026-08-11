//
//  CameraPreview.swift
//  project-2
//
//  Created by Lucius Scala on 4/14/26.
//

import SwiftUI
import AVFoundation

/// Bridges AVCaptureVideoPreviewLayer into SwiftUI via UIViewRepresentable.
struct CameraPreview: UIViewRepresentable {
    
    let captureSession: AVCaptureSession

    class PreviewView: UIView {
        // Override the backing layer to be a video preview layer instead of a plain CALayer.
        override class var layerClass: AnyClass {
            return AVCaptureVideoPreviewLayer.self
        }
        
        var videoPreviewLayer: AVCaptureVideoPreviewLayer! {
            return (layer as! AVCaptureVideoPreviewLayer)
        }
    }
    
    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView(frame: CGRect.zero)
        view.videoPreviewLayer.session = captureSession
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }
    
    func updateUIView(_ uiView: UIViewType, context: Context) {}
}
