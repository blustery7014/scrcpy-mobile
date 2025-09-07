//
//  PIPDebugView.swift
//  Scrcpy Remote
//
//  Created by Codex on 2025-09-07.
//

import SwiftUI
import AVKit
import AVFoundation
import CoreMedia

// Simple video player view for testing PIP functionality
struct TestVideoPlayer: UIViewRepresentable {
    @Binding var isPlaying: Bool
    
    class Coordinator: NSObject {
        var timer: Timer?
        var frameCount: Int = 0
        var formatDescription: CMVideoFormatDescription?
        
        func startVideoGeneration(layer: AVSampleBufferDisplayLayer, isPlaying: Binding<Bool>) {
            stopVideoGeneration()
            frameCount = 0
            
            timer = Timer.scheduledTimer(withTimeInterval: 1.0/15.0, repeats: true) { [weak self] timer in
                guard let self = self, isPlaying.wrappedValue else {
                    timer.invalidate()
                    return
                }
                
                if let sampleBuffer = self.createTestFrame() {
                    layer.enqueue(sampleBuffer)
                }
                self.frameCount += 1
            }
        }
        
        func stopVideoGeneration() {
            timer?.invalidate()
            timer = nil
        }
        
        func createTestFrame() -> CMSampleBuffer? {
            let width = 320
            let height = 240
            
            var pixelBuffer: CVPixelBuffer?
            let attrs: [CFString: Any] = [
                kCVPixelBufferCGImageCompatibilityKey: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey: true,
                kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary
            ]
            
            let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pixelBuffer)
            guard status == kCVReturnSuccess, let pb = pixelBuffer else { 
                print("Failed to create pixel buffer: \(status)")
                return nil 
            }
            
            CVPixelBufferLockBaseAddress(pb, [])
            defer { CVPixelBufferUnlockBaseAddress(pb, []) }
            
            if let base = CVPixelBufferGetBaseAddress(pb) {
                let bytesPerRow = CVPixelBufferGetBytesPerRow(pb)
                let colorSpace = CGColorSpaceCreateDeviceRGB()
                let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
                
                if let ctx = CGContext(data: base, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo) {
                    
                    // Animated background
                    let time = Double(frameCount) / 15.0 // Use frame count for smoother animation
                    let r = (sin(time) * 0.3 + 0.4)
                    let g = (sin(time * 0.7) * 0.3 + 0.4) 
                    let b = (sin(time * 1.3) * 0.3 + 0.4)
                    ctx.setFillColor(red: r, green: g, blue: b, alpha: 1.0)
                    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
                    
                    // Draw test text
                    UIGraphicsPushContext(ctx)
                    let text = "Test Video\nFrame: \(frameCount)" as NSString
                    let fontSize: CGFloat = 20
                    let attrs: [NSAttributedString.Key: Any] = [
                        .font: UIFont.boldSystemFont(ofSize: fontSize),
                        .foregroundColor: UIColor.white,
                        .paragraphStyle: {
                            let style = NSMutableParagraphStyle()
                            style.alignment = .center
                            return style
                        }()
                    ]
                    let textSize = text.size(withAttributes: attrs)
                    let rect = CGRect(
                        x: CGFloat(width) * 0.5 - textSize.width * 0.5,
                        y: CGFloat(height) * 0.5 - textSize.height * 0.5,
                        width: textSize.width,
                        height: textSize.height
                    )
                    text.draw(in: rect, withAttributes: attrs)
                    UIGraphicsPopContext()
                }
            }
            
            // Create or reuse format description
            if formatDescription == nil {
                var desc: CMVideoFormatDescription?
                let result = CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pb, formatDescriptionOut: &desc)
                guard result == noErr, let d = desc else { 
                    print("Failed to create format description: \(result)")
                    return nil 
                }
                formatDescription = d
            }
            
            guard let desc = formatDescription else { return nil }
            
            // Create sample buffer with proper timing
            let timeScale: Int32 = 15
            let pts = CMTime(value: Int64(frameCount), timescale: timeScale)
            let duration = CMTime(value: 1, timescale: timeScale)
            
            var timing = CMSampleTimingInfo(
                duration: duration,
                presentationTimeStamp: pts,
                decodeTimeStamp: .invalid
            )
            
            var sampleBuffer: CMSampleBuffer?
            let createResult = CMSampleBufferCreateReadyWithImageBuffer(
                allocator: kCFAllocatorDefault,
                imageBuffer: pb,
                formatDescription: desc,
                sampleTiming: &timing,
                sampleBufferOut: &sampleBuffer
            )
            
            guard createResult == noErr, let buffer = sampleBuffer else { 
                print("Failed to create sample buffer: \(createResult)")
                return nil 
            }
            
            return buffer
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    func makeUIView(context: Context) -> UIView {
        let containerView = UIView()
        containerView.backgroundColor = UIColor.black
        
        let sampleBufferLayer = AVSampleBufferDisplayLayer()
        sampleBufferLayer.videoGravity = .resizeAspect
        sampleBufferLayer.backgroundColor = UIColor.black.cgColor
        containerView.layer.addSublayer(sampleBufferLayer)
        
        // Register this layer with PIPManager for testing
        if #available(iOS 15.0, *) {
            PIPManager.shared.registerTestLayer(sampleBufferLayer)
        }
        
        return containerView
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        guard let sampleBufferLayer = uiView.layer.sublayers?.first(where: { $0 is AVSampleBufferDisplayLayer }) as? AVSampleBufferDisplayLayer else { return }
        
        // Update layer frame
        sampleBufferLayer.frame = uiView.bounds
        
        if isPlaying {
            context.coordinator.startVideoGeneration(layer: sampleBufferLayer, isPlaying: $isPlaying)
        } else {
            context.coordinator.stopVideoGeneration()
        }
    }
}

struct PIPDebugView: View {
    @State private var hasSampleBufferLayer: Bool = false
    @State private var supportText: String = ""
    @State private var statusText: String = ""
    @State private var isVideoPlaying: Bool = false

    private func refreshStatus() {
        if #available(iOS 15.0, *) {
            let supported = AVPictureInPictureController.isPictureInPictureSupported()
            supportText = "Supported: " + (supported ? "Yes" : "No")
            if supported {
                let found = PIPManager.shared.prepareIfNeeded()
                hasSampleBufferLayer = found
                
                if found {
                    if PIPManager.shared.isActive {
                        statusText = "PiP is currently active"
                    } else {
                        statusText = isVideoPlaying ? "Video layer ready (test video playing)" : "Video layer found"
                    }
                } else {
                    statusText = isVideoPlaying ? "Test video playing (layer should be available soon)" : "No video layer found (try playing the test video)"
                }
            } else {
                hasSampleBufferLayer = false
                statusText = "Device does not support PiP"
            }
        } else {
            supportText = "Supported: No (iOS < 15)"
            statusText = "Requires iOS 15+"
            hasSampleBufferLayer = false
        }
    }

    var body: some View {
        Form {
            Section(header: Text("状态")) {
                HStack {
                    Text(supportText)
                    Spacer()
                }
                HStack {
                    Text(statusText)
                    Spacer()
                }
            }
            
            Section(header: Text("Test Video Player")) {
                VStack(alignment: .leading, spacing: 10) {
                    TestVideoPlayer(isPlaying: $isVideoPlaying)
                        .frame(height: 180)
                        .cornerRadius(8)
                    
                    HStack {
                        Button(action: { 
                            isVideoPlaying.toggle()
                            refreshStatus()
                        }) {
                            HStack {
                                Image(systemName: isVideoPlaying ? "pause.circle" : "play.circle")
                                Text(isVideoPlaying ? "Pause Video" : "Play Video")
                            }
                        }
                        Spacer()
                    }
                }
            }
            
            Section(header: Text("自动化")) {
                if #available(iOS 15.0, *) {
                    Button(action: { PIPManager.shared.start(); refreshStatus() }) {
                        HStack {
                            Image(systemName: "play.circle")
                            Text("Start PiP")
                        }
                    }
                    .disabled(!UserDefaults.standard.bool(forKey: "settings.pip.enabled") || !isVideoPlaying)
                    
                    Button(action: { PIPManager.shared.stop(); refreshStatus() }) {
                        HStack {
                            Image(systemName: "stop.circle")
                            Text("Stop PiP")
                        }
                    }
                    
                    if !isVideoPlaying {
                        Text("⚠️ Start test video first")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                } else {
                    Text("PiP requires iOS 15+")
                }
            }
            
            Section(footer: Text("PiP uses the current video layer. Use the test player above or connect to a device to test real content.")) {
                EmptyView()
            }
        }
        .navigationBarTitle("Debug PiP", displayMode: .inline)
        .onAppear { refreshStatus() }
    }
}

