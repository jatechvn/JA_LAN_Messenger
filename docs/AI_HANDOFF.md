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
