# DisplayMac Binary Protocol Specification (v1.0)

This specification defines the wire protocol exchanged between **DisplayMacServer** (macOS host) and **DisplayMacClient** (Android client) across three TCP channels. All multi-byte integers and IEEE-754 floats are encoded in **Big-Endian** network byte order.

---

## 1. Transport Channels & Ports

| Port | Stream | Direction | Purpose |
| :--- | :--- | :--- | :--- |
| `7100` | Control & Input | Bidirectional | Capability handshake, keepalive ping/pong, keyframe requests, touch & stylus events |
| `7101` | Video | Host → Client | Annex-B HEVC video stream (IDR keyframes + P-frames) |
| `7102` | Audio | Host → Client | Uncompressed 48 kHz 16-bit stereo LPCM audio frames |

- **Discovery (Wi-Fi):** Host advertises Bonjour service type `_displaymac._tcp.` on port `7100`.
- **USB-C Link:** `adb reverse` maps `tcp:7100`, `tcp:7101`, and `tcp:7102` so the client connects over `127.0.0.1`.
- **Security Note:** Connections use plaintext TCP intended for USB-C loopback or trusted private LANs. Run `DisplayMacServer --usb-only` (or `./install.sh --usb-only`) to bind strictly to `127.0.0.1` and disable LAN exposure.

---

## 2. Control & Input Framing (Port `7100`)

Every control packet starts with an **8-byte header**:

```
 0                   1                   2                   3
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|          Magic (0x444D)       | Version (0x01)|   Msg Type    |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                      Payload Length (uint32)                  |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                         Payload Data...                       |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
```

- **Bounds:** `magic == 0x444D` (`"DM"`), `version == 0x01`, `0 <= payloadLength <= 65536`. Invalid headers close the connection immediately.

### Message Types

| Code | Name | Direction | Payload Size | Description |
| :--- | :--- | :--- | :--- | :--- |
| `0x01` | `ClientHello` | Client → Host | 18+ bytes | Display resolution, refresh rate, DPI, codec/feature flags, UTF-8 device name |
| `0x02` | `ServerConfig` | Host → Client | 14 bytes | Confirmed codec, active FPS, stream dimensions, bitrate (kbps) |
| `0x03` | `Ping` | Client → Host | 0 bytes | Periodic connection keepalive probe |
| `0x04` | `Pong` | Host → Client | 0 bytes | Keepalive response |
| `0x05` | `RequestKeyframe` | Client → Host | 0 bytes | Requests an immediate HEVC IDR keyframe |
| `0x10` | `TouchEvent` | Client → Host | 18 bytes | Finger touch, double-tap, right-click, scroll, drag, or zoom |
| `0x11` | `StylusEvent` | Client → Host | 18 bytes | Stylus proximity, hover, down/move/up, barrel button, pressure, tilt |

---

## 3. Handshake Payloads

### `ClientHello` (`0x01`)

| Offset | Field | Type | Constraints / Notes |
| :--- | :--- | :--- | :--- |
| `0` | `displayWidth` | `uint32` | Valid range: `320..7680` |
| `4` | `displayHeight` | `uint32` | Valid range: `320..7680` |
| `8` | `maxRefreshRate` | `uint32` | Valid range: `24..240` |
| `12` | `dpi` | `uint32` | Physical density DPI |
| `16` | `codecMask` | `uint8` | `0x01` = H.264, `0x02` = HEVC, `0x03` = AV1 |
| `17` | `flags` | `uint8` | Bit 0 = Stylus supported, Bit 1 = HDR |
| `18+` | `deviceName` | `utf8` (optional) | Up to 128 bytes UTF-8 device name (sanitized by host) |

### `ServerConfig` (`0x02`)

| Offset | Field | Type | Notes |
| :--- | :--- | :--- | :--- |
| `0` | `selectedCodec` | `uint8` | `0x02` = HEVC |
| `1` | `activeFps` | `uint8` | Active target frame rate |
| `2` | `streamWidth` | `uint32` | Virtual display width in pixels |
| `6` | `streamHeight` | `uint32` | Virtual display height in pixels |
| `10` | `targetBitrateKbps` | `uint32` | Encoder target bitrate in kbps (`60000` USB / `35000` Wi-Fi) |

---

## 4. Video Stream Framing (Port `7101`)

Each video packet begins with a **20-byte header**, followed by Annex-B (`0x00000001`-prefixed) HEVC NALUs (IDR frames prepend VPS/SPS/PPS):

```
 0                   1                   2                   3
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|          Magic (0x444D)       |  Frame Type   |     Codec     |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                        Sequence Number                        |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                    Presentation Timestamp (ns)                |
|                                                               |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                      Payload Length (uint32)                  |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                        Annex-B NALUs...                       |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
```

- **Frame Types:** `0x01` = Keyframe (IDR + parameter sets), `0x02` = P-frame.
- **Bounds:** `0 < payloadLength <= 16777216` (16 MiB).

---

## 5. Audio Stream Framing (Port `7102`)

Each audio packet carries an **8-byte header** followed by raw 48 kHz, 16-bit signed little-endian stereo LPCM samples:

```
 0                   1                   2                   3
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|          Magic (0x444D)       | FrameType(03) |   Reserved    |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                      Payload Length (uint32)                  |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                  48 kHz 16-bit Stereo LPCM...                 |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
```

- **Bounds:** `0 < payloadLength <= 262144` (256 KiB).

---

## 6. Input Payloads (`0x10` & `0x11`)

Both `TouchEvent` and `StylusEvent` use normalized coordinates `[0.0, 1.0]` mapped against the active macOS virtual display bounds.

### `TouchEvent` (`0x10`, 18 bytes)

| Offset | Field | Type | Notes |
| :--- | :--- | :--- | :--- |
| `0` | `action` | `uint8` | `1`=Tap, `2`=DoubleTap, `3`=RightClick, `4`=Scroll, `5`=DragStart, `6`=DragMove, `7`=DragEnd, `8`=Zoom |
| `1` | `phase` | `uint8` | `1`=Began, `2`=Changed, `3`=Ended, `4`=Cancelled |
| `2` | `normalizedX` | `float32` | `[0.0, 1.0]` |
| `6` | `normalizedY` | `float32` | `[0.0, 1.0]` |
| `10` | `deltaX` | `float32` | Horizontal scroll delta |
| `14` | `deltaY` | `float32` | Vertical scroll / pinch zoom delta |

### `StylusEvent` (`0x11`, 18 bytes)

| Offset | Field | Type | Notes |
| :--- | :--- | :--- | :--- |
| `0` | `action` | `uint8` | `1`=Down, `2`=Move, `3`=Up, `4`=Hover, `5`=HoverExit |
| `1` | `buttons` | `uint8` | Bit 0 = Primary barrel button (secondary click) |
| `2` | `normalizedX` | `float32` | `[0.0, 1.0]` |
| `6` | `normalizedY` | `float32` | `[0.0, 1.0]` |
| `10` | `pressure` | `float32` | `[0.0, 1.0]` |
| `14` | `tilt` | `float32` | Stylus tilt axis in radians |
