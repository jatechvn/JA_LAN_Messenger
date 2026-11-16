# Network layer (`lib/modules/network`)

Pure Dart P2P networking, BeeBEEP wire framing, key exchange, discovery, and file chunk streaming. All default ports are defined in [lib/modules/constants.dart](../constants.dart) (`36475` UDP, `6475` TCP chat, `6476` TCP file).

## Modules

| File | Responsibility |
| :--- | :--- |
| [protocol_beebeep.dart](protocol_beebeep.dart) | Wire framing (`\u2029` field separator, `\u2028` data separator), `BEE-CIAO`/`BEE-CHAT`/`BEE-GROU`/`BEE-RECV`/`BEE-READ`/`BEE-USER`/`BEE-FILE`/`BEE-BUZZ`/`BEE-PING`/`BEE-PONG`/`BEE-RCOV`/`BEE-REACT` builders/parsers, BeeBEEP auth hash |
| [beebeep_key_exchange.dart](beebeep_key_exchange.dart) | `BeebeepKeyExchange`: `sect163k1` ECDH over $GF(2^{163})$ + Base64URL + SHA3-256 session key derivation |
| [beebeep_session.dart](beebeep_session.dart) | `BeebeepSession`: encrypted TCP framing (16-bit HELLO prefix, 32-bit session prefix, AES-256-ECB via PointyCastle) |
| [lan_tcp_server.dart](lan_tcp_server.dart) | `LanTcpServer`: listener on TCP `6475` (fallback ports), HELLO handshake, routing ACK/READ/status/group/file packets |
| [lan_tcp_client.dart](lan_tcp_client.dart) | `LanTcpClient`: outbound TCP peer connection helper |
| [file_transfer_engine.dart](file_transfer_engine.dart) | `FileTransferEngine`: TCP `6476` 64 KB chunked upload/download with token verification and transfer ACK loop |
| [lan_discovery.dart](lan_discovery.dart) | `LanDiscoveryService` & `DiscoveryScanState`: UDP broadcast/multicast (`224.0.64.75`), NIC filtering, live scan phase progress |
| [subnet_sweep.dart](subnet_sweep.dart) | `SubnetSweep`: concurrent TCP port sweep across enabled IPv4 `/24` slices |
| [arp_resolver.dart](arp_resolver.dart) | `ArpResolver`: ARP table inspection helper for discovery reconciliation |
| [network_utils.dart](network_utils.dart) | `NetworkUtils`: adapter enumeration, subnet calculation, `parseIpv4Endpoint` (`IPv4` / `IPv4:port`), `isValidIp`, `compareIps` |
| [security_service.dart](security_service.dart) | `SecurityService`: optional AES-256 CBC pre-shared workgroup encryption |

## Cross-repo interop contract (`JA_LanMes_Cli`)

`JA_LanMes_Cli/tests/interop/` imports these four network files directly (alongside [peer_model.dart](../models/peer_model.dart) and [file_transfer_task.dart](../models/file_transfer_task.dart)):
- [protocol_beebeep.dart](protocol_beebeep.dart)
- [beebeep_session.dart](beebeep_session.dart)
- [lan_tcp_server.dart](lan_tcp_server.dart)
- [file_transfer_engine.dart](file_transfer_engine.dart)

Keep their paths, handshake semantics, `BEE-RECV`/`BEE-READ` ID-in-`text` format (`flags = 128`), and `IPv4:port` endpoint discrimination intact when refactoring.

## Verification

```powershell
flutter test test/protocol_test.dart test/beebeep_session_test.dart test/file_transfer_test.dart test/subnet_sweep_test.dart test/network_utils_test.dart test/manual_ip_add_and_new_friend_test.dart
```
