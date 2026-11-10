import Foundation

public enum MessageType: UInt8 {
    case clientHello     = 0x01
    case serverConfig    = 0x02
    case ping            = 0x03
    case pong            = 0x04
    case requestKeyframe = 0x05
    case touchEvent      = 0x10
    case stylusEvent     = 0x11
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

    public static let maxControlPayloadBytes: Int = 64 * 1024
    public static let maxVideoFrameBytes: Int = 16 * 1024 * 1024
    public static let maxAudioFrameBytes: Int = 256 * 1024

    public static let minDisplayDimension: UInt32 = 320
    public static let maxDisplayDimension: UInt32 = 7680
    public static let minRefreshRateHz: UInt32 = 24
    public static let maxRefreshRateHz: UInt32 = 240
}

extension Data {
    public func readUInt32BE(at offset: Int) -> UInt32 {
        guard offset >= 0, offset + 4 <= count else { return 0 }
        let b0 = UInt32(self[offset])
        let b1 = UInt32(self[offset + 1])
        let b2 = UInt32(self[offset + 2])
        let b3 = UInt32(self[offset + 3])
        return (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
    }

    public func readUInt16BE(at offset: Int) -> UInt16 {
        guard offset >= 0, offset + 2 <= count else { return 0 }
        let b0 = UInt16(self[offset])
        let b1 = UInt16(self[offset + 1])
        return (b0 << 8) | b1
    }

    public mutating func appendUInt16BE(_ value: UInt16) {
        var be = value.bigEndian
        append(Data(bytes: &be, count: 2))
    }

    public mutating func appendUInt32BE(_ value: UInt32) {
        var be = value.bigEndian
        append(Data(bytes: &be, count: 4))
    }

    public mutating func appendUInt64BE(_ value: UInt64) {
        var be = value.bigEndian
        append(Data(bytes: &be, count: 8))
    }
}

public struct ClientHello: Equatable {
    public let displayWidth: UInt32
    public let displayHeight: UInt32
    public let maxRefreshRate: UInt32
    public let dpi: UInt32
    public let codecMask: UInt8
    public let flags: UInt8
    public let deviceName: String

    public init(
        displayWidth: UInt32,
        displayHeight: UInt32,
        maxRefreshRate: UInt32,
        dpi: UInt32,
        codecMask: UInt8 = VideoCodec.hevc.rawValue,
        flags: UInt8 = 0x03,
        deviceName: String = ""
    ) {
        self.displayWidth = displayWidth
        self.displayHeight = displayHeight
        self.maxRefreshRate = maxRefreshRate
        self.dpi = dpi
        self.codecMask = codecMask
        self.flags = flags
        self.deviceName = ClientHello.sanitizeDeviceName(deviceName)
    }

    public init?(from data: Data) {
        guard data.count >= 18 else { return nil }
        let width = data.readUInt32BE(at: 0)
        let height = data.readUInt32BE(at: 4)
        let refreshRate = data.readUInt32BE(at: 8)
        let dpi = data.readUInt32BE(at: 12)

        guard (ProtocolConstants.minDisplayDimension...ProtocolConstants.maxDisplayDimension).contains(width),
              (ProtocolConstants.minDisplayDimension...ProtocolConstants.maxDisplayDimension).contains(height),
              (ProtocolConstants.minRefreshRateHz...ProtocolConstants.maxRefreshRateHz).contains(refreshRate) else {
            return nil
        }

        self.displayWidth = width
        self.displayHeight = height
        self.maxRefreshRate = refreshRate
        self.dpi = dpi > 0 ? dpi : 264
        self.codecMask = data[16]
        self.flags = data[17]

        if data.count > 18 {
            let maxNameBytes = min(data.count - 18, 128)
            let nameData = data.subdata(in: 18..<(18 + maxNameBytes))
            let rawName = String(data: nameData, encoding: .utf8) ?? ""
            self.deviceName = ClientHello.sanitizeDeviceName(rawName)
        } else {
            self.deviceName = ""
        }
    }

    public func serializePayload() -> Data {
        var data = Data(capacity: 18 + deviceName.utf8.count)
        data.appendUInt32BE(displayWidth)
        data.appendUInt32BE(displayHeight)
        data.appendUInt32BE(maxRefreshRate)
        data.appendUInt32BE(dpi)
        data.append(codecMask)
        data.append(flags)
        if !deviceName.isEmpty {
            data.append(Data(deviceName.utf8))
        }
        return data
    }

    private static func sanitizeDeviceName(_ raw: String) -> String {
        let filteredScalars = raw.unicodeScalars.filter { scalar in
            !CharacterSet.controlCharacters.contains(scalar)
        }
        return String(String.UnicodeScalarView(filteredScalars))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct ServerConfig: Equatable {
    public let selectedCodec: VideoCodec
    public let activeFps: UInt8
    public let streamWidth: UInt32
    public let streamHeight: UInt32
    public let targetBitrateKbps: UInt32

    public init(
        selectedCodec: VideoCodec,
        activeFps: UInt8,
        streamWidth: UInt32,
        streamHeight: UInt32,
        targetBitrateKbps: UInt32
    ) {
        self.selectedCodec = selectedCodec
        self.activeFps = activeFps
        self.streamWidth = streamWidth
        self.streamHeight = streamHeight
        self.targetBitrateKbps = targetBitrateKbps
    }

    public func serialize() -> Data {
        var data = Data(capacity: 14)
        data.append(selectedCodec.rawValue)
        data.append(activeFps)
        data.appendUInt32BE(streamWidth)
        data.appendUInt32BE(streamHeight)
        data.appendUInt32BE(targetBitrateKbps)
        return data
    }
}

public struct StylusAction {
    public static let down: UInt8      = 0x01
    public static let move: UInt8      = 0x02
    public static let up: UInt8        = 0x03
    public static let hover: UInt8     = 0x04
    public static let hoverExit: UInt8 = 0x05
}

public struct StylusPacket: Equatable {
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

public struct TouchAction {
    public static let tap: UInt8        = 0x01
    public static let doubleTap: UInt8  = 0x02
    public static let rightClick: UInt8 = 0x03
    public static let scroll: UInt8     = 0x04
    public static let dragStart: UInt8  = 0x05
    public static let dragMove: UInt8   = 0x06
    public static let dragEnd: UInt8    = 0x07
    public static let zoom: UInt8       = 0x08
}

public struct TouchPhase {
    public static let began: UInt8     = 0x01
    public static let changed: UInt8   = 0x02
    public static let ended: UInt8     = 0x03
    public static let cancelled: UInt8 = 0x04
}

public struct TouchPacket: Equatable {
    public let action: UInt8
    public let phase: UInt8
    public let normalizedX: Float
    public let normalizedY: Float
    public let deltaX: Float
    public let deltaY: Float

    public init?(from data: Data) {
        guard data.count >= 18 else { return nil }
        self.action = data[0]
        self.phase = data[1]
        self.normalizedX = Float(bitPattern: data.readUInt32BE(at: 2))
        self.normalizedY = Float(bitPattern: data.readUInt32BE(at: 6))
        self.deltaX = Float(bitPattern: data.readUInt32BE(at: 10))
        self.deltaY = Float(bitPattern: data.readUInt32BE(at: 14))
    }
}
