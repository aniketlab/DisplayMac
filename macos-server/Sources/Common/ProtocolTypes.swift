import Foundation

public enum MessageType: UInt8 {
    case clientHello     = 0x01
    case serverConfig    = 0x02
    case ping            = 0x03
    case pong            = 0x04
    case requestKeyframe = 0x05
    case touchEvent      = 0x10
    case stylusEvent     = 0x11
    case mouseEvent      = 0x12
    case keyboardEvent   = 0x13
    case setBrightness   = 0x20
}

public enum VideoCodec: UInt8 {
    case avc  = 0x01 // H.264
    case hevc = 0x02 // H.265
    case av1  = 0x03
}

public enum FrameType: UInt8 {
    case keyframe = 0x01
    case pFrame   = 0x02
    case audio    = 0x03
}

public struct ProtocolConstants {
    public static let magic: UInt16 = 0x444D // "DM"
    public static let currentVersion: UInt8 = 0x01
    public static let controlPort: UInt16 = 7100
    public static let videoPort: UInt16 = 7101
    public static let audioPort: UInt16 = 7102
    public static let bonjourServiceType = "_displaymac._tcp"
}

extension Data {
    public func readUInt32BE(at offset: Int) -> UInt32 {
        guard offset + 4 <= count else { return 0 }
        let b0 = UInt32(self[offset])
        let b1 = UInt32(self[offset + 1])
        let b2 = UInt32(self[offset + 2])
        let b3 = UInt32(self[offset + 3])
        return (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
    }
    
    public func readUInt16BE(at offset: Int) -> UInt16 {
        guard offset + 2 <= count else { return 0 }
        let b0 = UInt16(self[offset])
        let b1 = UInt16(self[offset + 1])
        return (b0 << 8) | b1
    }
}

public struct ClientHello {
    public let displayWidth: UInt32
    public let displayHeight: UInt32
    public let maxRefreshRate: UInt32
    public let dpi: UInt32
    public let codecMask: UInt8
    public let flags: UInt8
    public let deviceName: String
    
    public init?(from data: Data) {
        guard data.count >= 18 else { return nil }
        self.displayWidth = data.readUInt32BE(at: 0)
        self.displayHeight = data.readUInt32BE(at: 4)
        self.maxRefreshRate = data.readUInt32BE(at: 8)
        self.dpi = data.readUInt32BE(at: 12)
        self.codecMask = data[16]
        self.flags = data[17]
        
        if data.count > 18 {
            let nameData = data.subdata(in: 18..<data.count)
            self.deviceName = String(data: nameData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        } else {
            self.deviceName = ""
        }
    }
}

public struct ServerConfig {
    public let selectedCodec: VideoCodec
    public let activeFps: UInt8
    public let streamWidth: UInt32
    public let streamHeight: UInt32
    public let targetBitrateKbps: UInt32
    
    public func serialize() -> Data {
        var data = Data()
        data.append(selectedCodec.rawValue)
        data.append(activeFps)
        
        var widthBE = streamWidth.bigEndian
        data.append(Data(bytes: &widthBE, count: 4))
        
        var heightBE = streamHeight.bigEndian
        data.append(Data(bytes: &heightBE, count: 4))
        
        var bitrateBE = targetBitrateKbps.bigEndian
        data.append(Data(bytes: &bitrateBE, count: 4))
        
        return data
    }
}

public struct StylusAction {
    public static let down: UInt8  = 0x01
    public static let move: UInt8  = 0x02
    public static let up: UInt8    = 0x03
    public static let hover: UInt8 = 0x04
}

public struct StylusPacket {
    public let action: UInt8
    public let buttons: UInt8
    public let normalizedX: Float
    public let normalizedY: Float
    public let pressure: Float
    public let tilt: Float
    
    public init?(from data: Data) {
        guard data.count >= 18 else { return nil }
        self.action = data[0]
        self.buttons = data[1]
        self.normalizedX = Float(bitPattern: data.readUInt32BE(at: 2))
        self.normalizedY = Float(bitPattern: data.readUInt32BE(at: 6))
        self.pressure = Float(bitPattern: data.readUInt32BE(at: 10))
        self.tilt = Float(bitPattern: data.readUInt32BE(at: 14))
    }
}
