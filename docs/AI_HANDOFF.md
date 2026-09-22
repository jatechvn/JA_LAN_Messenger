# Handoff: nickname and native keyboard crash (2026-09-21)

## Nickname
- Confirmed profile updates previously changed memory only.
- AppPreferences now persists localNickname; coordinator restores it after startup preferences load.
- Immediate UI notification retained before asynchronous save.
- Analyzer clean; nickname persistence and incoming-toast suites: 4 tests passed.
- Source change only; not built or deployed. Previously lost nickname must be set once again.

## Remote crash evidence
- Authorized WinRM diagnosis: 172.21.171.29. No deployment or process termination performed.
- Windows 10 IoT Enterprise LTSC, build 19044; app 1.2.0.3.
- Event 1000: flutter_windows.dll + 0x29679, exception 0xC0000005.
- Remote DLL SHA256 matches local Release: 011E87E890B7BFBAC89F63C763341FFB8393D2B4A617DD836C471A0CDAA1346F.
- Local matching PDB maps this RVA to flutter::KeyboardManager::HandleOnKeyResult + 37.
- Remote minidump exception reads address 0xFFFFFFFFFFFFFFE8; RAX=0.
- Disassembly at fault: mov eax,dword ptr [rax-18h], immediately after loading PendingEvent.session vector end. Consistent with an empty/null event session, not enough evidence to establish why it became empty.
- EVKey64 is running on affected machine. This is correlation, not proof EVKey caused crash.
- Engine stamp: 77e2e94772b6eb43759e34ed1ad7da4674e19cab.
- SDK engine source HandleOnKeyResult reads event->session.back() without an empty guard. Candidate hardening needs a custom engine build and native keyboard regression tests; a Dart change cannot guard this access.
- Engine checkout lacks buildtools/windows-x64/gn.exe, third_party/dart and out; no native engine build performed.
- No dump copied: read only exception metadata/registers remotely, no chat/memory contents exported.

## Next
1. Confirm reproduction gesture and whether it persists without external IME (requires user coordination; do not terminate EVKey silently).
2. Prepare isolated engine build or verify a compatible upstream engine fix; test keyboard input, repeated callbacks and event lifetime, not merely suppress the exception.
3. Build app with nickname fix after reviewing other uncommitted UI/performance changes; no release/tag actions authorized.

## User A/B observation (2026-09-21)
- User reports no further crash after exiting EVKey on the affected machine.
- Together with the native keyboard fault, this strengthens the external-input interaction hypothesis; duration and exact reproducer remain unknown.
- Temporary workaround: keep EVKey exited while testing and use the app's Telex mode if Vietnamese input is needed.
- Existing external-IME bypass only disables the Dart formatter. It does not bypass Flutter's native keyboard manager and is not a crash fix.
- No new engine binary has been built, patched or deployed. Do not describe this as a completed compatibility fix.

## Runner mitigation built (2026-09-21)
- User clarified reproduction uses VNC from a controller running EVKey, and reports no crash after disabling VNC. Do not attribute specifically to target-local EVKey.
- Added KeyboardReentrancyGuard on Flutter child HWND via SetWindowSubclass. Nested keyboard messages are deferred until outer processing unwinds; remaining messages retain order/parameters.
- No binary patch or SDK changes. Linked comctl32 in runner.
- Native MSVC /W4 /WX test passes baseline nested-input detection, deferred order, cross-thread SendMessage during PeekMessage, and pending-window teardown.
- Dart analyzer clean; Flutter Windows Release build succeeded (42.6 sec).
- Mitigation addresses reentrant message delivery inferred from source and observed VNC conditions; actual VNC/EVKey crash reproduction still needs user confirmation.
- Copied 20 runtime files to target Desktop/JA_LAN_Messenger_VNC_Test_20260921_095543; all hashes matched. Not launched remotely and installed app unchanged. Earlier incomplete folder from WinRM OneDrive-attribute error was left intact.
- New Release includes nickname persistence and user's existing uncommitted UI/performance changes. No version bump, commit, tag or dist publication.

## Hardware performance verification (2026-09-21)
- Reviewed supplied hardware optimization walkthrough against current source; earlier claimed full-suite/build results are not new evidence for this patch.
- Fixed initialization of dropdown tier parameters even when custom card tuning exists, Lite blur getters overriding old saved blur, and persisted glass reset (null arguments previously did nothing). Preferences reset now also resets performance mode.
- Preserved rounded child clipping in GlassSurface zero-blur path. Settings modal respects effective Lite blur.
- setPerfTierMode now exposes its save Future; focused tests await persistence to avoid deleting their temporary directory while a save is pending.
- Focused performance suite: 14 tests pass, including disk reload and cleared tuning regressions. Dart analyzer clean. Tests use isolated AppData and temporary preference files.
- No new build/deployment in this verification. Actual N100 frame timing and VNC behavior remain untested.
- Scope limits: score is a heuristic, not an FPS benchmark; GPU query uses registry adapter 0000, which need not be the renderer adapter on multi-GPU PCs. Synchronous registry calls have no proven <15ms bound. Several auxiliary overlays still use explicit blur constants, so Lite is not globally zero-blur and zero-lag is not a verified guarantee.

## OTA update text verification (2026-09-21)
- Reviewed commit 674eec6, which formats the update version through LanguageProvider.tr at toast, badge tooltip, update dialog and manual-check result.
- Confirmed all updateAvailable call sites pass a version argument. Toast normalizes both `1.2.1` and `v1.2.1` to one `v` prefix.
- Focused locale and OTA suites pass 31 tests; `dart analyze lib test` is clean.
- No source change, build, package, remote update check, or deployment was performed in this verification. Windows visual and live SMB-update testing remain manual checks.

## Feature upgrade verification and fixes (2026-09-22)
- Re-audited the uncommitted single-instance, avatar, group-management, tray-badge, and OTA/UI changes instead of relying only on the supplied walkthrough.
- Fixed stale group-member rendering in `GroupMembersDialog`, excluded the `All Users` pseudo-group from group-only header/details actions, removed duplicate tray listener registration, restored avatar metadata through `PeerModel.copyWith`, and cleared stale remote avatar metadata when switching to initials.
- Added the member-search clear action and VI/EN/ZH translations, plus avatar regression coverage.
- Targeted suites: 51 tests passed. Full suite: 293 passed, 3 skipped. `flutter analyze`: clean. Windows Release build succeeded and compiled the native runner changes.
- Remaining manual checks: launch two Windows instances to verify focus redirection, inspect tray icon/menu on Windows, and run a real LAN peer exchange. Custom avatar files remain local; the handshake advertises color/preset metadata only, not image bytes.

## Light-theme avatar and group workflow fixes (2026-09-22)
- Avatar/member/create-group foregrounds now follow ThemeProvider; light-mode member search hints have a tested contrast ratio above 4.5:1 on white. Added opt-in scrollable content to GlassDialog after widget tests reproduced overflow at 800x600. The create-group clear action now resets both the filter and visible text.
- Group storage continues to contain remote members only. A shared coordinator member-list accessor adds the local user for dialogs/details, while counts include self across the sidebar/header/details. Self is not removable via member-list actions. The add picker reads current membership instead of its opening PeerModel snapshot.
- Implemented native BeeBEEP BEE-GROU requests and GroupChat data/flag routing, based on reference_sources/beebeep/src/core/Protocol.cpp. Create/add broadcasts recipient-specific member records; authenticated reconnection resends the current snapshot. Persisted user hashes resolve previously undiscovered members and endpoint changes. Group messages route by stable group ID, not display name; duplicate received IDs are ignored. Invalid packets, stale updates and existing-group updates from non-members are rejected.
- Added @user autocomplete above the composer, with Unicode names, caret-aware insertion and IME/email guards. Mentions remain interoperable plain-text @name (no separate identity-based mention payload or special notification preference).
- Added isolated group_sync_and_ui_test.dart: 9 tests cover invitation/update records, self counts, hash resolution, persistence/reconnect, duplicate group names, malformed data, light/dark dialogs, mention insertion, and encrypted loopback TCP dispatch. New constructor dependency injection keeps test device registries and transport isolated.
- Verification: full suite 302 passed / 3 skipped using temporary APPDATA; dart analyze lib test clean; git diff --check clean. The final contrast adjustment passed all 9 new tests again. Windows Release build succeeded; no commit, release or deployment requested.
- Remaining manual checks: run the updated app on two LAN machines, create/invite/reconnect and exchange @mentions; verify native desktop notification behavior and actual original-BeeBEEP group interoperability. Older JA builds that ignore native group packets must be updated. This is snapshot synchronization, not a durable delivery/ACK queue; offline removal/leave conflict handling is not fully implemented. Native group file-transfer routing is outside this text-chat change.

## Final review fixes after Gemini/Grok (2026-09-22)
- User requested direct Codex implementation; the delegated agy CLI process was interrupted and confirmed stopped before edits. It had not modified source. Existing unrelated changes remain uncommitted and preserved.
- Roster updates now retain local unreadCount, lastMessage and lastMessageTime, including persisted metadata.
- Corrected BeeBEEP group control flags: Refused=32 removes the sender; Delete=512 removes the recipient. Native controls with an empty group revision are supported. A plain Delete no longer means global disband. JA disband uses Delete plus an explicit fifth ChatMessageData field (`ja-group-v1:disband`); original BeeBEEP reads the first four fields and still removes its local recipient normally. Legacy incorrect Auto/Important flags (1024/2048) are no longer used.
- Explicit per-recipient invitations have a persisted issuance time and a separate JA metadata marker. Ordinary snapshots/reconnect retries retain the original invitation time. Departure records persist a cutoff and prior member identities; only a newer explicit invitation from a prior member can rejoin a left/kicked group. Malformed snapshots do not clear departure state, replayed old invitations remain rejected, and disband stays terminal. Older ID-only departure files are migrated once. Native BeeBEEP has no distinct re-invite marker, so automatic re-invitation after departure requires updated JA senders; ordinary native snapshots intentionally do not bypass a departure.
- Added seven regressions using literal native control fixtures as well as JA flows: metadata persistence, native Refused/Delete, outgoing wire flags, restart/replay/outsider rejection, explicit re-invitation after kick, terminal disband, and per-recipient persisted invite timestamps. Corrected lifecycle test descriptions for native flag values.
- Verified: full suite 327 passed / 3 skipped using temporary APPDATA; `dart analyze lib test` clean; `git diff --check` clean; Windows Release build succeeded at `build/windows/x64/runner/Release/ja_lan_messenger.exe`. No commit, push or deployment.
- Still manual: real two-machine LAN and original BeeBEEP UI exchange. All JA clients should be updated together. Timestamp ordering assumes reasonably synchronized clocks. This does not add a durable ACK queue for offline kicks or implement group owner/admin permissions.

## Personal/group avatar walkthrough review (2026-09-22)
- Reviewed the newly supplied avatar walkthrough against current source. Verification only: application source was not changed in this review.
- Confirmed defects: `updateGroupAvatar` passes null to `GroupModel.copyWith`, which retains old Base64; selecting a preset after a custom group image therefore continues displaying/sending the old image. Nullable avatar fields need explicit clearing semantics.
- Native BeeBEEP compatibility remains incomplete: JA sends a UserVCard-flagged packet with a single `avatar:...` data field and a prefixed image payload. The reference `Protocol::changeVCardFromMessage` requires at least five data fields and plain PNG Base64 in text; it rejects this packet. JA also ignores native vCard ID 16 without the JA marker. This is not a verified interoperable avatar exchange.
- Existing custom personal avatars have no thumbnail migration: old preferences contain a path but no `userAvatarBase64`; HELLO advertises initials until the user saves the avatar again.
- Group avatar picker receives only preset/path/color, not the received Base64. A remote custom group avatar therefore opens as the default game preset, with a misleading preview. Correct clearing semantics should be accompanied by a picker fix so confirming a color change preserves the remote image.
- Verification: avatar and group-sync suites 38 passed; `dart analyze lib test` clean; full suite 337 passed / 3 skipped using isolated temporary APPDATA. The supplied total 327/327 does not describe the current checkout. Some tests emit handled plugin/temporary-file diagnostics; the test runner still exits successfully.
- No Windows build, live UI, two-machine LAN, original BeeBEEP exchange, commit, or deployment performed. Next: fix these avatar state/protocol/migration gaps and add transition and native-wire regression tests before claiming the walkthrough complete.
