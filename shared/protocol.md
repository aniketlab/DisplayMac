# DisplayMac Binary Protocol Specification (v1.0)

This document defines the wire protocol used between the **macOS Server** (`DisplayMacServer`) and the **Android Client** (`DisplayMacClient`) over TCP/UDP channels.

---

## 1. Connection & Channels

DisplayMac operates over two logical streams:
1. **Control & Input Channel (TCP / Port 7100)**:
   - Client Handshake & Display Capability Negotiation (Resolution, Max Refresh Rate, Codecs).
   - Touch, Stylus (S-Pen), Keyboard, and Mouse Events.
   - Flow control, heartbeat, and on-demand IDR/Keyframe requests.
2. **Video Streaming Channel (TCP or Low-Latency UDP / Port 7101)**:
   - High-throughput video stream consisting of packetized NAL units (HEVC / H.264).

---

## 2. Message Framing (Control & Input Channel)

All control messages start with a fixed **8-byte header**:

```
 0                   1                   2                   3
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|          Magic (0x444D)       |   Version (1) |  Msg Type     |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                         Payload Length                        |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                        Payload Data...                        |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
```

- **Magic**: `0x444D` (ASCII `"DM"` for DisplayMac)
- **Version**: `0x01`
- **Msg Type** (1 byte):
  - `0x01`: **Client Hello / Handshake** (Tablet announces width, height, fps, supported codecs)
  - `0x02`: **Server Config / Ack** (Mac confirms virtual display bounds, chosen codec, bitrate)
  - `0x03`: **Heartbeat / Ping**
  - `0x04`: **Heartbeat / Pong**
  - `0x05`: **Request Keyframe (IDR)** (Sent by client on decoder packet drop or sync loss)
  - `0x10`: **Touch Event** (Multi-touch down/move/up)
  - `0x11`: **Stylus Event** (S-Pen coordinates, pressure, tilt, button state)
  - `0x12`: **Mouse / Trackpad Event** (Delta moves, scroll wheel, buttons)
  - `0x13`: **Keyboard Event** (Keycodes, modifiers)

---

## 3. Handshake Messages

### A. Client Hello (`0x01`)
Sent by the Android tablet immediately upon TCP connection:

| Offset | Field | Type | Description |
| :--- | :--- | :--- | :--- |
| 0 | `displayWidth` | `uint32_t` (Big Endian) | Screen width in pixels (e.g. `2960`) |
| 4 | `displayHeight` | `uint32_t` (Big Endian) | Screen height in pixels (e.g. `1848`) |
| 8 | `maxRefreshRate` | `uint32_t` (Big Endian) | Target refresh rate (e.g. `120`) |
| 12 | `dpi` | `uint32_t` (Big Endian) | Density (e.g. `280`) |
| 16 | `codecMask` | `uint8_t` | Bitmask: Bit 0 = H.264, Bit 1 = HEVC, Bit 2 = AV1 |
| 17 | `flags` | `uint8_t` | Bit 0 = Stylus Supported, Bit 1 = HDR10 Supported |

### B. Server Config (`0x02`)
Server response acknowledging setup:

| Offset | Field | Type | Description |
| :--- | :--- | :--- | :--- |
| 0 | `selectedCodec` | `uint8_t` | `1` = H.264, `2` = HEVC, `3` = AV1 |
| 1 | `activeFps` | `uint8_t` | Configured FPS (e.g. `120`) |
| 2 | `streamWidth` | `uint32_t` | Virtual display active width |
| 6 | `streamHeight` | `uint32_t` | Virtual display active height |
| 10 | `targetBitrateKbps` | `uint32_t` | Video bitrate (e.g. `80000` = 80 Mbps) |

---

## 4. Video Stream Framing (Port 7101)

Each video frame packet consists of a **16-byte Video Header** followed by raw H.264 / HEVC NALU data:

```
 0                   1                   2                   3
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|          Magic (0x444D)       |  Frame Type   |     Codec     |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                          Frame Index                          |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                    Presentation Timestamp (PTS)               |
|                                                               |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                         Payload Length                        |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                        NAL Units Data...                      |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
```

- **Frame Type**: `0x01` = IDR / Keyframe (contains SPS/PPS/VPS), `0x02` = P-Frame.
- **Codec**: `0x02` = HEVC, `0x01` = AVC.
- **Frame Index**: Incrementing sequence counter for loss detection.
- **PTS**: Nanosecond timestamp from host capture clock (used for jitter-free A/V sync and frame pacing).

---

## 5. Input Packets (Touch & S-Pen Stylus)

Coordinates are normalized as **32-bit Floating Point values** in the range `[0.0, 1.0]`, completely eliminating any screen resolution or scaling discrepancy between macOS and Android.

### Stylus Packet (`0x11`)
```
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
| Action (Down/Move/Up/Hover)   | Buttons State |    Reserved   |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                         Normalized X                          |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                         Normalized Y                          |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                    Pressure (0.0 to 1.0)                      |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                      Tilt (Degrees / Rad)                     |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
```

- **Action**:
  - `0x01`: Pen Down
  - `0x02`: Pen Move
  - `0x03`: Pen Up
  - `0x04`: Pen Hover (S-Pen floating over screen without contact)
- **Buttons**:
  - Bit 0 = S-Pen Barrel Button pressed (maps to Secondary Click / Right Click).
