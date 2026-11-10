import Foundation
import CoreAudio

public final class AudioManager {
    public static let shared = AudioManager()

    private var previousDefaultDeviceID: AudioDeviceID?
    private var ioProcID: AudioDeviceIOProcID?
    private var capturingDeviceID: AudioDeviceID?
    private var audioCallback: ((Data) -> Void)?
    private var isCapturing = false

    public var isClientConnected = false

    private init() {}

    public func setActive(_ active: Bool) {
        self.isClientConnected = active
    }

    /// Updates the DisplayMac HAL device name in CoreAudio without insecure temp files.
    public func setDynamicDeviceName(_ name: String) {
        guard let dev = findTabletAudioDevice() else { return }

        var propAddress = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var cfName: CFString = name as CFString
        let status = AudioObjectSetPropertyData(
            dev.id,
            &propAddress,
            0,
            nil,
            UInt32(MemoryLayout<CFString>.size),
            &cfName
        )
        if status == noErr {
            print("[Audio] Virtual audio device name updated to '\(name)'")
        }
    }

    public func getOutputDevices() -> [(id: AudioDeviceID, name: String)] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var propertySize: UInt32 = 0
        let statusSize = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &propertySize
        )
        guard statusSize == noErr, propertySize > 0 else { return [] }

        let numDevices = Int(propertySize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: numDevices)
        let statusData = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &deviceIDs
        )
        guard statusData == noErr else { return [] }

        var outputDevices: [(id: AudioDeviceID, name: String)] = []
        for id in deviceIDs {
            var streamAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioObjectPropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            var streamSize: UInt32 = 0
            if AudioObjectGetPropertyDataSize(id, &streamAddress, 0, nil, &streamSize) == noErr && streamSize > 0 {
                if let name = getDeviceName(for: id) {
                    outputDevices.append((id: id, name: name))
                }
            }
        }
        return outputDevices
    }

    /// Finds only DisplayMac's own HAL virtual audio device by UID or name.
    public func findTabletAudioDevice() -> (id: AudioDeviceID, name: String)? {
        for dev in getOutputDevices() {
            if isDisplayMacAudioDevice(id: dev.id, name: dev.name) {
                return dev
            }
        }
        return nil
    }

    public func getDefaultOutputDevice() -> AudioDeviceID? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID: AudioDeviceID = 0
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceID
        )
        return status == noErr ? deviceID : nil
    }

    public func setDefaultOutputDevice(_ deviceID: AudioDeviceID) -> Bool {
        var mutableID = deviceID
        let dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            dataSize,
            &mutableID
        )
        return status == noErr
    }

    public func isDisplayMacAudioDevice(id: AudioDeviceID, name: String? = nil) -> Bool {
        if let uid = getDeviceUID(for: id), uid.lowercased().contains("displaymacaudio") {
            return true
        }
        let resolvedName = name ?? getDeviceName(for: id) ?? ""
        return resolvedName.lowercased().contains("displaymac")
    }

    public func saveCurrentOutputDevice() {
        if let current = getDefaultOutputDevice(),
           let name = getDeviceName(for: current),
           !isDisplayMacAudioDevice(id: current, name: name) {
            self.previousDefaultDeviceID = current
            print("[Audio] Saved active physical audio output: '\(name)'")
        }
    }

    public func restorePreviousOutputDevice() {
        guard let current = getDefaultOutputDevice(),
              let currentName = getDeviceName(for: current),
              isDisplayMacAudioDevice(id: current, name: currentName) else {
            return
        }

        if let previousID = previousDefaultDeviceID,
           let name = getDeviceName(for: previousID) {
            _ = setDefaultOutputDevice(previousID)
            print("[Audio] Reverted audio output to physical device '\(name)'")
            return
        }

        restorePhysicalMacAudio()
    }

    public func getPhysicalDefaultDevice() -> AudioDeviceID? {
        for dev in getOutputDevices() {
            if !isDisplayMacAudioDevice(id: dev.id, name: dev.name) {
                return dev.id
            }
        }
        return nil
    }

    public func getPhysicalDefaultDeviceName() -> String {
        if let id = getPhysicalDefaultDevice(), let name = getDeviceName(for: id) {
            return name
        }
        return "System Output"
    }

    public func restorePhysicalMacAudio() {
        if let currentDefault = getDefaultOutputDevice(),
           let devName = getDeviceName(for: currentDefault),
           isDisplayMacAudioDevice(id: currentDefault, name: devName) {
            if let physicalID = getPhysicalDefaultDevice() {
                _ = setDefaultOutputDevice(physicalID)
                let physName = getDeviceName(for: physicalID) ?? "System Output"
                print("[Audio] Restored default output to physical device '\(physName)'")
            }
        }
    }

    public func startCapturing(deviceID: AudioDeviceID, onPCMData: @escaping (Data) -> Void) -> Bool {
        stopCapturing()
        self.capturingDeviceID = deviceID
        self.audioCallback = onPCMData

        var proc: AudioDeviceIOProcID?
        let status = AudioDeviceCreateIOProcIDWithBlock(&proc, deviceID, nil) { [weak self] _, inInputData, _, _, _ in
            guard let self = self else { return }
            let bufferList = inInputData.pointee
            guard bufferList.mNumberBuffers > 0 else { return }

            let buffer = bufferList.mBuffers
            guard let mData = buffer.mData else { return }
            let byteSize = Int(buffer.mDataByteSize)

            let floatCount = byteSize / MemoryLayout<Float>.size
            guard floatCount > 0 else { return }

            let floatPtr = mData.assumingMemoryBound(to: Float.self)
            var pcmData = Data(count: floatCount * 2)
            pcmData.withUnsafeMutableBytes { outRaw in
                let int16Ptr = outRaw.bindMemory(to: Int16.self).baseAddress!
                for i in 0..<floatCount {
                    let f = max(-1.0, min(1.0, floatPtr[i]))
                    int16Ptr[i] = Int16(f * 32767.0)
                }
            }
            self.audioCallback?(pcmData)
        }

        guard status == noErr, let validProc = proc else {
            print("[Audio] Error creating IOProc on device \(deviceID): \(status)")
            return false
        }

        self.ioProcID = validProc
        let startStatus = AudioDeviceStart(deviceID, validProc)
        if startStatus == noErr {
            self.isCapturing = true
            print("[Audio] CoreAudio loopback capture active on device \(deviceID)")
            return true
        } else {
            print("[Audio] Failed to start audio device IO: \(startStatus)")
            return false
        }
    }

    public func stopCapturing() {
        guard isCapturing, let devID = capturingDeviceID, let proc = ioProcID else { return }
        AudioDeviceStop(devID, proc)
        AudioDeviceDestroyIOProcID(devID, proc)
        self.ioProcID = nil
        self.capturingDeviceID = nil
        self.audioCallback = nil
        self.isCapturing = false
        print("[Audio] Audio capture stopped")
    }

    public func getDeviceName(for deviceID: AudioDeviceID) -> String? {
        getStringProperty(selector: kAudioObjectPropertyName, for: deviceID)
    }

    public func getDeviceUID(for deviceID: AudioDeviceID) -> String? {
        getStringProperty(selector: kAudioDevicePropertyDeviceUID, for: deviceID)
    }

    private func getStringProperty(selector: AudioObjectPropertySelector, for deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: CFString?
        var propertySize = UInt32(MemoryLayout<CFString?>.size)
        let status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &value
        )
        guard status == noErr, let cfValue = value else { return nil }
        return cfValue as String
    }
}
