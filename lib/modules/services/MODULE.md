# Services & coordinator layer (`lib/modules/services`)

Application orchestration, device identity/presence policies, persistence, desktop power/tray management, OTA updates, local Ollama AI integration, and remote WinRM launch.

## Domain grouping

- **Core Orchestration**: [messenger_coordinator.dart](messenger_coordinator.dart) (`MessengerCoordinator`, `ToastData`, `PendingBuzzTarget`, `ManualAddStatus`, `ManualPeerResult`, all public virtual methods/getters & core lifecycle) + private implementation helpers in cohesive extension `part` modules in [coordinator/MODULE.md](coordinator/MODULE.md)
  - [coordinator/coordinator_groups_part.dart](coordinator/coordinator_groups_part.dart) — group sync, roles, departures
  - [coordinator/coordinator_presence_and_nic_part.dart](coordinator/coordinator_presence_and_nic_part.dart) — physical identity consolidation, `knownDevices`, DHCP probe, NIC policy, `HELLO` handshake
  - [coordinator/coordinator_messaging_part.dart](coordinator/coordinator_messaging_part.dart) — direct/group/broadcast text, ACK/READ receipts, typing, reactions, drafts
  - [coordinator/coordinator_outbox_part.dart](coordinator/coordinator_outbox_part.dart) — offline outbox queue, periodic retry & reconnect flush
  - [coordinator/coordinator_ai_and_ota_part.dart](coordinator/coordinator_ai_and_ota_part.dart) — Ollama AI dispatch, recovery & OTA checks
  - [coordinator/coordinator_files_and_contacts_part.dart](coordinator/coordinator_files_and_contacts_part.dart) — clipboard files, offline Buzz/WinRM launch, manual `IPv4[:port]`, pin/mute, incoming file completion
- **Identity, Presence & NIC Policy**: [known_devices_registry.dart](known_devices_registry.dart), [peer_session_registry.dart](peer_session_registry.dart), [network_preferences.dart](network_preferences.dart)
- **Persistence & Scroll Intent**: [app_preferences.dart](app_preferences.dart), [chat_history_service.dart](chat_history_service.dart), [conversation_scroll_store.dart](conversation_scroll_store.dart) (atomic `.tmp` + rename writes)
- **Power, Tray, Taskbar & Startup**: [app_power_manager.dart](app_power_manager.dart), [tray_badge_service.dart](tray_badge_service.dart), [tray_window_toggle.dart](tray_window_toggle.dart), [unread_attention_service.dart](unread_attention_service.dart), [app_icon_decoder.dart](app_icon_decoder.dart), [autostart_service.dart](autostart_service.dart)
- **OTA Updates**: [ota_update_service.dart](ota_update_service.dart), [ota_staging_cleanup.dart](ota_staging_cleanup.dart)
- **Local AI (Ollama / JA-AI)**: [ai_service.dart](ai_service.dart), [ai_queue_manager.dart](ai_queue_manager.dart), [ai_server_locator.dart](ai_server_locator.dart) — recovery first validates current addresses of online peers advertising the target hostname, then falls back to DNS/mDNS and a bounded hostname-checked scan. The AI port/path stays independent of the BeeBEEP chat port. New peer/address discovery invalidates the failed-recovery cooldown.
- **Files, Entities, Clipboard & Stickers**: [file_preview_inspector.dart](file_preview_inspector.dart), [folder_archive_helper.dart](folder_archive_helper.dart), [clipboard_image.dart](clipboard_image.dart), [image_clipboard_helper.dart](image_clipboard_helper.dart), [message_entity_detector.dart](message_entity_detector.dart), [quick_action_helper.dart](quick_action_helper.dart), [sticker_service.dart](sticker_service.dart)
- **WinRM Remote Launch**: [winrm_launcher_service.dart](winrm_launcher_service.dart), [windows_secret.dart](windows_secret.dart)

## Targeted verification

See [test/MODULE.md](../../../test/MODULE.md) for feature-specific suites (`presence_policy_regression_test`, `ota_update_service_test`, `app_power_manager_test`, `offline_message_retry_test`, `winrm_launcher_test`). Always isolate `APPDATA` when running coordinator tests.
