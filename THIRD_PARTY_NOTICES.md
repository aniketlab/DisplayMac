# Third-Party Software Notices

DisplayMac incorporates or relies upon the following third-party open-source components:

---

## 1. BlackHole Virtual Audio Driver (`macos-server/Driver/DisplayMacAudio.c`)

- **Upstream Project:** [ExistentialAudio/BlackHole](https://github.com/ExistentialAudio/BlackHole)
- **Copyright:** Copyright (c) 2019 Existential Audio Inc.
- **License:** GNU General Public License v3.0 (GPL-3.0)
- **Usage in DisplayMac:** `macos-server/Driver/DisplayMacAudio.c` is derived from `BlackHole.c` and compiled by `macos-server/setup_dynamic_audio.sh` into an isolated CoreAudio HAL plugin bundle (`DisplayMacAudio.driver`) using `com.displaymac.audio` identifiers.
- **License Compliance Note:** As a derivative of BlackHole, `macos-server/Driver/DisplayMacAudio.c` and any compiled binaries built from it remain subject to the terms of **GPL-3.0**. The rest of the DisplayMac host (`macos-server/Sources/`) and Android client (`android-client/`) communicate with macOS CoreAudio purely through standard public system Audio HAL APIs as separate processes.

---

## 2. Protocol & Architecture Inspirations

- **[Genymobile/scrcpy](https://github.com/Genymobile/scrcpy)** (Apache-2.0): Architectural inspiration for `adb reverse` TCP tunneling over USB.
- **AndroidX, Material Components, Kotlin Coroutines** (Apache-2.0): Used via Gradle in `android-client/`.
