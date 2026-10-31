import Foundation
import ScreenCaptureKit
import CoreMedia
import CoreVideo

public protocol ScreenCaptureEngineDelegate: AnyObject {
    func captureEngine(_ engine: ScreenCaptureEngine, didCaptureSampleBuffer sampleBuffer: CMSampleBuffer)
}

public final class ScreenCaptureEngine: NSObject, SCStreamOutput, SCStreamDelegate {
    public weak var delegate: ScreenCaptureEngineDelegate?
    
    private var stream: SCStream?
    private let videoQueue = DispatchQueue(label: "com.displaymac.capture.queue", qos: .userInteractive)
    private var isRunning: Bool = false
    
    public func startCapture(displayID: CGDirectDisplayID, width: Int, height: Int, targetFps: Int = 120) async throws {
        guard !isRunning else { return }
        
        if !CGPreflightScreenCaptureAccess() {
            print("[ScreenCapture] Requesting Screen Recording TCC authorization...")
            _ = CGRequestScreenCaptureAccess()
        }
        
        let shareableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let targetDisplay = shareableContent.displays.first(where: { $0.displayID == displayID }) ?? shareableContent.displays.first else {
            throw NSError(domain: "DisplayMac", code: -1, userInfo: [NSLocalizedDescriptionKey: "Target display not found"])
        }
        
        let filter = SCContentFilter(display: targetDisplay, excludingWindows: [])
        
        let configuration = SCStreamConfiguration()
        configuration.width = width
        configuration.height = height
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(targetFps))
        configuration.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange // NV12
        configuration.showsCursor = true
        configuration.capturesAudio = false
        configuration.scalesToFit = true
        
        let scStream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try scStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: videoQueue)
        
        try await scStream.startCapture()
        self.stream = scStream
        self.isRunning = true
        print("[ScreenCapture] Active at \(width)x\(height) @ \(targetFps) FPS (Zero-Copy NV12)")
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
        guard type == .screen else { return }
        guard sampleBuffer.isValid else { return }
        
        delegate?.captureEngine(self, didCaptureSampleBuffer: sampleBuffer)
    }
    
    // MARK: - SCStreamDelegate
    public func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("[ScreenCapture] Stream halted unexpectedly: \(error.localizedDescription)")
        self.isRunning = false
    }
}
