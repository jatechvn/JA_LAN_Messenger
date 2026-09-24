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

## Avatar display and group authorization review (2026-09-23)
- Reviewed the supplied follow-up walkthrough against HEAD a1a07f0 (v1.3.0) and the ten currently modified source/test files. No production source changes made during this review.
- The four previously reported avatar gaps have code/test fixes in HEAD: explicit null clearing, native vCard fields/parsing, startup migration, and Base64 picker preview/preservation. New changes consistently use AppAvatar in the main/compact contact lists, group list and contact profile, and prioritize the AI asset.
- P1: disband authorization trusts packet-provided `meta.creatorId` as an alternative to the sender identity. A regular member can append the real owner's public ID to a disband packet and delete the group on the recipient.
- P1: ordinary snapshots from any current member overwrite `creatorId` with `meta.creatorId`. A member can set it to their own hash and become an admin according to isAdmin; ownership must not be replaceable by an ordinary roster/avatar update.
- P1: inbound plain Delete/kick has no admin check, and removeGroupMember has no local permission guard. A non-admin can kick even the creator; hidden UI buttons do not enforce wire authorization.
- Reproduced all three permission defects with isolated in-memory peers in `.dart_tool/review_group_permissions_test.dart`. Its three passing diagnostic assertions confirm the defective behavior, not a successful security check. No real LAN packets were sent.
- P2 mixed-version regression: new _syncGroup sends 4 base fields plus invitation, avatar and creator (7 fields) for locally created groups. The released v1.3.0 parser at HEAD rejects more than 6 fields, so its recipients ignore these invitations/updates. Need compatible encoding/capability negotiation or an explicit coordinated-upgrade requirement.
- Verification: full existing suite 348 passed / 3 skipped; `dart analyze lib test` clean; `git diff --check` clean. The walkthrough omits the three skipped tests. No native Windows build/UI or real BeeBEEP/LAN verification performed.
- Next: enforce sender-based owner/admin checks for disband/kick/roster changes, preserve established ownership, address mixed-version metadata, and convert the diagnostic reproductions into denial regression tests.

## Group authorization fixes (2026-09-23)
- Implemented the follow-up fixes. Disband and kick now check the sending member against stored ownership/admin identities; packet-supplied creator metadata never grants authority. Existing ownership/admins are preserved on snapshots. Non-admin snapshots that remove members are rejected, while invitations and avatar changes remain available to members.
- Added service-level removeGroupMember checks and protected the creator against direct kick/removal. Owner fallback now requires the exact legacy JA ID shape and a nonempty hex identity; an explicit stored owner takes precedence. For newly received JA groups, infer ownership from the ID prefix and known member identities; native/non-JA groups use the initial sender. Previously persisted native groups with no owner cannot safely infer one from arbitrary updates.
- Kept outgoing invitations within v1.3.0's six data fields by carrying URI-encoded creator metadata as an extra pipe attribute in the avatar extension. Old avatar parsing ignores this attribute; invitation time and image/preset stay intact. The new parser still accepts the previous separate creator extension. This compatibility does not retrofit permission enforcement onto old clients.
- Added nine denial/positive regression tests in test/group_permissions_test.dart, replacing the earlier .dart_tool diagnostic expectations as the maintained regression coverage. Updated two native control fixtures to use a remotely owned group, so legitimate owner kick/re-invite/disband behavior remains tested.
- Verified: focused avatar/group suites 79 passed; final full suite 357 passed / 3 skipped using temporary APPDATA; formatting, `dart analyze lib test`, and `git diff --check` clean. No Windows build, deployment, commit or push in this turn.
- Remaining validation: real two-machine LAN/mixed-version/native BeeBEEP and Windows UI checks. All clients need the update to enforce the new permission rules. Ownership uses the existing BeeBEEP peer-identity mechanism; this change adds no cryptographic identity proof, co-admin distribution protocol, or owner-transfer workflow.

## Group notices and role workflow verification (2026-09-23)
- Rechecked the supplied 363-pass walkthrough against the dirty checkout. Its new role workflow and system notices were present, but local-only tests missed receive-side defects. Preserved unrelated changes; no commit, build, app restart or deployment.
- Added failing regressions before fixes: regular-member snapshots could change avatars/add peers; grants used endpoint IDs instead of receiver-local hashes; an empty admin list was omitted from the wire; remote role changes had no notices; transferring ownership could drop the old owner's implicit admin rights; newly discovered member notices displayed hash IDs instead of packet names.
- Snapshot updates now require a stored admin identity. Promotion/demotion and outgoing role metadata use stable member hashes; an explicit empty admin list now revokes the final admin. Ownership transfer explicitly retains the old owner as admin. Receive-side promotion/demotion/transfer notices use local translations and revision-based deduplication; first invitations remain history-free. Existing six-field invitation encoding is retained.
- Further negative tests reproduced co-admin roster removal of the creator and an async avatar save overwriting a concurrent role revocation. Both paths are now guarded; avatar completion rechecks current permissions and copies current group state.
- Avatar controls now react to current coordinator permissions, including revocation while open, and read-only previews remain usable without a coordinator provider. The details panel hides add-member actions for ordinary members and never offers removal of the creator. Widget coverage verifies the open-dialog revocation path.
- Automated checks: final full suite 371 passed / 3 skipped (46 sec); analyzer, relevant formatting and diff check clean. Tests use isolated temporary APPDATA and custom test files. Remaining manual checks: Windows visual behavior, two-machine role changes/notices/reconnect, and original BeeBEEP/mixed-version behavior. Snapshot ordering/offline conflict resolution and cryptographic identity remain existing limitations.

## Offline outbox verification (2026-09-24)
- Reviewed the supplied outbox walkthrough against three modified source files and the new six-test suite. Preserved those edits. No build, app restart, deployment, commit or push.
- Found missing per-recipient persistence for group messages (including partial delivery marked sent), race-prone retry snapshots, manual group retry not clearing recipient queues, and failed file messages being eligible for plain-text resend. The original reload test copied normalization logic rather than exercising the coordinator loader.
- Added nullable `MessageModel.pendingRecipients` JSON metadata, restored the recipient index through the real loader, and exposed `historyLoaded` so sends/reconnects wait for history. New text sends record intended targets, clear only successful ones, and remap pending group IDs when a handshake resolves a member. Broadcast retries retain `[All Users]` framing and exclude the local AI pseudo-peer.
- Auto retry rechecks message existence, revocation, pending targets and current group membership after its delay. Manual direct connect is guarded against overlapping handshake flushes; connection failures are caught, and delivered/read states are not downgraded. File/AI/revoked messages are excluded from text retry UI/service.
- Expanded outbox suite to 14 cases: actual restart with partial group delivery, actual startup normalization, concurrent flush, manual-connect overlap, revoke/removal during delay, recipient-specific manual retry, broadcast framing, file exclusion and translation-key checks. Test storage/known-device registry are isolated before construction; no temporary directories deleted in this verification.
- Verification: final full suite passed 386 tests / 3 skipped (51 sec), including all 14 outbox cases. `dart analyze lib test`, changed-file formatting and `git diff --check` clean. Handled window-manager plugin diagnostics from headless tests do not constitute Windows UI validation.
- Limits: `sent` means accepted by the socket, not recipient ACK. There is no exactly-once delivery or power-loss guarantee; persistence follows the existing history preference, 500ms debounce and 1000-message retention policy. Old group history without recipient metadata cannot reconstruct partial delivery safely and is not automatically broadcast to all members. Windows visual QA, real LAN, original BeeBEEP and abrupt-termination testing remain unperformed.
