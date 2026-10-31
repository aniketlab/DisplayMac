import Foundation
import VideoToolbox
import CoreMedia

public protocol HardwareVideoEncoderDelegate: AnyObject {
    func videoEncoder(_ encoder: HardwareVideoEncoder, didEncodePacket data: Data, isKeyframe: Bool, pts: CMTime)
}

public final class HardwareVideoEncoder {
    public weak var delegate: HardwareVideoEncoderDelegate?
    
    private var session: VTCompressionSession?
    private var frameIndex: UInt32 = 0
    private var forceKeyframe: Bool = true
    
    public init() {}
    
    public func setupSession(width: Int, height: Int, fps: Int = 120, bitrateMbps: Int = 60) -> Bool {
        teardown()
        
        // Low-latency encoder specification for Apple Silicon M-series hardware
        let encoderSpecification: [CFString: Any] = [
            kVTVideoEncoderSpecification_EnableLowLatencyRateControl: true
        ]
        
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
            compressionSessionOut: &session
        )
        
        guard status == noErr, let session = session else {
            print("[Encoder] Failed to initialize VTCompressionSession, status: \(status)")
            return false
        }
        
        // Optimize for ultra-low latency interactive streaming (Sub-frame latency)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_HEVC_Main_AutoLevel)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxFrameDelayCount, value: NSNumber(value: 0)) // 0 Frame latency!
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_PrioritizeEncodingSpeedOverQuality, value: kCFBooleanTrue)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: NSNumber(value: fps))
        let bitrateBps = bitrateMbps * 1_000_000
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: NSNumber(value: bitrateBps))
        let dataLimits = [bitrateBps / 8, 1] as CFArray
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_DataRateLimits, value: dataLimits)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: NSNumber(value: fps)) // Keyframe every 1s
        
        VTCompressionSessionPrepareToEncodeFrames(session)
        print("[Encoder] Hardware HEVC VideoToolbox session active (\(width)x\(height) @ \(fps)fps, \(bitrateMbps) Mbps)")
        return true
    }
    
    public func encode(sampleBuffer: CMSampleBuffer) {
        guard let session = session, let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let duration = CMSampleBufferGetDuration(sampleBuffer)
        
        var properties: CFDictionary? = nil
        if forceKeyframe {
            let dict: [CFString: Any] = [kVTEncodeFrameOptionKey_ForceKeyFrame: true]
            properties = dict as CFDictionary
            forceKeyframe = false
        }
        
        VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: imageBuffer,
            presentationTimeStamp: pts,
            duration: duration,
            frameProperties: properties,
            sourceFrameRefcon: nil,
            infoFlagsOut: nil
        )
    }
    
    public func requestImmediateKeyframe() {
        self.forceKeyframe = true
    }
    
    public func teardown() {
        if let session = session {
            VTCompressionSessionInvalidate(session)
            self.session = nil
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
        
        // If keyframe, attach HEVC Parameter Sets (VPS, SPS, PPS) in Annex B format
        if isKeyframe {
            var paramSetCount = 0
            CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(formatDesc, parameterSetIndex: 0, parameterSetPointerOut: nil, parameterSetSizeOut: nil, parameterSetCountOut: &paramSetCount, nalUnitHeaderLengthOut: nil)
            
            for i in 0..<paramSetCount {
                var paramSetPtr: UnsafePointer<UInt8>?
                var paramSetSize = 0
                CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(formatDesc, parameterSetIndex: i, parameterSetPointerOut: &paramSetPtr, parameterSetSizeOut: &paramSetSize, parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil)
                if let ptr = paramSetPtr, paramSetSize > 0 {
                    // Annex B start code 0x00000001
                    packetData.append(contentsOf: [0x00, 0x00, 0x00, 0x01])
                    packetData.append(ptr, count: paramSetSize)
                }
            }
        }
        
        // Extract Slice NALUs with 100% crash-proof unaligned byte reads (No ARM64 alignment trap)
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
                
                // Annex-B 4-byte start code 0x00000001
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
