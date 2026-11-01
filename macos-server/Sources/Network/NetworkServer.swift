import Foundation
import Network
import CoreMedia

public protocol NetworkServerDelegate: AnyObject {
    func networkServer(_ server: NetworkServer, didConnectClient hello: ClientHello)
    func networkServerDidDisconnectClient(_ server: NetworkServer)
    func networkServerDidRequestKeyframe(_ server: NetworkServer)
}

public final class NetworkServer {
    public weak var delegate: NetworkServerDelegate?
    
    private var controlListener: NWListener?
    private var videoListener: NWListener?
    
    private var controlConnection: NWConnection?
    private var videoConnection: NWConnection?
    
    // Audio Channel (Dedicated Port 7102)
    private var audioListener: NWListener?
    private var audioConnection: NWConnection?
    private let audioQueue = DispatchQueue(label: "com.displaymac.network.audio", qos: .userInteractive)
    
    private let serverQueue = DispatchQueue(label: "com.displaymac.network.queue", qos: .userInteractive)
    private var frameSequenceNumber: UInt32 = 0
    private var inFlightFrames = 0
    private let maxInFlight = 2
    private var totalBytesSent: UInt64 = 0
    private var lastSpeedCheck = Date()
    private var lastBytesCount: UInt64 = 0
    
    public init() {}
    
    public var isClientLoopback: Bool {
        guard let endpoint = controlConnection?.endpoint else { return false }
        switch endpoint {
        case .hostPort(let host, _):
            let hostStr = "\(host)"
            return hostStr == "127.0.0.1" || hostStr == "::1" || hostStr.contains("127.0.0.1")
        default:
            return false
        }
    }
    
    private static func createTcpParameters() -> NWParameters {
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.noDelay = true
        tcpOptions.enableKeepalive = true
        tcpOptions.keepaliveIdle = 2
        let params = NWParameters(tls: nil, tcp: tcpOptions)
        params.allowLocalEndpointReuse = true
        return params
    }
    
    public func start(controlPort: UInt16 = ProtocolConstants.controlPort,
                       videoPort: UInt16 = ProtocolConstants.videoPort,
                       audioPort: UInt16 = ProtocolConstants.audioPort) throws {
        // Control Channel Listener
        let tcpParams = NetworkServer.createTcpParameters()
        let cListener = try NWListener(using: tcpParams, on: NWEndpoint.Port(rawValue: controlPort)!)
        
        // Broadcast Bonjour service for zero-config Wi-Fi discovery
        cListener.service = NWListener.Service(name: "DisplayMac Host", type: ProtocolConstants.bonjourServiceType)
        
        cListener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("[NetworkServer] Control Channel ready on port \(controlPort) with Bonjour '\(ProtocolConstants.bonjourServiceType)'")
            case .failed(let error):
                print("[NetworkServer] Control Listener failed: \(error)")
            default:
                break
            }
        }
        
        cListener.newConnectionHandler = { [weak self] connection in
            self?.handleNewControlConnection(connection)
        }
        
        cListener.start(queue: serverQueue)
        self.controlListener = cListener
        
        // Video Channel Listener (Port 7101 - Pure 120 FPS Video)
        let vParams = NetworkServer.createTcpParameters()
        let vListener = try NWListener(using: vParams, on: NWEndpoint.Port(rawValue: videoPort)!)
        
        vListener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("[NetworkServer] Video Channel ready on port \(videoPort)")
            case .failed(let error):
                print("[NetworkServer] Video Listener failed: \(error)")
            default:
                break
            }
        }
        
        vListener.newConnectionHandler = { [weak self] connection in
            self?.handleNewVideoConnection(connection)
        }
        
        vListener.start(queue: serverQueue)
        self.videoListener = vListener
        
        // Audio Channel Listener (Port 7102 - Dedicated Crystal-Clear Wire Audio)
        let aParams = NetworkServer.createTcpParameters()
        let aListener = try NWListener(using: aParams, on: NWEndpoint.Port(rawValue: audioPort)!)
        
        aListener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("[NetworkServer] Audio Channel ready on port \(audioPort) (Isolated 48kHz Stereo)")
            case .failed(let error):
                print("[NetworkServer] Audio Listener failed: \(error)")
            default:
                break
            }
        }
        
        aListener.newConnectionHandler = { [weak self] connection in
            self?.handleNewAudioConnection(connection)
        }
        
        aListener.start(queue: audioQueue)
        self.audioListener = aListener
    }
    
    public func stop() {
        controlConnection?.cancel()
        videoConnection?.cancel()
        audioConnection?.cancel()
        controlListener?.cancel()
        videoListener?.cancel()
        audioListener?.cancel()
    }
    
    // MARK: - Control Connection Handling
    private func handleNewControlConnection(_ connection: NWConnection) {
        print("[NetworkServer] New client connected on Control Channel: \(connection.endpoint)")
        if let old = self.controlConnection {
            old.stateUpdateHandler = nil
            old.cancel()
        }
        self.controlConnection = connection
        
        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .failed(let error):
                print("[NetworkServer] Control connection failed: \(error)")
                guard self.controlConnection === connection else { return }
                self.controlConnection = nil
                self.delegate?.networkServerDidDisconnectClient(self)
            case .cancelled:
                print("[NetworkServer] Control connection closed.")
                guard self.controlConnection === connection else { return }
                self.controlConnection = nil
                self.delegate?.networkServerDidDisconnectClient(self)
            default:
                break
            }
        }
        
        connection.start(queue: serverQueue)
        readControlHeader(connection)
    }
    
    private func readControlHeader(_ connection: NWConnection) {
        // Read 8-byte header: Magic(2) + Version(1) + MsgType(1) + Length(4)
        connection.receive(minimumIncompleteLength: 8, maximumLength: 8) { [weak self] content, _, isComplete, error in
            guard let self = self, let data = content, data.count == 8, error == nil else {
                if isComplete { connection.cancel() }
                return
            }
            
            let magic = data.readUInt16BE(at: 0)
            guard magic == ProtocolConstants.magic else {
                print("[NetworkServer] Invalid packet magic: \(magic)")
                self.readControlHeader(connection)
                return
            }
            
            let msgTypeRaw = data[3]
            let payloadLength = data.readUInt32BE(at: 4)
            
            self.readControlPayload(connection, msgType: msgTypeRaw, length: Int(payloadLength))
        }
    }
    
    private func readControlPayload(_ connection: NWConnection, msgType: UInt8, length: Int) {
        guard length > 0 else {
            self.readControlHeader(connection)
            return
        }
        
        connection.receive(minimumIncompleteLength: length, maximumLength: length) { [weak self] content, _, isComplete, error in
            guard let self = self, let payload = content, payload.count == length, error == nil else {
                if isComplete { connection.cancel() }
                return
            }
            
            self.handleControlMessage(msgType: msgType, payload: payload)
            self.readControlHeader(connection)
        }
    }
    
    private func handleControlMessage(msgType: UInt8, payload: Data) {
        switch MessageType(rawValue: msgType) {
        case .clientHello:
            if let hello = ClientHello(from: payload) {
                print("[NetworkServer] Received ClientHello: \(hello.displayWidth)x\(hello.displayHeight) @ \(hello.maxRefreshRate)Hz (DPI: \(hello.dpi))")
                delegate?.networkServer(self, didConnectClient: hello)
            }
            
        case .requestKeyframe:
            print("[NetworkServer] Client requested immediate IDR keyframe")
            delegate?.networkServerDidRequestKeyframe(self)
            
        case .touchEvent:
            if let touch = TouchPacket(from: payload) {
                InputInjector.shared.handleTouchPacket(touch)
            }
            
        case .stylusEvent:
            if let stylus = StylusPacket(from: payload) {
                InputInjector.shared.handleStylusPacket(stylus)
            }
            
        case .ping:
            sendPong()
            
        default:
            break
        }
    }
    
    public func sendServerConfig(_ config: ServerConfig) {
        guard let connection = controlConnection else { return }
        
        let payload = config.serialize()
        var header = Data()
        var magicBE = ProtocolConstants.magic.bigEndian
        header.append(Data(bytes: &magicBE, count: 2))
        header.append(ProtocolConstants.currentVersion)
        header.append(MessageType.serverConfig.rawValue)
        var lengthBE = UInt32(payload.count).bigEndian
        header.append(Data(bytes: &lengthBE, count: 4))
        
        let packet = header + payload
        connection.send(content: packet, completion: .contentProcessed({ error in
            if let error = error {
                print("[NetworkServer] Failed to send ServerConfig: \(error)")
            }
        }))
    }
    
    private func sendPong() {
        guard let connection = controlConnection else { return }
        var packet = Data()
        var magicBE = ProtocolConstants.magic.bigEndian
        packet.append(Data(bytes: &magicBE, count: 2))
        packet.append(ProtocolConstants.currentVersion)
        packet.append(MessageType.pong.rawValue)
        var zeroLen: UInt32 = 0
        packet.append(Data(bytes: &zeroLen, count: 4))
        connection.send(content: packet, completion: .idempotent)
    }
    
    // MARK: - Video Connection Handling
    private func handleNewVideoConnection(_ connection: NWConnection) {
        print("[NetworkServer] New client connected on Video Channel: \(connection.endpoint)")
        if let old = self.videoConnection {
            old.stateUpdateHandler = nil
            old.cancel()
        }
        self.videoConnection = connection
        
        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .failed(let error):
                print("[NetworkServer] Video connection failed: \(error)")
                guard self.videoConnection === connection else { return }
                self.videoConnection = nil
            case .cancelled:
                print("[NetworkServer] Video connection closed.")
                guard self.videoConnection === connection else { return }
                self.videoConnection = nil
            default:
                break
            }
        }
        
        connection.start(queue: serverQueue)
    }
    
    public func broadcastVideoFrame(naluData: Data, isKeyframe: Bool, pts: CMTime) {
        guard let connection = videoConnection, connection.state == .ready else { return }
        
        let effectiveMaxInFlight = isClientLoopback ? 1 : 2
        if inFlightFrames >= effectiveMaxInFlight && !isKeyframe {
            return
        }
        
        // Construct 20-byte Video Header:
        // Magic(2) + FrameType(1) + Codec(1) + SeqNum(4) + PTS(8) + PayloadLength(4)
        var packet = Data(capacity: 20 + naluData.count)
        
        var magicBE = ProtocolConstants.magic.bigEndian
        packet.append(Data(bytes: &magicBE, count: 2))
        
        let frameType: UInt8 = isKeyframe ? FrameType.keyframe.rawValue : FrameType.pFrame.rawValue
        packet.append(frameType)
        packet.append(VideoCodec.hevc.rawValue)
        
        var seqBE = frameSequenceNumber.bigEndian
        packet.append(Data(bytes: &seqBE, count: 4))
        frameSequenceNumber &+= 1
        
        var ptsNanoseconds = UInt64(CMTimeGetSeconds(pts) * 1_000_000_000).bigEndian
        packet.append(Data(bytes: &ptsNanoseconds, count: 8))
        
        var payloadLengthBE = UInt32(naluData.count).bigEndian
        packet.append(Data(bytes: &payloadLengthBE, count: 4))
        
        packet.append(naluData)
        
        totalBytesSent += UInt64(packet.count)
        let now = Date()
        let elapsed = now.timeIntervalSince(lastSpeedCheck)
        if elapsed >= 1.0 {
            let bytes = totalBytesSent - lastBytesCount
            let mbps = (Double(bytes) * 8.0) / (elapsed * 1_000_000.0)
            lastBytesCount = totalBytesSent
            lastSpeedCheck = now
            print(String(format: "[Throughput] ⚡ Speed: %.1f Mbps (Wire Transfer) | 120 FPS Real-Time", mbps))
        }

        inFlightFrames += 1
        connection.send(content: packet, completion: .contentProcessed({ [weak self] _ in
            guard let self = self else { return }
            self.inFlightFrames = max(0, self.inFlightFrames - 1)
        }))
    }
    
    // MARK: - Audio Connection Handling (Dedicated Port 7102)
    private func handleNewAudioConnection(_ connection: NWConnection) {
        print("[NetworkServer] 🎵 New client connected on Audio Channel: \(connection.endpoint)")
        if let old = self.audioConnection {
            old.stateUpdateHandler = nil
            old.cancel()
        }
        self.audioConnection = connection
        
        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .failed(let error):
                print("[NetworkServer] Audio connection failed: \(error)")
                guard self.audioConnection === connection else { return }
                self.audioConnection = nil
            case .cancelled:
                print("[NetworkServer] Audio connection closed.")
                guard self.audioConnection === connection else { return }
                self.audioConnection = nil
            default:
                break
            }
        }
        
        connection.start(queue: audioQueue)
    }
    
    public func broadcastAudioFrame(pcmData: Data) {
        guard let connection = audioConnection, connection.state == .ready else { return }
        
        // 8-byte Audio Header: Magic(2) + FrameType(1) + Reserved(1) + PayloadLength(4)
        var packet = Data(capacity: 8 + pcmData.count)
        
        var magicBE = ProtocolConstants.magic.bigEndian
        packet.append(Data(bytes: &magicBE, count: 2))
        
        packet.append(FrameType.audio.rawValue) // 0x03
        packet.append(0x00) // Reserved
        
        var payloadLengthBE = UInt32(pcmData.count).bigEndian
        packet.append(Data(bytes: &payloadLengthBE, count: 4))
        
        packet.append(pcmData)
        
        connection.send(content: packet, completion: .idempotent)
    }
}
