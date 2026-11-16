# Architecture & navigation map (`JA_LAN_Messenger`)

Desktop entrypoint flow: [lib/main.dart](../lib/main.dart) (`PowerAwareWidgetsBinding` + CWD exe anchor + `OtaStagingCleanup` post-frame cleanup) -> [lib/modules/ui/main_messenger_window.dart](../lib/modules/ui/main_messenger_window.dart) -> [lib/modules/services/messenger_coordinator.dart](../lib/modules/services/messenger_coordinator.dart) -> P2P sockets in [lib/modules/network/](../lib/modules/network/), Win32 runner in [windows/runner/](../windows/runner/), and Glassmorphic widgets in [lib/modules/ui/widgets/](../lib/modules/ui/widgets/).

Python CLI and SSH-only jumphost bridging live separately in the sibling `JA_LanMes_Cli` repository (`../PROJECT_PY/JA_LanMes_Cli`); direct LAN protocol interop is verified from `JA_LanMes_Cli/tests/interop/`.

## Module ownership & directory map

| Area | Path | Guide | Responsibility & Key Entrypoints |
| :--- | :--- | :--- | :--- |
| App bootstrap & core | [lib/main.dart](../lib/main.dart), [lib/modules/](../lib/modules/) | — | Startup orchestration (`JaLanMessengerApp`), [lib/modules/constants.dart](../lib/modules/constants.dart), [lib/modules/power_aware_binding.dart](../lib/modules/power_aware_binding.dart), [lib/modules/window_helper.dart](../lib/modules/window_helper.dart), [lib/modules/logger_config.dart](../lib/modules/logger_config.dart), [lib/modules/search_history_repository.dart](../lib/modules/search_history_repository.dart) |
| Data models | [lib/modules/models/](../lib/modules/models/) | — | `PeerModel`, `MessageModel`, `GroupModel`, `FileTransferTask`, `AiConfigModel` |
| Network & BeeBEEP wire | [lib/modules/network/](../lib/modules/network/) | [lib/modules/network/MODULE.md](../lib/modules/network/MODULE.md) | UDP `36475` discovery, TCP `6475` `sect163k1`/`AES-256-ECB` chat, TCP `6476` 64 KB file streaming, subnet sweep, `IPv4:port` parsing, `JA_LanMes_Cli` interop contract |
| Coordinator & services | [lib/modules/services/](../lib/modules/services/), [lib/modules/services/coordinator/](../lib/modules/services/coordinator/) | [lib/modules/services/MODULE.md](../lib/modules/services/MODULE.md), [lib/modules/services/coordinator/MODULE.md](../lib/modules/services/coordinator/MODULE.md) | `MessengerCoordinator` + 6 cohesive `part` extensions (groups, presence/NIC, messaging, outbox, AI/OTA, files/contacts), registries, atomic stores, power/tray, WinRM |
| Built-in IME engines | [lib/modules/ime/](../lib/modules/ime/) | — | Pure Dart Vietnamese Telex, Chinese Pinyin + dictionary, external IME auto-bypass (`ImeService`) |
| Localization | [lib/modules/localization/](../lib/modules/localization/) | — | Trilingual (`VI`/`EN`/`ZH`) lookup table (`LanguageProvider`) |
| Theme & glass tokens | [lib/modules/theme/](../lib/modules/theme/) | — | Dark Bento Glass tokens (`AppColors`, `ThemeProvider`, Windows 10 Aero / Windows 11 Acrylic styles) |
| Utilities | [lib/modules/utils/](../lib/modules/utils/) | — | Avatar preset & Base64 helpers ([lib/modules/utils/avatar_utils.dart](../lib/modules/utils/avatar_utils.dart)) |
| Window shell & widgets | [lib/modules/ui/](../lib/modules/ui/), [lib/modules/ui/widgets/](../lib/modules/ui/widgets/), [lib/modules/ui/widgets/chat_view/](../lib/modules/ui/widgets/chat_view/), [lib/modules/ui/widgets/peer_list/](../lib/modules/ui/widgets/peer_list/), [lib/modules/ui/widgets/settings/](../lib/modules/ui/widgets/settings/) | [lib/modules/ui/widgets/MODULE.md](../lib/modules/ui/widgets/MODULE.md), [lib/modules/ui/widgets/chat_view/MODULE.md](../lib/modules/ui/widgets/chat_view/MODULE.md), [lib/modules/ui/widgets/peer_list/MODULE.md](../lib/modules/ui/widgets/peer_list/MODULE.md) | Main window (`MainMessengerWindow`), compact mode, virtualized peer list + `part` widgets, chat panel + `part` widgets, settings tabs, glass primitives |
| Native Windows runner | [windows/runner/](../windows/runner/), [windows/flutter/](../windows/flutter/) | [windows/runner/MODULE.md](../windows/runner/MODULE.md) | Win32 single-instance mutex (`windows/runner/main.cpp`), DWM blur, `KeyboardReentrancyGuard`, `FlashWindowEx`, `AssocQueryStringW`, plugin registrant |
| Packaging & root scripts | [windows/packaging/](../windows/packaging/), [tool/](../tool/) | — | Release bundler ([windows/packaging/package_dist.ps1](../windows/packaging/package_dist.ps1)), [build.bat](../build.bat), [install.bat](../install.bat), [uninstall.bat](../uninstall.bat), [uninstall.ps1](../uninstall.ps1), [verify_scan.ps1](../verify_scan.ps1), sticker/taskbar tools; legacy [deploy_release_v1.6.0.ps1](../deploy_release_v1.6.0.ps1) (do not run) |
| Automated test suite | [test/](../test/) | [test/MODULE.md](../test/MODULE.md) | 96 Dart unit/widget/integration tests, PowerShell installer/packaging smoke scripts, MSVC keyboard guard harness |

## Product & handoff references

- Operational & safety rules: [AGENTS.md](../AGENTS.md)
- Product feature specification & user manual: [USERGUIDE.md](../USERGUIDE.md), [ABOUT.txt](../ABOUT.txt), [README.md](../README.md)
- Active engineering handoff & recent verification ledger: [AI_HANDOFF.md](AI_HANDOFF.md)
