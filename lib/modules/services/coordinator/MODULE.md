# Coordinator extensions (`lib/modules/services/coordinator`)

Cohesive `extension ... on MessengerCoordinator` `part` modules belonging to [../messenger_coordinator.dart](../messenger_coordinator.dart). All public methods/getters stay on `MessengerCoordinator` as virtual instance members. Extracted implementations use private `_...Impl` helpers; keep calls to other public members routed through the class so overrides, `super`, tear-offs and `dynamic` retain their behavior. Lifecycle entrypoints and mutable fields also stay on the class. Do not import these files standalone.

Regression coverage: [coordinator_dispatch_test.dart](../../../../test/coordinator_dispatch_test.dart) checks wired TCP callbacks, dynamic access, navigation overrides, `super` calls, tear-offs and optional/async arguments.

| Part File | Extension Name | Responsibility |
| :--- | :--- | :--- |
| [coordinator_groups_part.dart](coordinator_groups_part.dart) | `MessengerCoordinatorGroups` | Group persistence, departures, `BEE-GROU` sync, roles & member management |
| [coordinator_presence_and_nic_part.dart](coordinator_presence_and_nic_part.dart) | `MessengerCoordinatorPresenceAndNic` | Physical identity consolidation, `knownDevices`, DHCP endpoint probing, NIC policy, `HELLO` handshake |
| [coordinator_messaging_part.dart](coordinator_messaging_part.dart) | `MessengerCoordinatorMessaging` | Direct/group/broadcast text send & receive, `BEE-RECV`/`BEE-READ`, typing, reactions, drafts |
| [coordinator_outbox_part.dart](coordinator_outbox_part.dart) | `MessengerCoordinatorOutbox` | Offline outbox queueing, periodic retry & peer reconnect flush |
| [coordinator_ai_and_ota_part.dart](coordinator_ai_and_ota_part.dart) | `MessengerCoordinatorAiAndOta` | Ollama AI prompt dispatch, locator recovery & OTA update checks |
| [coordinator_files_and_contacts_part.dart](coordinator_files_and_contacts_part.dart) | `MessengerCoordinatorFilesAndContacts` | Clipboard attachments, offline Buzz/WinRM launch, manual `IPv4[:port]`, pin/mute, incoming file completion |
