import Foundation
import Network
import CoreMedia

public protocol NetworkServerDelegate: AnyObject {
    func networkServer(_ server: NetworkServer, didConnectClient hello: ClientHello)
    func networkServerDidRequestKeyframe(_ server: NetworkServer)
}

public final class NetworkServer {
    public weak var delegate: NetworkServerDelegate?
    
    private var controlListener: NWListener?
    private var videoListener: NWListener?
    
    private var controlConnection: NWConnection?
    private var videoConnection: NWConnection?
    
    private let serverQueue = DispatchQueue(label: "com.displaymac.network.queue", qos: .userInteractive)
    private var frameSequenceNumber: UInt32 = 0
    
    public init() {}
    
    public func start(controlPort: UInt16 = ProtocolConstants.controlPort, videoPort: UInt16 = ProtocolConstants.videoPort) throws {
        // Control Channel Listener
        let tcpParams = NWParameters.tcp
        tcpParams.allowLocalEndpointReuse = true
        
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
        
        // Video Channel Listener
        let vParams = NWParameters.tcp
        vParams.allowLocalEndpointReuse = true
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
    }
    
    public func stop() {
        controlConnection?.cancel()
        videoConnection?.cancel()
        controlListener?.cancel()
        videoListener?.cancel()
    }
    
    // MARK: - Control Connection Handling
    private func handleNewControlConnection(_ connection: NWConnection) {
        print("[NetworkServer] New client connected on Control Channel: \(connection.endpoint)")
        self.controlConnection?.cancel()
        self.controlConnection = connection
        
        connection.stateUpdateHandler = { [weak self] state in
            if case .failed(let error) = state {
                print("[NetworkServer] Control connection failed: \(error)")
                self?.controlConnection = nil
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
            
            let magic = data.subdata(in: 0..<2).withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
            guard magic == ProtocolConstants.magic else {
                print("[NetworkServer] Invalid packet magic: \(magic)")
                self.readControlHeader(connection)
                return
            }
            
            let msgTypeRaw = data[3]
            let payloadLength = data.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            
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
        self.videoConnection?.cancel()
        self.videoConnection = connection
        
        connection.start(queue: serverQueue)
    }
    
    public func broadcastVideoFrame(naluData: Data, isKeyframe: Bool, pts: CMTime) {
        guard let connection = videoConnection else { return }
        
        // Construct 16-byte Video Header:
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
        
        connection.send(content: packet, completion: .idempotent)
    }
}
