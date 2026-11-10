import Foundation
import Network
import CoreMedia
import DisplayMacProtocol

public protocol NetworkServerDelegate: AnyObject {
    func networkServer(_ server: NetworkServer, didConnectClient hello: ClientHello, isLoopback: Bool)
    func networkServerDidDisconnectClient(_ server: NetworkServer)
    func networkServerDidRequestKeyframe(_ server: NetworkServer)
}

public final class NetworkServer {
    public weak var delegate: NetworkServerDelegate?

    private var controlListener: NWListener?
    private var videoListener: NWListener?
    private var audioListener: NWListener?

    private var controlConnection: NWConnection?
    private var videoConnection: NWConnection?
    private var audioConnection: NWConnection?

    private let serverQueue = DispatchQueue(label: "com.displaymac.network.server", qos: .userInteractive)
    private let audioQueue = DispatchQueue(label: "com.displaymac.network.audio", qos: .userInteractive)
    private let stateLock = NSLock()

    private var _isClientLoopback = false
    public var isClientLoopback: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _isClientLoopback
    }

    private var frameSequenceNumber: UInt32 = 0
    private var inFlightFrames = 0
    private var totalBytesSent: UInt64 = 0
    private var lastSpeedCheck = Date()
    private var lastBytesCount: UInt64 = 0

    public init() {}

    private static func createTcpParameters(localPortForLoopbackOnly: UInt16? = nil) -> NWParameters {
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.noDelay = true
        tcpOptions.enableKeepalive = true
        tcpOptions.keepaliveIdle = 2
        let params = NWParameters(tls: nil, tcp: tcpOptions)
        params.allowLocalEndpointReuse = true
        if let port = localPortForLoopbackOnly, let nwPort = NWEndpoint.Port(rawValue: port) {
            params.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: nwPort)
        }
        return params
    }

    private static func resolveBonjourHostName() -> String {
        let rawHost = ProcessInfo.processInfo.hostName
            .replacingOccurrences(of: ".local", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return rawHost.isEmpty ? "DisplayMac Host" : rawHost
    }

    public func start(
        controlPort: UInt16 = ProtocolConstants.controlPort,
        videoPort: UInt16 = ProtocolConstants.videoPort,
        audioPort: UInt16 = ProtocolConstants.audioPort,
        bindLocalhostOnly: Bool = false
    ) throws {
        // Control channel listener (Port 7100)
        let cParams = NetworkServer.createTcpParameters(
            localPortForLoopbackOnly: bindLocalhostOnly ? controlPort : nil
        )
        let cListener = if bindLocalhostOnly {
            try NWListener(using: cParams)
        } else {
            try NWListener(using: cParams, on: NWEndpoint.Port(rawValue: controlPort)!)
        }

        if !bindLocalhostOnly {
            cListener.service = NWListener.Service(
                name: NetworkServer.resolveBonjourHostName(),
                type: ProtocolConstants.bonjourServiceType
            )
        }

        cListener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                let scope = bindLocalhostOnly ? "127.0.0.1" : "0.0.0.0"
                print("[Network] Control channel listening on \(scope):\(controlPort)")
            case .failed(let error):
                print("[Network] Control listener failed: \(error)")
            default:
                break
            }
        }
        cListener.newConnectionHandler = { [weak self] connection in
            self?.handleNewControlConnection(connection)
        }
        cListener.start(queue: serverQueue)
        self.controlListener = cListener

        // Video channel listener (Port 7101)
        let vParams = NetworkServer.createTcpParameters(
            localPortForLoopbackOnly: bindLocalhostOnly ? videoPort : nil
        )
        let vListener = if bindLocalhostOnly {
            try NWListener(using: vParams)
        } else {
            try NWListener(using: vParams, on: NWEndpoint.Port(rawValue: videoPort)!)
        }
        vListener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("[Network] Video channel listening on port \(videoPort)")
            case .failed(let error):
                print("[Network] Video listener failed: \(error)")
            default:
                break
            }
        }
        vListener.newConnectionHandler = { [weak self] connection in
            self?.handleNewVideoConnection(connection)
        }
        vListener.start(queue: serverQueue)
        self.videoListener = vListener

        // Audio channel listener (Port 7102)
        let aParams = NetworkServer.createTcpParameters(
            localPortForLoopbackOnly: bindLocalhostOnly ? audioPort : nil
        )
        let aListener = if bindLocalhostOnly {
            try NWListener(using: aParams)
        } else {
            try NWListener(using: aParams, on: NWEndpoint.Port(rawValue: audioPort)!)
        }
        aListener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("[Network] Audio channel listening on port \(audioPort)")
            case .failed(let error):
                print("[Network] Audio listener failed: \(error)")
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
        serverQueue.async { [weak self] in
            self?.controlConnection?.cancel()
            self?.videoConnection?.cancel()
            self?.controlListener?.cancel()
            self?.videoListener?.cancel()
            self?.controlConnection = nil
            self?.videoConnection = nil
            self?.inFlightFrames = 0
        }
        audioQueue.async { [weak self] in
            self?.audioConnection?.cancel()
            self?.audioListener?.cancel()
            self?.audioConnection = nil
        }
    }

    // MARK: - Control Connection Handling (serverQueue)
    private func handleNewControlConnection(_ connection: NWConnection) {
        print("[Network] Client connected on control channel: \(connection.endpoint)")
        if let old = self.controlConnection {
            old.stateUpdateHandler = nil
            old.cancel()
        }
        self.controlConnection = connection

        let loopback = Self.isEndpointLoopback(connection.endpoint)
        stateLock.lock()
        _isClientLoopback = loopback
        stateLock.unlock()

        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .failed(let error):
                print("[Network] Control connection failed: \(error)")
                guard self.controlConnection === connection else { return }
                self.controlConnection = nil
                self.delegate?.networkServerDidDisconnectClient(self)
            case .cancelled:
                print("[Network] Control connection closed")
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

    private static func isEndpointLoopback(_ endpoint: NWEndpoint) -> Bool {
        switch endpoint {
        case .hostPort(let host, _):
            let hostStr = "\(host)"
            return hostStr == "127.0.0.1" || hostStr == "::1" || hostStr.contains("127.0.0.1")
        default:
            return false
        }
    }

    private func readControlHeader(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 8, maximumLength: 8) { [weak self] content, _, isComplete, error in
            guard let self = self, let data = content, data.count == 8, error == nil else {
                if isComplete || error != nil { connection.cancel() }
                return
            }

            let magic = data.readUInt16BE(at: 0)
            let version = data[2]
            let msgTypeRaw = data[3]
            let payloadLengthBE = data.readUInt32BE(at: 4)

            guard magic == ProtocolConstants.magic, version == ProtocolConstants.currentVersion else {
                print("[Network] Dropping connection: invalid protocol header (magic=\(magic) version=\(version))")
                connection.cancel()
                return
            }

            guard payloadLengthBE <= UInt32(ProtocolConstants.maxControlPayloadBytes) else {
                print("[Network] Dropping connection: control payload length out of bounds (\(payloadLengthBE))")
                connection.cancel()
                return
            }

            let payloadLength = Int(payloadLengthBE)
            if payloadLength == 0 {
                self.handleControlMessage(msgType: msgTypeRaw, payload: Data())
                self.readControlHeader(connection)
            } else {
                self.readControlPayload(connection, msgType: msgTypeRaw, length: payloadLength)
            }
        }
    }

    private func readControlPayload(_ connection: NWConnection, msgType: UInt8, length: Int) {
        connection.receive(minimumIncompleteLength: length, maximumLength: length) { [weak self] content, _, isComplete, error in
            guard let self = self, let payload = content, payload.count == length, error == nil else {
                if isComplete || error != nil { connection.cancel() }
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
                print("[Network] Received ClientHello: \(hello.displayWidth)x\(hello.displayHeight) @ \(hello.maxRefreshRate)Hz (DPI: \(hello.dpi))")
                let loopback = self.isClientLoopback
                delegate?.networkServer(self, didConnectClient: hello, isLoopback: loopback)
            } else {
                print("[Network] Ignored invalid ClientHello payload")
            }

        case .requestKeyframe:
            print("[Network] Client requested IDR keyframe")
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
            sendPongLockedOnServerQueue()

        default:
            break
        }
    }

    public func sendServerConfig(_ config: ServerConfig) {
        serverQueue.async { [weak self] in
            guard let self = self, let connection = self.controlConnection else { return }

            let payload = config.serialize()
            var packet = Data(capacity: 8 + payload.count)
            packet.appendUInt16BE(ProtocolConstants.magic)
            packet.append(ProtocolConstants.currentVersion)
            packet.append(MessageType.serverConfig.rawValue)
            packet.appendUInt32BE(UInt32(payload.count))
            packet.append(payload)

            connection.send(content: packet, completion: .contentProcessed({ error in
                if let error = error {
                    print("[Network] Failed to send ServerConfig: \(error)")
                }
            }))
        }
    }

    private func sendPongLockedOnServerQueue() {
        guard let connection = controlConnection else { return }
        var packet = Data(capacity: 8)
        packet.appendUInt16BE(ProtocolConstants.magic)
        packet.append(ProtocolConstants.currentVersion)
        packet.append(MessageType.pong.rawValue)
        packet.appendUInt32BE(0)
        connection.send(content: packet, completion: .idempotent)
    }

    // MARK: - Video Connection Handling (serverQueue)
    private func handleNewVideoConnection(_ connection: NWConnection) {
        print("[Network] Client connected on video channel: \(connection.endpoint)")
        if let old = self.videoConnection {
            old.stateUpdateHandler = nil
            old.cancel()
        }
        self.videoConnection = connection
        self.inFlightFrames = 0

        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .failed(let error):
                print("[Network] Video connection failed: \(error)")
                guard self.videoConnection === connection else { return }
                self.videoConnection = nil
                self.inFlightFrames = 0
            case .cancelled:
                print("[Network] Video connection closed")
                guard self.videoConnection === connection else { return }
                self.videoConnection = nil
                self.inFlightFrames = 0
            default:
                break
            }
        }

        connection.start(queue: serverQueue)
    }

    public func broadcastVideoFrame(naluData: Data, isKeyframe: Bool, pts: CMTime) {
        serverQueue.async { [weak self] in
            guard let self = self,
                  let connection = self.videoConnection,
                  connection.state == .ready else { return }

            let effectiveMaxInFlight = self.isClientLoopback ? 1 : 2
            if self.inFlightFrames >= effectiveMaxInFlight && !isKeyframe {
                return
            }

            var packet = Data(capacity: 20 + naluData.count)
            packet.appendUInt16BE(ProtocolConstants.magic)

            let frameType: UInt8 = isKeyframe ? FrameType.keyframe.rawValue : FrameType.pFrame.rawValue
            packet.append(frameType)
            packet.append(VideoCodec.hevc.rawValue)

            packet.appendUInt32BE(self.frameSequenceNumber)
            self.frameSequenceNumber &+= 1

            let ptsSeconds = CMTimeGetSeconds(pts)
            let ptsNanoseconds = ptsSeconds.isFinite && ptsSeconds >= 0 ? UInt64(ptsSeconds * 1_000_000_000) : 0
            packet.appendUInt64BE(ptsNanoseconds)
            packet.appendUInt32BE(UInt32(naluData.count))
            packet.append(naluData)

            self.totalBytesSent += UInt64(packet.count)
            let now = Date()
            let elapsed = now.timeIntervalSince(self.lastSpeedCheck)
            if elapsed >= 2.0 {
                let bytes = self.totalBytesSent - self.lastBytesCount
                let mbps = (Double(bytes) * 8.0) / (elapsed * 1_000_000.0)
                self.lastBytesCount = self.totalBytesSent
                self.lastSpeedCheck = now
                print(String(format: "[Throughput] %.1f Mbps video stream", mbps))
            }

            self.inFlightFrames += 1
            connection.send(content: packet, completion: .contentProcessed({ [weak self] _ in
                guard let self = self else { return }
                self.inFlightFrames = max(0, self.inFlightFrames - 1)
            }))
        }
    }

    // MARK: - Audio Connection Handling (audioQueue)
    private func handleNewAudioConnection(_ connection: NWConnection) {
        print("[Network] Client connected on audio channel: \(connection.endpoint)")
        if let old = self.audioConnection {
            old.stateUpdateHandler = nil
            old.cancel()
        }
        self.audioConnection = connection

        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .failed(let error):
                print("[Network] Audio connection failed: \(error)")
                guard self.audioConnection === connection else { return }
                self.audioConnection = nil
            case .cancelled:
                print("[Network] Audio connection closed")
                guard self.audioConnection === connection else { return }
                self.audioConnection = nil
            default:
                break
            }
        }

        connection.start(queue: audioQueue)
    }

    public func broadcastAudioFrame(pcmData: Data) {
        audioQueue.async { [weak self] in
            guard let self = self,
                  let connection = self.audioConnection,
                  connection.state == .ready else { return }

            var packet = Data(capacity: 8 + pcmData.count)
            packet.appendUInt16BE(ProtocolConstants.magic)
            packet.append(FrameType.audio.rawValue)
            packet.append(0x00)
            packet.appendUInt32BE(UInt32(pcmData.count))
            packet.append(pcmData)

            connection.send(content: packet, completion: .idempotent)
        }
    }
}
