import Foundation
import VideoToolbox
import CoreMedia

public protocol HardwareVideoEncoderDelegate: AnyObject {
    func videoEncoder(_ encoder: HardwareVideoEncoder, didEncodePacket data: Data, isKeyframe: Bool, pts: CMTime)
}

public final class HardwareVideoEncoder {
    public weak var delegate: HardwareVideoEncoderDelegate?

    private let stateLock = NSLock()
    private var session: VTCompressionSession?
    private var forceKeyframe: Bool = true
    private var lastCapturedPixelBuffer: CVPixelBuffer?
    private var configuredFps: Int = 120

    public init() {}

    public func setupSession(width: Int, height: Int, fps: Int = 120, bitrateMbps: Int = 60) -> Bool {
        teardown()

        let safeFps = max(fps, 24)
        let encoderSpecification: [CFString: Any] = [
            kVTVideoEncoderSpecification_EnableLowLatencyRateControl: true
        ]

        var newSession: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: Int32(width),
            height: Int32(height),
            codecType: kCMVideoCodecType_HEVC,
            encoderSpecification: encoderSpecification as CFDictionary,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: compressionCallback,
            refcon: Unmanaged.passUnretained(self).toOpaque(),
            compressionSessionOut: &newSession
        )

        guard status == noErr, let createdSession = newSession else {
            print("[Encoder] Failed to initialize VTCompressionSession (status: \(status))")
            return false
        }

        VTSessionSetProperty(createdSession, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(createdSession, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_HEVC_Main_AutoLevel)
        VTSessionSetProperty(createdSession, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        VTSessionSetProperty(createdSession, key: kVTCompressionPropertyKey_AllowTemporalCompression, value: kCFBooleanTrue)
        VTSessionSetProperty(createdSession, key: kVTCompressionPropertyKey_MaxFrameDelayCount, value: NSNumber(value: 0))
        VTSessionSetProperty(createdSession, key: kVTCompressionPropertyKey_PrioritizeEncodingSpeedOverQuality, value: kCFBooleanTrue)
        VTSessionSetProperty(createdSession, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: NSNumber(value: safeFps))

        let bitrateBps = bitrateMbps * 1_000_000
        VTSessionSetProperty(createdSession, key: kVTCompressionPropertyKey_AverageBitRate, value: NSNumber(value: bitrateBps))
        let dataLimits = [bitrateBps / 8, 1] as CFArray
        VTSessionSetProperty(createdSession, key: kVTCompressionPropertyKey_DataRateLimits, value: dataLimits)
        VTSessionSetProperty(createdSession, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: NSNumber(value: safeFps * 30))
        VTSessionSetProperty(createdSession, key: kVTCompressionPropertyKey_MoreFramesBeforeStart, value: kCFBooleanFalse)
        VTSessionSetProperty(createdSession, key: kVTCompressionPropertyKey_MoreFramesAfterEnd, value: kCFBooleanFalse)

        VTCompressionSessionPrepareToEncodeFrames(createdSession)

        stateLock.lock()
        self.session = createdSession
        self.configuredFps = safeFps
        self.forceKeyframe = true
        stateLock.unlock()

        print("[Encoder] Hardware HEVC VideoToolbox session active (\(width)x\(height) @ \(safeFps) FPS, \(bitrateMbps) Mbps)")
        return true
    }

    public func encode(sampleBuffer: CMSampleBuffer) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        stateLock.lock()
        let activeSession = self.session
        self.lastCapturedPixelBuffer = imageBuffer
        let shouldForceKeyframe = self.forceKeyframe
        if shouldForceKeyframe {
            self.forceKeyframe = false
        }
        stateLock.unlock()

        guard let activeSession = activeSession else { return }

        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let duration = CMSampleBufferGetDuration(sampleBuffer)

        var properties: CFDictionary?
        if shouldForceKeyframe {
            let dict: [CFString: Any] = [kVTEncodeFrameOptionKey_ForceKeyFrame: true]
            properties = dict as CFDictionary
        }

        VTCompressionSessionEncodeFrame(
            activeSession,
            imageBuffer: imageBuffer,
            presentationTimeStamp: pts,
            duration: duration,
            frameProperties: properties,
            sourceFrameRefcon: nil,
            infoFlagsOut: nil
        )
    }

    public func requestImmediateKeyframe() {
        stateLock.lock()
        self.forceKeyframe = true
        let activeSession = self.session
        let cachedBuffer = self.lastCapturedPixelBuffer
        let fps = self.configuredFps
        if activeSession != nil && cachedBuffer != nil {
            self.forceKeyframe = false
        }
        stateLock.unlock()

        if let activeSession = activeSession, let imageBuffer = cachedBuffer {
            let pts = CMClockGetTime(CMClockGetHostTimeClock())
            let duration = CMTime(value: 1, timescale: CMTimeScale(max(fps, 24)))
            let dict: [CFString: Any] = [kVTEncodeFrameOptionKey_ForceKeyFrame: true]

            VTCompressionSessionEncodeFrame(
                activeSession,
                imageBuffer: imageBuffer,
                presentationTimeStamp: pts,
                duration: duration,
                frameProperties: dict as CFDictionary,
                sourceFrameRefcon: nil,
                infoFlagsOut: nil
            )
            print("[Encoder] Dispatched cached frame as IDR keyframe upon client request")
        }
    }

    public func teardown() {
        stateLock.lock()
        let activeSession = self.session
        self.session = nil
        self.lastCapturedPixelBuffer = nil
        stateLock.unlock()

        if let activeSession = activeSession {
            VTCompressionSessionCompleteFrames(activeSession, untilPresentationTimeStamp: .invalid)
            VTCompressionSessionInvalidate(activeSession)
        }
    }

    deinit {
        teardown()
    }

    fileprivate func handleEncodedSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }

        var isKeyframe = false
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false),
           CFArrayGetCount(attachments) > 0 {
            let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFDictionary.self)
            isKeyframe = !CFDictionaryContainsKey(dict, Unmanaged.passUnretained(kCMSampleAttachmentKey_NotSync).toOpaque())
        }

        var packetData = Data()

        if isKeyframe {
            var paramSetCount = 0
            CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(
                formatDesc,
                parameterSetIndex: 0,
                parameterSetPointerOut: nil,
                parameterSetSizeOut: nil,
                parameterSetCountOut: &paramSetCount,
                nalUnitHeaderLengthOut: nil
            )

            for i in 0..<paramSetCount {
                var paramSetPtr: UnsafePointer<UInt8>?
                var paramSetSize = 0
                CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(
                    formatDesc,
                    parameterSetIndex: i,
                    parameterSetPointerOut: &paramSetPtr,
                    parameterSetSizeOut: &paramSetSize,
                    parameterSetCountOut: nil,
                    nalUnitHeaderLengthOut: nil
                )
                if let ptr = paramSetPtr, paramSetSize > 0 {
                    packetData.append(contentsOf: [0x00, 0x00, 0x00, 0x01])
                    packetData.append(ptr, count: paramSetSize)
                }
            }
        }

        var totalLength = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        CMBlockBufferGetDataPointer(dataBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &totalLength, dataPointerOut: &dataPointer)

        if let pointer = dataPointer {
            var offset = 0
            while offset + 4 <= totalLength {
                let raw = UnsafeRawPointer(pointer).advanced(by: offset)
                let b0 = UInt32(raw.load(fromByteOffset: 0, as: UInt8.self))
                let b1 = UInt32(raw.load(fromByteOffset: 1, as: UInt8.self))
                let b2 = UInt32(raw.load(fromByteOffset: 2, as: UInt8.self))
                let b3 = UInt32(raw.load(fromByteOffset: 3, as: UInt8.self))
                let lengthPrefixed = Int((b0 << 24) | (b1 << 16) | (b2 << 8) | b3)
                offset += 4

                guard lengthPrefixed > 0, offset + lengthPrefixed <= totalLength else {
                    break
                }

                packetData.append(contentsOf: [0x00, 0x00, 0x00, 0x01])
                let nalBytes = UnsafeRawPointer(pointer).advanced(by: offset).assumingMemoryBound(to: UInt8.self)
                packetData.append(nalBytes, count: lengthPrefixed)
                offset += lengthPrefixed
            }
        }

        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        delegate?.videoEncoder(self, didEncodePacket: packetData, isKeyframe: isKeyframe, pts: pts)
    }
}

private func compressionCallback(
    outputCallbackRefCon: UnsafeMutableRawPointer?,
    sourceFrameRefCon: UnsafeMutableRawPointer?,
    status: OSStatus,
    infoFlags: VTEncodeInfoFlags,
    sampleBuffer: CMSampleBuffer?
) {
    guard status == noErr, let sampleBuffer = sampleBuffer, let refCon = outputCallbackRefCon else { return }
    let encoder = Unmanaged<HardwareVideoEncoder>.fromOpaque(refCon).takeUnretainedValue()
    encoder.handleEncodedSampleBuffer(sampleBuffer)
}
