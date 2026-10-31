import Foundation
import ScreenCaptureKit
import CoreMedia
import CoreVideo

public protocol ScreenCaptureEngineDelegate: AnyObject {
    func captureEngine(_ engine: ScreenCaptureEngine, didCaptureSampleBuffer sampleBuffer: CMSampleBuffer)
    func captureEngine(_ engine: ScreenCaptureEngine, didCaptureAudioData data: Data, pts: CMTime)
}

public final class ScreenCaptureEngine: NSObject, SCStreamOutput, SCStreamDelegate {
    public weak var delegate: ScreenCaptureEngineDelegate?
    
    private var stream: SCStream?
    private let videoQueue = DispatchQueue(label: "com.displaymac.capture.video", qos: .userInteractive)
    private let audioQueue = DispatchQueue(label: "com.displaymac.capture.audio", qos: .userInteractive)
    private var isRunning: Bool = false
    
    public func startCapture(displayID: CGDirectDisplayID, width: Int, height: Int, targetFps: Int = 120) async throws {
        guard !isRunning else { return }
        
        if !CGPreflightScreenCaptureAccess() {
            print("[ScreenCapture] Requesting Screen Recording TCC authorization...")
            _ = CGRequestScreenCaptureAccess()
        }
        
        // Poll up to 1.5s for the newly spawned virtual display to register in WindowServer
        var targetDisplay: SCDisplay? = nil
        for attempt in 0..<15 {
            let shareableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            if let found = shareableContent.displays.first(where: { $0.displayID == displayID }) {
                targetDisplay = found
                print("[ScreenCapture] Target Virtual Display \(displayID) successfully resolved on attempt \(attempt + 1)")
                break
            }
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms sleep
        }
        
        var chosenDisplay = targetDisplay
        if chosenDisplay == nil {
            let fallbackContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            chosenDisplay = fallbackContent.displays.first
        }
        guard let displayToCapture = chosenDisplay else {
            throw NSError(domain: "DisplayMac", code: -1, userInfo: [NSLocalizedDescriptionKey: "Target display not found"])
        }
        
        print("[ScreenCapture] Capturing display: ID \(displayToCapture.displayID) (\(displayToCapture.width)x\(displayToCapture.height))")
        let filter = SCContentFilter(display: displayToCapture, excludingWindows: [])
        
        let configuration = SCStreamConfiguration()
        configuration.width = width
        configuration.height = height
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(targetFps))
        configuration.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange // NV12
        configuration.colorSpaceName = CGColorSpace.sRGB
        configuration.showsCursor = true
        configuration.scalesToFit = false // Pixel-perfect 1:1 mapping, no blur
        configuration.queueDepth = 5
        
        // High-fidelity low-latency system audio capture
        configuration.capturesAudio = true
        configuration.sampleRate = 48000
        configuration.channelCount = 2
        
        let scStream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try scStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: videoQueue)
        try scStream.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue)
        
        try await scStream.startCapture()
        self.stream = scStream
        self.isRunning = true
        print("[ScreenCapture] Active at \(width)x\(height) @ \(targetFps) FPS (Zero-Copy NV12 + 48kHz Stereo Audio)")
    }
    
    public func stopCapture() async {
        guard isRunning, let stream = stream else { return }
        do {
            try await stream.stopCapture()
            print("[ScreenCapture] Stream stopped.")
        } catch {
            print("[ScreenCapture] Error stopping stream: \(error.localizedDescription)")
        }
        self.stream = nil
        self.isRunning = false
    }
    
    // MARK: - SCStreamOutput Delegate
    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sampleBuffer.isValid else { return }
        
        switch type {
        case .screen:
            delegate?.captureEngine(self, didCaptureSampleBuffer: sampleBuffer)
            
        case .audio:
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
            var totalLength = 0
            var dataPointer: UnsafeMutablePointer<Int8>?
            CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &totalLength, dataPointerOut: &dataPointer)
            guard let ptr = dataPointer, totalLength > 0 else { return }
            
            // Check if format is Float32 PCM (default in ScreenCaptureKit)
            if let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
               let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)?.pointee {
                if (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0 {
                    let floatCount = totalLength / MemoryLayout<Float>.size
                    let floatPtr = UnsafeRawPointer(ptr).assumingMemoryBound(to: Float.self)
                    let pcm16 = convertFloatTo16BitPCM(pointer: floatPtr, sampleCount: floatCount)
                    let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                    delegate?.captureEngine(self, didCaptureAudioData: pcm16, pts: pts)
                    return
                }
            }
            
            let rawData = Data(bytes: ptr, count: totalLength)
            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            delegate?.captureEngine(self, didCaptureAudioData: rawData, pts: pts)
            
        @unknown default:
            break
        }
    }
    
    private func convertFloatTo16BitPCM(pointer: UnsafePointer<Float>, sampleCount: Int) -> Data {
        var int16Data = Data(count: sampleCount * 2)
        int16Data.withUnsafeMutableBytes { (dest: UnsafeMutableRawBufferPointer) in
            let destPtr = dest.baseAddress!.assumingMemoryBound(to: Int16.self)
            for i in 0..<sampleCount {
                let clamped = max(-1.0, min(1.0, pointer[i]))
                destPtr[i] = Int16(clamped * 32767.0)
            }
        }
        return int16Data
    }
    
    // MARK: - SCStreamDelegate
    public func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("[ScreenCapture] Stream halted unexpectedly: \(error.localizedDescription)")
        self.isRunning = false
    }
}
