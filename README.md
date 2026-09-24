# JA LAN Messenger

[![Version](https://img.shields.io/badge/version-1.3.1-blue.svg)](CHANGELOG.md)
[![Flutter Version](https://img.shields.io/badge/Flutter-3.44.2-02569B?logo=flutter)](https://flutter.dev)
[![Dart Version](https://img.shields.io/badge/Dart-3.12.2-0175C2?logo=dart)](https://dart.dev)
[![Platform](https://img.shields.io/badge/Platform-Windows%2010%20%7C%2011-0078D6?logo=windows)](https://microsoft.com/windows)
[![Architecture](https://img.shields.io/badge/Architecture-Pure%20Dart%20P2P-brightgreen)](#)
[![License](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)

A modern, ultra-lightweight, high-performance **Peer-to-Peer (P2P) Office LAN Messenger** built with Flutter Desktop (Dart). Fully decentralized and serverless, inspired by and cross-compatible with **BeeBEEP (C++/Qt)**.

---

## ⚡ Key Highlights

- **Serverless Decentralized P2P**: Zero central server setup required. Instant plug-and-play communication in local networks.
- **Personal & Group Avatar Synchronization**: Custom image upload, rich preset icons, and color paletting with automatic ultra-lightweight Base64 LAN thumbnail synchronization across peers.
- **System Tray Icon Badge Counter**: Real-time unread message counter badge painted directly onto the Windows system tray icon via native Win32 GDI rendering.
- **Single-Instance Mutex & Window Focus**: Enforces single-instance execution via Windows Mutex (`main.cpp`), automatically waking and bringing the existing instance to the foreground when re-opened.
- **Comprehensive Group Chat Management**: Network-wide group dissolution synchronization, leave group, kick members, live typing indicators, and sound notifications for group conversations.
- **Hardware Tiering & Mini PC Optimization**: Auto-detects system CPU/GPU via Windows Registry and categorizes performance into Ultra, Medium, or Lite. Lite mode eliminates heavy backdrop blur for ultra-smooth operation on budget Mini PCs (e.g. Intel N100).
- **Showcase GlassDropdown**: Solid frosted glass popup menu for user status with zero background bleeding.
- **Auto-Scrolling Typing Indicator**: Chat automatically scrolls into view when a peer is typing.
- **Over-The-Air (OTA) LAN Updates**: Automated in-network update checker with configurable intervals (daily, weekly, monthly, off), SMB/UNC share sync, and 1-click self-updating handoff script.
- **One-Click Windows Installer & Uninstaller**: Full Control Panel / Windows Settings integration with Desktop/Start Menu shortcuts and clean self-cleaning uninstallation.
- **Staged Multi-File Attachments & Lightbox Preview**: Stage multiple files/images in the input composer before sending, complete with image zoom/lightbox and document preview dialogs.
- **Built-in Smart IME Engine**: Native Vietnamese Telex and Chinese Pinyin input support with zero external software needed and automatic bypass when system IME is active.
- **Dynamic AI Assistant (JA-AI)**: Native integration with local Ollama engine, automatic server model detection (`/api/tags`), smart capability heuristics (Vision, Thinking, Coder), live model switching, offline caching, and collapsible Thought Process markdown display.
- **Message Quoting & Multi-Message Pinning**: Direct quote reply with smooth auto-scroll to original message, multi-message pinning bar with counter and rapid navigation.
- **Ultra-Lightweight & Fast-Loading**: Pure Dart networking (`RawDatagramSocket`, `ServerSocket`, `Socket`). Minimal memory footprint (~40–60 MB RAM).
- **BeeBEEP Protocol Compatibility**: Uses standard ports (`36475` UDP discovery, `6475` TCP chat/control, `6476` TCP file transfer) with delimiter wire format (`\u2029`), enabling interoperability with native BeeBEEP desktop clients on the office network.
- **High-Speed File Transfer Engine**: Multi-megabyte/gigabyte binary chunk streaming (64 KB blocks) with real-time speed calculation, progress tracking, and direct local directory saving.
- **Bento Glassmorphism UI & Live Glass Tuning**: Compact default window (`960x640`), live tuning for card & dialog blur/opacity, optimized high-contrast dark theme, and adaptive styling for both **Windows 10** (Aero Blur) and **Windows 11** (Acrylic/Mica).
- **Persistent Chat History**: Safe atomic disk persistence with temp file replacement, storage size telemetry, and offline history restoration.
- **Security & Privacy**: Optional AES-256 (CBC mode) encryption with SHA-256 derived pre-shared workgroup keys.
- **Multi-language**: Full native support for Tiếng Việt (VI), English (EN), and 简体中文 (ZH).

---

## 📐 Network Architecture & Protocols

| Component | Protocol / Layer | Default Port | Functionality |
| :--- | :--- | :--- | :--- |
| **Peer Discovery** | UDP Broadcast & Multicast | `36475` | `255.255.255.255` & `224.0.64.75` announcing `BEE-BEEP` datagrams |
| **Messaging & Control** | TCP Streaming | `6475` | Handshake (`BEE-CIAO`), direct messaging (`BEE-CHAT`), ACK (`BEE-RECV`), Nudge (`BEE-BUZZ`) |
| **File Transfer** | TCP Binary Stream | `6476` | High-throughput 64 KB chunk streaming with metadata header |

---

## 🚀 Getting Started

### Prerequisites

- Flutter SDK `^3.44.2` / Dart `^3.12.2`
- Visual Studio 2022 with Desktop development with C++

### Quick Launch

Run the rapid start script:
```powershell
.\run.bat
```
or run manually:
```powershell
flutter run -d windows
```

### Production Release Build

To compile a standalone Windows executable:
```powershell
.\build.bat
```
The compiled binaries and shortcut `.Release - Shortcut.lnk` will be generated in:
```text
build\windows\x64\runner\Release\
```

### Installation & Uninstallation

`build.bat` packages Release into `dist` only after checking the EXE version, runtime files and ZIP hashes. Packaging failures stop the build script. Previous output is retained in `dist.previous-*`; temporary staging is retained in `.package-stage-*` for inspection. Release configuration and logs are not deleted or distributed. These retained directories use additional disk space and can be reviewed before manual cleanup.

- **One-Click Installation (`install.bat`)**:
  - Installs to `%LOCALAPPDATA%\Programs\JA_LAN_Messenger` without requiring administrator / UAC elevation.
  - Automatically creates Desktop and Start Menu shortcuts.
  - Registers the app in Windows **Control Panel (`Programs and Features`)** and **Windows Settings (`Installed apps`)**.
  - Close the installed app first. Portable instances are not force-stopped. Existing configuration is preserved; program files are backed up in `%TEMP%` before reinstalling.
- **Clean Uninstallation (`uninstall.bat`)**:
  - Can be triggered directly from **Control Panel**, Start Menu, or by executing `uninstall.bat`.
  - Supports interactive confirmation or silent execution (`/silent`).
  - Prompts to optionally preserve or purge user chat history and configuration (`%APPDATA%\JA_LAN_Messenger`).
  - Requires the registered installation path; refuses to remove portable/source folders. `/silent` preserves user data. Keep `uninstall.ps1` with the scripts.
- **Inno Setup Packaging (`windows/packaging/installer.iss`)**:
  - Separate Inno-managed installation in `%LOCALAPPDATA%\Programs\JA_LAN_Messenger_Setup`, with its own uninstaller. Compilation requires Inno Setup and has not been verified on this workstation.

---

## 📂 Project Structure

```text
JA_LAN_Messenger/
├── reference_sources/
│   └── beebeep/                # Cloned BeeBEEP C++ reference source
├── windows/
│   ├── runner/                 # Native C++ Win32 runner with Acrylic & Aero Glass
│   └── packaging/              # Inno Setup packaging script (installer.iss)
├── lib/
│   ├── main.dart               # App entry point
│   └── modules/
│       ├── constants.dart      # Global network ports & layout constants
│       ├── build_info.dart     # Dynamic build metadata
│       ├── logger_config.dart  # Production & debug logging
│       ├── window_helper.dart  # Window management helper
│       ├── theme/              # Bento Glass theme provider & token colors
│       ├── models/             # Data models (Peer, Message, FileTransferTask)
│       ├── network/            # Pure Dart P2P socket engines (UDP & TCP)
│       ├── services/           # MessengerCoordinator orchestrator
│       └── ui/                 # Compact UI (Sidebar, Peer list, Chat, Transfers, Settings)
├── run.bat                     # Rapid dev runner
├── build.bat                   # Release compiler & packager
├── install.bat                 # Standard Windows one-click installer
├── uninstall.bat               # Windows uninstaller (Control Panel integrated)
└── clean_project.bat           # Deep cleanup utility
```
