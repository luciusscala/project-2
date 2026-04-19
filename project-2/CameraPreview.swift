//
//  CameraPreview.swift
//  project-2
//
//  Created by Lucius Scala on 4/14/26.
//

import SwiftUI
import AVFoundation


struct CameraPreview: UIViewRepresentable {
    
    //add the capture session type
    let captureSession: AVCaptureSession

    class PreviewView: UIView {
        //must override the Core Animation layer because we want to be able to have a live preview of the frames.
        override class var layerClass: AnyClass {
            return AVCaptureVideoPreviewLayer.self
        }
        //computable property which provides access to the avcapture.. layer (what is animated by swift)
        var videoPreviewLayer: AVCaptureVideoPreviewLayer! {
                        
            return (layer as! AVCaptureVideoPreviewLayer)
        }
    }
    
    
    func makeUIView(context: Context) -> PreviewView {
        
        //creates the preview object with a blank frame
        let view = PreviewView(frame: CGRect.zero)
        
        //connects the preview layer to the capture session
        view.videoPreviewLayer.session = captureSession
        
        return view
    }
    
    func updateUIView(_ uiView: UIViewType, context: Context) {
    
    }
    
}

