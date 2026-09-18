# JA LAN Messenger

[![Version](https://img.shields.io/badge/version-1.1.0-blue.svg)](CHANGELOG.md)
[![Flutter Version](https://img.shields.io/badge/Flutter-3.44.2-02569B?logo=flutter)](https://flutter.dev)
[![Dart Version](https://img.shields.io/badge/Dart-3.12.2-0175C2?logo=dart)](https://dart.dev)
[![Platform](https://img.shields.io/badge/Platform-Windows%2010%20%7C%2011-0078D6?logo=windows)](https://microsoft.com/windows)
[![Architecture](https://img.shields.io/badge/Architecture-Pure%20Dart%20P2P-brightgreen)](#)
[![License](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)

A modern, ultra-lightweight, high-performance **Peer-to-Peer (P2P) Office LAN Messenger** built with Flutter Desktop (Dart). Fully decentralized and serverless, inspired by and cross-compatible with **BeeBEEP (C++/Qt)**.

---

## ⚡ Key Highlights

- **Serverless Decentralized P2P**: Zero central server setup required. Instant plug-and-play communication in local networks.
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

---

## 📂 Project Structure

```text
JA_LAN_Messenger/
├── reference_sources/
│   └── beebeep/                # Cloned BeeBEEP C++ reference source
├── windows/
│   └── runner/                 # Native C++ Win32 runner with Acrylic & Aero Glass
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
├── build.bat                   # Release compiler
└── clean_project.bat           # Deep cleanup utility
```
