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
    private let nameFilePath = "/tmp/displaymac_audio_name.txt"
    private let activeFilePath = "/tmp/displaymac_audio_active.txt"
    
    private init() {}
    
    /// Updates the active connection state of the tablet audio device
    public func setActive(_ active: Bool) {
        self.isClientConnected = active
        let val = active ? "1" : "0"
        try? val.write(toFile: activeFilePath, atomically: true, encoding: .utf8)
    }
    
    /// Real-time Silence Guard: Intercepts accidental selection of DisplayMac Audio while disconnected
    /// and immediately snaps default sound back to BenQ monitor or Mac mini speakers in 0ms!
    public func startSilenceGuard() {
        var propAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &propAddress,
            DispatchQueue.main
        ) { [weak self] _, _ in
            guard let self = self else { return }
            if let current = self.getDefaultOutputDevice(),
               let name = self.getDeviceName(for: current) {
                if !self.isDisplayMacVirtualAudio(name: name) {
                    // User switched to a physical device (BenQ, Mac mini speakers, Headphones) -> remember it!
                    self.previousDefaultDeviceID = current
                } else if !self.isClientConnected {
                    // Tablet is offline, but DisplayMac Audio was selected -> snap back immediately!
                    self.restorePhysicalMacAudio()
                }
            }
        }
        print("[Audio] 🛡️ Real-time Silence Guard active (tracks physical audio memory & prevents offline mute).")
    }
    
    /// Sets the dynamic tablet model name (e.g. "Samsung Galaxy Tab S10 Ultra (DisplayMac)" or "DisplayMac Audio")
    public func setDynamicDeviceName(_ name: String) {
        do {
            try name.write(toFile: nameFilePath, atomically: true, encoding: .utf8)
        } catch {
            print("[Audio] Failed to write dynamic audio device name: \(error)")
        }
        
        // Directly update the property on the HAL device so macOS Menu Bar & Control Center reflect it immediately
        if let dev = findTabletAudioDevice() {
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
                print("[Audio] 🏷️ Live audio device name set to: '\(name)'")
            } else {
                print("[Audio] 🏷️ Dynamic audio device name recorded: '\(name)'")
            }
        }
    }
    
    /// Queries all connected audio output devices
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
    
    /// Finds a tablet-associated audio output device (DisplayMac, Samsung, Tab, Galaxy, BlackHole)
    public func findTabletAudioDevice() -> (id: AudioDeviceID, name: String)? {
        let devices = getOutputDevices()
        let keywords = ["displaymac", "samsung", "galaxy", "tab", "blackhole"]
        for dev in devices {
            let lowerName = dev.name.lowercased()
            for kw in keywords {
                if lowerName.contains(kw) {
                    return dev
                }
            }
        }
        return nil
    }
    
    /// Gets current default system audio output device
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
    
    /// Sets default system audio output device
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
    
    /// Determines whether an audio device belongs to DisplayMac virtual audio pipeline
    public func isDisplayMacVirtualAudio(name: String) -> Bool {
        let lower = name.lowercased()
        let keywords = ["displaymac", "samsung", "galaxy", "tab", "blackhole"]
        return keywords.contains { lower.contains($0) }
    }
    
    /// Saves current default audio output so it can be restored on disconnect
    public func saveCurrentOutputDevice() {
        if let current = getDefaultOutputDevice(),
           let name = getDeviceName(for: current),
           !isDisplayMacVirtualAudio(name: name) {
            self.previousDefaultDeviceID = current
            print("[Audio] 💾 Saved active physical audio output: '\(name)'")
        }
    }
    
    /// Restores previous audio output device on client disconnect (only if audio was left on tablet)
    public func restorePreviousOutputDevice() {
        // Only revert if macOS audio is currently directed to the tablet!
        guard let current = getDefaultOutputDevice(),
              let currentName = getDeviceName(for: current),
              isDisplayMacVirtualAudio(name: currentName) else {
            return // User was already using physical audio (BenQ/Mac mini); do not interrupt!
        }
        
        if let previousID = previousDefaultDeviceID,
           let name = getDeviceName(for: previousID) {
            _ = setDefaultOutputDevice(previousID)
            print("[Audio] 🔈 Tablet disconnected: Reverted sound to previous physical output '\(name)'!")
            return
        }
        
        // Automatic fallback: restore to physical hardware (BenQ monitor or Mac mini speakers)
        restorePhysicalMacAudio()
    }
    
    /// Finds the physical Mac audio output device (Mac mini built-in speakers or BenQ monitor)
    public func getPhysicalDefaultDevice() -> AudioDeviceID? {
        let devices = getOutputDevices()
        for dev in devices {
            if !isDisplayMacVirtualAudio(name: dev.name) {
                return dev.id
            }
        }
        return nil
    }
    
    /// Returns the name of the active physical Mac audio output device
    public func getPhysicalDefaultDeviceName() -> String {
        if let id = getPhysicalDefaultDevice(), let name = getDeviceName(for: id) {
            return name
        }
        return "Physical Hardware"
    }
    
    /// Ensures that physical Mac hardware (Mac mini speakers or BenQ) is default, undoing any rogue selection
    public func restorePhysicalMacAudio() {
        if let currentDefault = getDefaultOutputDevice(),
           let devName = getDeviceName(for: currentDefault),
           isDisplayMacVirtualAudio(name: devName) {
            if let physicalID = getPhysicalDefaultDevice() {
                _ = setDefaultOutputDevice(physicalID)
                let physName = getDeviceName(for: physicalID) ?? "Physical Hardware"
                print("[Audio] 🔈 Restored default audio to physical hardware: '\(physName)'")
            }
        }
    }
    
    /// Start capturing audio loopback from the virtual tablet audio device
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
            print("[Audio] ⚡ CoreAudio direct loopback capture active on device \(deviceID)!")
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
        print("[Audio] Audio capture stopped.")
    }
    
    public func getDeviceName(for deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: CFString? = nil
        var propertySize = UInt32(MemoryLayout<CFString?>.size)
        let status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &name
        )
        guard status == noErr, let cfName = name else { return nil }
        return cfName as String
    }
}
