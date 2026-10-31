import Foundation
import CoreAudio

public final class AudioManager {
    public static let shared = AudioManager()
    
    private var previousDefaultDeviceID: AudioDeviceID?
    
    private init() {}
    
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
            // Check if device has output streams
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
    
    /// Finds a tablet-associated audio output device (Samsung, Tab, Galaxy, DisplayMac, BlackHole)
    public func findTabletAudioDevice() -> (id: AudioDeviceID, name: String)? {
        let devices = getOutputDevices()
        let keywords = ["samsung", "galaxy", "tab", "displaymac", "blackhole"]
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
    
    /// Saves current default audio output so it can be restored on disconnect
    public func saveCurrentOutputDevice() {
        self.previousDefaultDeviceID = getDefaultOutputDevice()
    }
    
    /// Restores previous audio output device on client disconnect
    public func restorePreviousOutputDevice() {
        if let previousID = previousDefaultDeviceID {
            _ = setDefaultOutputDevice(previousID)
            self.previousDefaultDeviceID = nil
        }
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
