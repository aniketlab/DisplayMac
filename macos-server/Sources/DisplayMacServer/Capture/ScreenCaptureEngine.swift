import Foundation
import ScreenCaptureKit
import CoreAudio
import CoreMedia
import CoreVideo
import AVFoundation

public protocol ScreenCaptureEngineDelegate: AnyObject {
    func captureEngine(_ engine: ScreenCaptureEngine, didCaptureSampleBuffer sampleBuffer: CMSampleBuffer)
    func captureEngine(_ engine: ScreenCaptureEngine, didCaptureAudioData data: Data)
}

public final class ScreenCaptureEngine: NSObject, SCStreamOutput, SCStreamDelegate {
    public weak var delegate: ScreenCaptureEngineDelegate?

    private var stream: SCStream?
    private let videoQueue = DispatchQueue(label: "com.displaymac.capture.video", qos: .userInteractive)
    private let audioQueue = DispatchQueue(label: "com.displaymac.capture.audio", qos: .userInteractive)
    public private(set) var isRunning: Bool = false

    public func startCapture(displayID: CGDirectDisplayID, width: Int, height: Int, targetFps: Int = 120) async throws {
        guard !isRunning else { return }

        if !CGPreflightScreenCaptureAccess() {
            print("[ScreenCapture] Requesting Screen Recording TCC authorization...")
            _ = CGRequestScreenCaptureAccess()
        }

        // Poll up to 3.0s for the newly spawned virtual display to register in WindowServer.
        var targetDisplay: SCDisplay?
        for attempt in 0..<30 {
            let shareableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            if let found = shareableContent.displays.first(where: { $0.displayID == displayID }) {
                targetDisplay = found
                print("[ScreenCapture] Virtual display \(displayID) resolved on attempt \(attempt + 1)")
                break
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        guard let displayToCapture = targetDisplay else {
            print("[ScreenCapture] Error: Virtual display \(displayID) not found in WindowServer; aborting capture")
            throw NSError(
                domain: "com.displaymac.server",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Target virtual display \(displayID) not found"]
            )
        }

        print("[ScreenCapture] Capturing display ID \(displayToCapture.displayID) (\(displayToCapture.width)x\(displayToCapture.height))")
        let filter = SCContentFilter(display: displayToCapture, excludingWindows: [])

        let configuration = SCStreamConfiguration()
        configuration.width = width
        configuration.height = height
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(max(targetFps, 24)))
        configuration.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        configuration.colorSpaceName = CGColorSpace.sRGB
        configuration.showsCursor = true
        configuration.scalesToFit = false
        configuration.queueDepth = 3

        let scStream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try scStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: videoQueue)

        try await scStream.startCapture()
        self.stream = scStream
        self.isRunning = true
        print("[ScreenCapture] Active at \(width)x\(height) @ \(targetFps) FPS (NV12)")
    }

    public func stopCapture() async {
        guard isRunning, let stream = stream else { return }
        do {
            try await stream.stopCapture()
            print("[ScreenCapture] Stream stopped")
        } catch {
            print("[ScreenCapture] Error stopping stream: \(error.localizedDescription)")
        }
        self.stream = nil
        self.isRunning = false
    }

    // MARK: - SCStreamOutput
    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sampleBuffer.isValid else { return }

        if type == .screen {
            delegate?.captureEngine(self, didCaptureSampleBuffer: sampleBuffer)
        } else if type == .audio {
            if let pcm16Data = extractPCM16Data(from: sampleBuffer) {
                delegate?.captureEngine(self, didCaptureAudioData: pcm16Data)
            }
        }
    }

    private func extractPCM16Data(from sampleBuffer: CMSampleBuffer) -> Data? {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)?.pointee else {
            return nil
        }

        var audioBufferList = AudioBufferList()
        var blockBuffer: CMBlockBuffer?

        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: &audioBufferList,
            bufferListSize: MemoryLayout<AudioBufferList>.size,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr else { return nil }

        let isFloat = (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        let isNonInterleaved = (asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0
        let numBuffers = Int(audioBufferList.mNumberBuffers)

        if isFloat {
            let buffers = UnsafeMutableAudioBufferListPointer(&audioBufferList)
            if isNonInterleaved && numBuffers >= 2 {
                guard let leftPtr = buffers[0].mData?.assumingMemoryBound(to: Float.self),
                      let rightPtr = buffers[1].mData?.assumingMemoryBound(to: Float.self) else { return nil }
                let frameCount = Int(buffers[0].mDataByteSize) / MemoryLayout<Float>.size
                guard frameCount > 0 else { return nil }

                var pcmData = Data(count: frameCount * 4)
                pcmData.withUnsafeMutableBytes { rawOut in
                    let outPtr = rawOut.bindMemory(to: Int16.self).baseAddress!
                    for i in 0..<frameCount {
                        let l = max(-1.0, min(1.0, leftPtr[i]))
                        let r = max(-1.0, min(1.0, rightPtr[i]))
                        outPtr[i * 2] = Int16(l * 32767.0)
                        outPtr[i * 2 + 1] = Int16(r * 32767.0)
                    }
                }
                return pcmData
            } else if numBuffers >= 1 {
                guard let floatPtr = buffers[0].mData?.assumingMemoryBound(to: Float.self) else { return nil }
                let sampleCount = Int(buffers[0].mDataByteSize) / MemoryLayout<Float>.size
                guard sampleCount > 0 else { return nil }

                var pcmData = Data(count: sampleCount * 2)
                pcmData.withUnsafeMutableBytes { rawOut in
                    let outPtr = rawOut.bindMemory(to: Int16.self).baseAddress!
                    for i in 0..<sampleCount {
                        let s = max(-1.0, min(1.0, floatPtr[i]))
                        outPtr[i] = Int16(s * 32767.0)
                    }
                }
                return pcmData
            }
        } else {
            guard let mData = audioBufferList.mBuffers.mData else { return nil }
            return Data(bytes: mData, count: Int(audioBufferList.mBuffers.mDataByteSize))
        }

        return nil
    }

    // MARK: - SCStreamDelegate
    public func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("[ScreenCapture] Stream halted unexpectedly: \(error.localizedDescription)")
        self.isRunning = false
    }
}
