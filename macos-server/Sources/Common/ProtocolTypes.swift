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
}

public enum VideoCodec: UInt8 {
    case avc  = 0x01 // H.264
    case hevc = 0x02 // H.265
    case av1  = 0x03
}

public enum FrameType: UInt8 {
    case keyframe = 0x01
    case pFrame   = 0x02
}

public struct ProtocolConstants {
    public static let magic: UInt16 = 0x444D // "DM"
    public static let currentVersion: UInt8 = 0x01
    public static let controlPort: UInt16 = 7100
    public static let videoPort: UInt16 = 7101
    public static let bonjourServiceType = "_displaymac._tcp"
}

public struct ClientHello {
    public let displayWidth: UInt32
    public let displayHeight: UInt32
    public let maxRefreshRate: UInt32
    public let dpi: UInt32
    public let codecMask: UInt8
    public let flags: UInt8
    
    public init?(from data: Data) {
        guard data.count >= 18 else { return nil }
        self.displayWidth = data.subdata(in: 0..<4).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        self.displayHeight = data.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        self.maxRefreshRate = data.subdata(in: 8..<12).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        self.dpi = data.subdata(in: 12..<16).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        self.codecMask = data[16]
        self.flags = data[17]
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
        
        let xBits = data.subdata(in: 2..<6).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        self.normalizedX = Float(bitPattern: xBits)
        
        let yBits = data.subdata(in: 6..<10).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        self.normalizedY = Float(bitPattern: yBits)
        
        let pressureBits = data.subdata(in: 10..<14).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        self.pressure = Float(bitPattern: pressureBits)
        
        let tiltBits = data.subdata(in: 14..<18).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        self.tilt = Float(bitPattern: tiltBits)
    }
}
