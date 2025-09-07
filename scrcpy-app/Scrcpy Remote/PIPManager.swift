//
//  PIPManager.swift
//  Scrcpy Remote
//
//  Created by Codex on 2025-09-07.
//

import Foundation
import AVKit
import AVFoundation
import CoreMedia
import CoreVideo
import UIKit

@available(iOS 15.0, *)
@MainActor
final class PIPManager: NSObject, AVPictureInPictureControllerDelegate, AVPictureInPictureSampleBufferPlaybackDelegate {
    static let shared = PIPManager()

    private var pipController: AVPictureInPictureController?
    private var contentSource: AVPictureInPictureController.ContentSource?
    private weak var sampleBufferLayer: AVSampleBufferDisplayLayer?
    private weak var registeredTestLayer: AVSampleBufferDisplayLayer?
    
    // Fake video generator
    private var fakeTimer: DispatchSourceTimer?
    private var fakePTS: CMTime = .zero
    private let fakeFPS: Double = 15.0
    private var fakeFormatDescription: CMVideoFormatDescription?

    private override init() { 
        super.init()
        setupAudioSession()
    }
    
    private func setupAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try audioSession.setActive(true)
            print("[PIP] Audio session configured for playback")
        } catch {
            print("[PIP] Failed to setup audio session: \(error)")
        }
    }

    var isSupported: Bool {
        return AVPictureInPictureController.isPictureInPictureSupported()
    }

    var isActive: Bool {
        return pipController?.isPictureInPictureActive ?? false
    }
    
    // Register a test sample buffer layer for PIP testing
    func registerTestLayer(_ layer: AVSampleBufferDisplayLayer) {
        print("[PIP] Registering test layer: \(layer)")
        registeredTestLayer = layer
        // Invalidate existing controller so it can be recreated with new layer
        invalidatePipController()
    }
    
    // Unregister the test layer
    func unregisterTestLayer() {
        print("[PIP] Unregistering test layer")
        registeredTestLayer = nil
        invalidatePipController()
    }
    
    // Invalidate the current PIP controller so it can be recreated
    private func invalidatePipController() {
        if let controller = pipController {
            if controller.isPictureInPictureActive {
                controller.stopPictureInPicture()
            }
            pipController = nil
            contentSource = nil
            sampleBufferLayer = nil
            print("[PIP] Invalidated PIP controller")
        }
    }

    // Finds the first AVSampleBufferDisplayLayer in the view hierarchy
    private func findSampleBufferLayer() -> AVSampleBufferDisplayLayer? {
        // First check if we have a registered test layer
        if let testLayer = registeredTestLayer {
            print("[PIP] Using registered test layer: \(testLayer)")
            return testLayer
        }
        
        guard let window = WindowUtil.getFrontmostWindow() else { 
            print("[PIP] No frontmost window found")
            return nil 
        }
        print("[PIP] Searching for sample buffer layer in window: \(window)")
        let result = findSampleBufferLayer(in: window.layer)
        if let layer = result {
            print("[PIP] Found sample buffer layer: \(layer)")
        } else {
            print("[PIP] No sample buffer layer found in hierarchy")
            printLayerHierarchy(window.layer, level: 0)
        }
        return result
    }

    private func findSampleBufferLayer(in layer: CALayer) -> AVSampleBufferDisplayLayer? {
        if let sbd = layer as? AVSampleBufferDisplayLayer { 
            print("[PIP] Found AVSampleBufferDisplayLayer: \(sbd)")
            return sbd 
        }
        guard let sublayers = layer.sublayers else { return nil }
        for sub in sublayers {
            if let found = findSampleBufferLayer(in: sub) { return found }
        }
        return nil
    }
    
    private func printLayerHierarchy(_ layer: CALayer, level: Int) {
        let indent = String(repeating: "  ", count: level)
        print("[PIP] \(indent)\(type(of: layer))")
        if let sublayers = layer.sublayers {
            for sub in sublayers {
                printLayerHierarchy(sub, level: level + 1)
            }
        }
    }

    func prepareIfNeeded() -> Bool {
        guard pipController == nil else { return true }
        guard let sbdLayer = findSampleBufferLayer() else {
            print("[PIP] No AVSampleBufferDisplayLayer found in hierarchy.")
            return false
        }

        let playbackDelegate = self as AVPictureInPictureSampleBufferPlaybackDelegate
        let source = AVPictureInPictureController.ContentSource(sampleBufferDisplayLayer: sbdLayer,
                                                                playbackDelegate: playbackDelegate)
        contentSource = source
        let controller = AVPictureInPictureController(contentSource: source)
        controller.delegate = self
        pipController = controller
        sampleBufferLayer = sbdLayer
        print("[PIP] Controller prepared with SampleBufferDisplayLayer.")
        
        // Test if delegate methods are being called during setup
        print("[PIP] Testing delegate methods...")
        _ = playbackDelegate.pictureInPictureControllerTimeRangeForPlayback(controller)
        _ = playbackDelegate.pictureInPictureControllerIsPlaybackPaused(controller)
        print("[PIP] Initial delegate test completed.")
        return true
    }

    func start() {
        guard UserDefaults.standard.bool(forKey: "settings.pip.enabled") else {
            print("[PIP] Disabled in settings; not starting.")
            return
        }
        guard isSupported else {
            print("[PIP] Not supported on this device.")
            return
        }
        guard prepareIfNeeded() else { 
            print("[PIP] Failed to prepare PIP controller.")
            return 
        }
        
        // Immediately check if it's possible (might work if test video is already playing)
        if pipController?.isPictureInPicturePossible == true {
            print("[PIP] Already possible! Starting immediately...")
            pipController?.startPictureInPicture()
            return
        }
        
        // If not possible, start feeding data and wait for layer to be active
        print("[PIP] Not possible yet. Starting aggressive content flow to establish layer...")
        
        // Feed multiple initial frames quickly to establish content flow
        if let layer = sampleBufferLayer {
            for i in 0..<5 {
                if let buffer = makeFakeSampleBuffer(width: 320, height: 240) {
                    layer.enqueue(buffer)
                    print("[PIP] Fed initial frame \(i+1)/5")
                }
            }
        }
        
        startFakeFrames(renderSize: nil)
        
        // Check more frequently and give it more time
        var attempts = 0
        let maxAttempts = 20  // Increased attempts
        
        func checkPipPossible() {
            attempts += 1
            print("[PIP] Attempt \(attempts)/\(maxAttempts): Checking if PIP is possible...")
            
            // Force check delegates are working
            if attempts == 1 {
                print("[PIP] Verifying delegate functionality...")
                if let controller = self.pipController {
                    let delegate = self as AVPictureInPictureSampleBufferPlaybackDelegate
                    let range = delegate.pictureInPictureControllerTimeRangeForPlayback(controller)
                    let paused = delegate.pictureInPictureControllerIsPlaybackPaused(controller)
                    print("[PIP] Delegate check - Range: \(range), Paused: \(paused)")
                }
            }
            
            if self.pipController?.isPictureInPicturePossible == true {
                print("[PIP] PIP now possible after \(attempts) attempts! Starting...")
                self.pipController?.startPictureInPicture()
                return
            }
            
            if attempts < maxAttempts {
                // Continue feeding content and check again more frequently
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {  // Reduced delay
                    checkPipPossible()
                }
            } else {
                print("[PIP] Failed to make PIP possible after \(maxAttempts) attempts.")
                print("[PIP] Final debug info:")
                if let layer = self.sampleBufferLayer {
                    print("[PIP]   - Layer: \(layer)")
                    print("[PIP]   - Layer ready: \(layer.isReadyForMoreMediaData)")
                    print("[PIP]   - Layer status: \(layer.status.rawValue)")
                    print("[PIP]   - Layer error: \(String(describing: layer.error))")
                    print("[PIP]   - Controller: \(String(describing: self.pipController))")
                    print("[PIP]   - Content source: \(String(describing: self.contentSource))")
                    print("[PIP]   - PIP supported: \(AVPictureInPictureController.isPictureInPictureSupported())")
                    print("[PIP]   - App state: \(UIApplication.shared.applicationState.rawValue)")
                    print("[PIP]   - Audio session category: \(AVAudioSession.sharedInstance().category.rawValue)")
                    print("[PIP]   - Audio session active: \(AVAudioSession.sharedInstance().isOtherAudioPlaying)")
                    
                    // Check if we can create a new controller with this layer
                    let testPlaybackDelegate = self as AVPictureInPictureSampleBufferPlaybackDelegate
                    let testSource = AVPictureInPictureController.ContentSource(sampleBufferDisplayLayer: layer, playbackDelegate: testPlaybackDelegate)
                    let testController = AVPictureInPictureController(contentSource: testSource)
                    print("[PIP]   - Test controller possible: \(testController.isPictureInPicturePossible)")
                    
                    // Try one final attempt with fresh controller
                    print("[PIP] Trying final attempt with fresh controller...")
                    self.invalidatePipController()
                    if self.prepareIfNeeded() {
                        print("[PIP]   - Fresh controller possible: \(self.pipController?.isPictureInPicturePossible ?? false)")
                    }
                }
                self.stopFakeFrames()
            }
        }
        
        // Start checking after a very short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            checkPipPossible()
        }
    }

    func stop() {
        guard let controller = pipController, controller.isPictureInPictureActive else { return }
        controller.stopPictureInPicture()
        stopFakeFrames()
    }

    // Swift-only helper to produce a frame for CMVideoDimensions variant.
    // Marked @nonobjc to avoid selector collision with the CGSize delegate method.
    @available(iOS 18.0, *)
    @nonobjc
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                    didTransitionToRenderSize newRenderSize: CMVideoDimensions) -> CMSampleBuffer? {
        let width = Int(max(Int32(1), newRenderSize.width))
        let height = Int(max(Int32(1), newRenderSize.height))
        let sample = makeFakeSampleBuffer(width: width, height: height)
        if let s = sample {
            sampleBufferLayer?.enqueue(s)
        }
        return sample
    }


    // MARK: - AVPictureInPictureSampleBufferPlaybackDelegate (required)
    @objc func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, setPlaying playing: Bool) {
        print("[PIP] Delegate: setPlaying(\(playing))")
        // The content is live-driven; no explicit play/pause control.
    }

    @objc func pictureInPictureControllerTimeRangeForPlayback(_ pictureInPictureController: AVPictureInPictureController) -> CMTimeRange {
        print("[PIP] Delegate: timeRangeForPlayback requested")
        // Live/indeterminate content.
        return CMTimeRange(start: .zero, duration: CMTime.positiveInfinity)
    }

    @objc func pictureInPictureControllerIsPlaybackPaused(_ pictureInPictureController: AVPictureInPictureController) -> Bool {
        print("[PIP] Delegate: isPlaybackPaused requested")
        // Always considered playing for live content.
        return false
    }

    @objc func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, didTransitionToRenderSize newRenderSize: CMVideoDimensions) {
        // Update fake generator resolution to match PiP render size
        let size = CGSize(width: CGFloat(newRenderSize.width), height: CGFloat(newRenderSize.height))
        startFakeFrames(renderSize: size)
    }

    @objc func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, skipByInterval skipInterval: CMTime, completion: @escaping () -> Void) {
        // Skipping not supported for live content
        completion()
    }
}

@available(iOS 15.0, *)
extension PIPManager {
    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        print("[PIP] Will start")
    }
    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        print("[PIP] Did start")
    }
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        print("[PIP] Failed to start: \(error)")
    }
    func pictureInPictureControllerWillStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        print("[PIP] Will stop")
    }
    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        print("[PIP] Did stop")
    }
}


// MARK: - Fake frames generation
@available(iOS 15.0, *)
extension PIPManager {
    private func startFakeFrames(renderSize: CGSize?) {
        guard let layer = sampleBufferLayer else {
            return
        }
        stopFakeFrames()
        fakePTS = .zero

        let width = Int((renderSize?.width ?? 240).rounded(.toNearestOrAwayFromZero))
        let height = Int((renderSize?.height ?? 160).rounded(.toNearestOrAwayFromZero))

        // Prepare format description lazily per size
        fakeFormatDescription = nil

        // Create timer
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "pip.fake.frames"))
        let interval = DispatchTimeInterval.milliseconds(Int(1000.0 / fakeFPS))
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self, weak layer] in
            guard let self = self, let layer = layer else { return }
            if let sample = self.makeFakeSampleBuffer(width: width, height: height) {
                layer.enqueue(sample)
            }
        }
        fakeTimer = timer
        timer.resume()
    }

    private func stopFakeFrames() {
        fakeTimer?.cancel()
        fakeTimer = nil
    }

    private func makeFakeSampleBuffer(width: Int, height: Int) -> CMSampleBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary
        ]
        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pixelBuffer)
        guard status == kCVReturnSuccess, let pb = pixelBuffer else { 
            print("[PIP] Failed to create pixel buffer: \(status)")
            return nil 
        }

        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }
        
        if let base = CVPixelBufferGetBaseAddress(pb) {
            let bytesPerRow = CVPixelBufferGetBytesPerRow(pb)
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
            if let ctx = CGContext(data: base,
                                   width: width,
                                   height: height,
                                   bitsPerComponent: 8,
                                   bytesPerRow: bytesPerRow,
                                   space: colorSpace,
                                   bitmapInfo: bitmapInfo) {
                // Background color animates slightly so we see motion
                let t = CGFloat(CMTimeGetSeconds(fakePTS))
                let r = (sin(t) * 0.3 + 0.4)
                let g = (sin(t * 0.7) * 0.3 + 0.4)
                let b = (sin(t * 1.3) * 0.3 + 0.4)
                ctx.setFillColor(red: r, green: g, blue: b, alpha: 1.0)
                ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

                // Draw centered text "PIP Test"
                UIGraphicsPushContext(ctx)
                let frameNum = Int(CMTimeGetSeconds(fakePTS) * fakeFPS)
                let text = "PIP Test\nFrame: \(frameNum)" as NSString
                let fontSize = min(CGFloat(height) * 0.15, 20)
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
        if fakeFormatDescription == nil {
            var desc: CMVideoFormatDescription?
            let r = CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pb, formatDescriptionOut: &desc)
            if r != noErr || desc == nil {
                print("[PIP] Failed to create format description: \(r)")
                return nil
            }
            fakeFormatDescription = desc
        }

        guard let desc = fakeFormatDescription else { return nil }

        let ts: CMTimeScale = CMTimeScale(Int32(fakeFPS))
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: ts),
            presentationTimeStamp: fakePTS,
            decodeTimeStamp: .invalid
        )
        
        var sample: CMSampleBuffer?
        let cr = CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault, 
            imageBuffer: pb, 
            formatDescription: desc, 
            sampleTiming: &timing, 
            sampleBufferOut: &sample
        )
        
        if cr != noErr {
            print("[PIP] Failed to create sample buffer: \(cr)")
            return nil
        }

        // Advance PTS
        fakePTS = CMTimeAdd(fakePTS, CMTime(value: 1, timescale: ts))
        return sample
    }
}

// (CMVideoDimensions variant implemented in main class above.)
