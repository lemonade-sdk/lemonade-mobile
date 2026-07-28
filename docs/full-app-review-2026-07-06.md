# Full-app review — 2026-07-06

Scope: bugs & race conditions, missing caching, and connection errors that surface to the
customer instead of auto-healing. Six parallel reviews (API/networking, chat pipeline,
voice/audio, storage, providers/state, UI). Every finding cites file:line and was verified
against the actual code. Cross-referenced against `bugs` and `bugs_testflight.md`.

---

## Critical

### C1. Streaming autosave destroys other chats (data loss) — confirmed by two independent reviews
`lib/providers/chat_provider.dart:358` (also `:183, :189, :410, :422`) + `lib/providers/chat_history_provider.dart:83-102`

Every streaming write goes through `updateActiveChat`, which targets **whatever chat is
currently active**, not the chat the turn started in — no chatId is captured for the turn.
If the user taps another chat (or creates one, or deletes the streaming chat — `deleteChat`
at `chat_history_provider.dart:110-116` immediately activates another) while tokens stream,
the next `_updateAssistant` runs `ChatRepository.replaceMessages(otherChat.id, streamingMessages)`
— the other chat's entire message log is deleted on disk and replaced with the streaming
conversation. Permanent, silent data loss. Also: `clearChat()` during an in-flight turn is
silently undone by the next token (`chat_provider.dart:443-445`).

**Fix direction:** capture the chat uuid at turn start; all persistence during the turn keys
off that uuid; drop writes if the chat no longer exists.

### C2. Mic stays hot after leaving Talk screen
`lib/services/duplex_voice_session.dart:122-131` + `lib/screens/talk_screen.dart:229-237`

`dispose()` never stops/disposes the `AudioRecorder` and never sets `_running=false`.
Leaving TalkScreen via swipe-back/back-button calls `_session?.dispose()` without `stop()` —
the OS mic indicator stays on, hardware locked, battery drains until the process dies.

### C3. Full message-table rewrite + attachment re-hash on every streamed token
`lib/providers/chat_provider.dart:223-230` → `lib/providers/chat_history_provider.dart:100-101` → `lib/storage/chat_repository.dart:161-219`

Each token delta awaits `upsertChat` (txn) + `replaceMessages` (delete ALL message+attachment
rows, re-insert) and — before the txn — base64-decodes + sha256s + disk-writes every
image/audio part of every message in the chat (`_persistDataUrlPart`, `chat_repository.dart:170-190`).
A 500-token reply in a chat with two 2 MB images = ~500 full-transcript rewrites and ~1000
multi-MB decode+hash passes on the UI isolate. Causes visible stutter (SSE `await for` is
backpressured by disk writes), battery drain, flash wear, and widens every race window
including C1. **Fix direction:** debounce persistence (e.g. 250–500 ms + on finish), diff
messages, and skip attachment re-persist for already-persisted parts.

---

## High — connection errors that don't auto-heal (and surface to the customer)

### H1. No timeouts anywhere → indefinite hangs, dead Stop button, composer bricked
- `lib/api/nexus/nexus_gateway_base.dart:59-113`, `lib/api/nexus/nexus_account_client.dart:231-248` —
  no gateway HTTP call ever sets a timeout; the `TimeoutException` mapping at
  `nexus_gateway_base.dart:178` / `nexus_account_client.dart:326` is dead code.
- `lib/api/lemonade_client.dart:110-117` + `models_endpoint.dart:27`, `admin_endpoint.dart:17-45` —
  `getJson` defaults to no timeout and no caller passes one (`/models`, `/health`, `/stats`).
- `lib/api/lemonade_client.dart:162-175` — SSE `_http.send(req)` has no connect/first-byte
  timeout and no idle timeout on the body; also bypasses `_withErrorMapping`, so raw
  `ClientException`/`SocketException` escape instead of typed exceptions.
- `lib/omni/agent_loop.dart:159-166, 218-230`, `lib/services/chat_service.dart:145-149` —
  the SSE-drop retry and wrap-up calls also run with `timeout: null`.

Scenario: Wi-Fi dies without RST mid-turn → request hangs forever; `_stopRequested` is only
checked when an event arrives (`chat_provider.dart:221`) so **Stop does nothing**;
`chatStreamingProvider` stays true and the composer blocks all sends
(`nexus_composer.dart:120`) until app restart.

### H2. Raw exception persisted as an assistant message and replayed to the model
`lib/providers/chat_provider.dart:270-272` (+ `lib/constants/messages.dart:85`)

On any failure, `_replaceLast(working, 'Error: ${e.toString()}')` (a) shows raw exception
text as the assistant reply, (b) **persists it** and replays it to the model as assistant
content on every later turn (`chat_service.dart:186-208`), and (c) discards partial streamed
text and already-generated artifacts. Likely contributor to the reported "network error 500
after a few rounds" (`bugs` item 4) — the context gets polluted with error strings.

### H3. SSE truncation misreported as a normal completion
`lib/api/endpoints/chat_endpoint.dart:106-110`

Stream ending without `finish_reason`/`[DONE]` fabricates `finishReason: 'stop'` — mid-response
truncation looks like a completed answer, so the provider-level silent retry (82d749a) never
fires for the partial-content case. When the stream *errors* mid-way, no `ChatStreamFinish`
is emitted and assembled content/tool-calls are lost. Also related: closing the shared client
on server switch (`lemonade_client_provider.dart:10-12`) kills in-flight streams and the abort
masquerades as `'stop'`.

### H4. WebSockets are one-shot: no reconnect, no backoff, some silently
- `lib/api/realtime/realtime_audio_socket.dart:88-95` + `duplex_voice_session.dart:163` +
  `voice_mode_provider.dart:398` — WS drop mid-voice-call is never healed and never surfaced:
  nobody subscribes to `_ws.state`, mic keeps streaming into a dead sink, every turn hits the
  10 s `_pendingFinal` timeout → empty transcript → skip → resume — an **infinite deaf loop**,
  and the WS-vs-HTTP decision (`startCall:193-211`) is never revisited despite a working
  `_httpMode` fallback existing. Matches `bugs` item 3.
- `lib/api/nexus/nexus_call_takeover_socket.dart:40-63,81-88` + `call_takeover_audio.dart:33-38` +
  `live_call_overlay.dart:69-83` — takeover socket: `connect()` is fire-and-forget (no `ready`
  await), `onError/onDone` silently close with `_closed=true`; UI shows "You're live on the
  call" while `sendPcm` no-ops — **operator live into dead air**, no reconnect, no revert to AI.
- `lib/api/nexus/nexus_voice_events_socket.dart:37-66` — live call events silently stop after
  any blip; `_closed` latch makes the object one-shot and re-`events()` leaks the second channel.
- `lib/services/beacon_listener_service.dart:38-42` — UDP socket error → discovery silently
  dead forever (`_isListening` stays true).

### H5. Realtime-transcription connect failure swallowed → records against a dead socket
`lib/services/realtime_transcription_service.dart:61-65` + `lib/providers/transcription_provider.dart:371-389`

`connect()` catches the socket exception and pushes it to a broadcast controller **before any
listener is attached** (listener attaches after `await connect(...)`), so the error is dropped.
State goes to `recording`; user dictates for minutes; transcript comes back empty; no error shown.

### H6. Gateway HTTP clients killed mid-flight by unrelated auth-state changes
`lib/providers/nexus_gateway_provider.dart:13,22,31,41,50`

All five gateway clients `ref.watch(authProvider)` (whole `AuthState`) with
`ref.onDispose(client.close)`. Any mutation with an unchanged token (profile refresh, `busy`
flip) rebuilds every client and closes the old one mid-request — e.g. a Knowledge PDF upload
dies with "Client is already closed". Should watch `authProvider.select((a) => a.token)`.
Related leak: `account_provider.dart:273-300` constructs `NexusAccountClient` (fresh
`http.Client`) per rebuild and never closes it.

### H7. No retry/backoff anywhere for transient failures
`lib/api/lemonade_client.dart:223-233`, `lib/api/nexus/nexus_gateway_base.dart:173-183`

One `SocketException` from a momentary network transition is immediately wrapped and thrown to
UI. One-shot actions on a **live call** (`hangup`, `hold`, `sendDtmf`), `orderNumber`, `topup`
all surface first-attempt failures raw. Meanwhile the one retry that exists
(`agent_loop.dart:151-167`, `chat_service.dart:141-153`) catches **all** exceptions, so
deterministic 4xx/overflow errors get pointlessly re-sent non-streaming (double load/latency).

### H8. A single failed 2 s poll blanks device stats
`lib/providers/device_stats_provider.dart:28-35` + `device_stats_card.dart:22-23`

One dropped packet yields `null` → card flips to "unreachable" and gauges blank for a cycle.
No last-good retention, no consecutive-failure grace; errors and "no server" are conflated.
Poll also never pauses when the app is backgrounded.

---

## High — races & logic bugs

### H9. Login silently ignores typed credentials when a stale token exists
`lib/providers/account_provider.dart:82-93` with `:138-155`

`login()`/`register()` call `_reuseExistingToken()` FIRST. If the keychain still holds account
A's token (hydrate read threw at `:73`, or logout's `clearAccount()` failed at `:174-176`),
entering account B's credentials "signs in" as account A with no error.

### H10. Model catalog fetch races across server/mode switches
`lib/providers/models_provider.dart:148-271, 90-107`

`fetchModels()` never re-checks after its awaits that the server/mode is still current;
concurrent fetches are last-write-wins. A slow gateway response landing after a switch to
Local AI shows the gateway catalog for the local server and **persists a gateway-only model id
as `selected_model` for the local server** → next chat 404s. Also `:101-103`: a server switch
persists `clearSelection()` before knowing the new fetch will succeed — switching servers
while offline permanently erases the previous selection. And `fetchModels` has no in-flight
dedup (`chat_provider.dart:61,97,124` triggers it twice per blocked send).

### H11. Per-chat model overrides don't recompute on chat switch
`lib/providers/model_defaults_provider.dart:18,30-31,44-45`

`ref.watch(chatHistoryProvider.notifier).getActiveChat()` watches the notifier object (never
changes), not chat state — `effectiveLlmModel/AudioModel/ImageGenModel` keep returning the
previous chat's override until an unrelated dependency changes; transcription then uses the
wrong model.

### H12. Voice-mode start/stop races corrupt the session
- `lib/providers/voice_mode_provider.dart:142-221` — `hangUp()` during `startCall()`'s awaits
  (port discovery can take ~10 s): teardown nulls `_recorder`, then startCall resumes, orphans
  a fresh WS, and crashes on `_recorder!` → user sees "Voice mode failed to start" for a call
  they cancelled; other interleaving leaves the mic on with `_callActive==false`.
- `lib/services/duplex_voice_session.dart:252-272` — no re-entrancy guard on
  `RealtimeCompleted` → concurrent `_runTurn`s on multi-`completed` utterances (documented
  server behavior): interleaved history, two plays on one `AudioPlayer` (can hang), duplicate
  persistence. voice_mode has a `_committing` guard; duplex has none.
- `lib/services/duplex_voice_session.dart:96-120, 201-232, 471-476` — `stop()` during
  `start()` leaves a half-open WS driving the "stopped" session; HTTP-fallback utterance
  completes after hang-up (persists a turn post-call, emits on closed controllers);
  `_playDataUrl` awaits `firstWhere(completed)` with no timeout → End-call during speech hangs
  the turn then throws on closed controllers.
- `lib/providers/transcription_provider.dart:439-441, 520-553` — stop silently ignored while
  `_isTransitioning` (connect can take ~12 s) so recording starts after the user "cancelled";
  `cancelRecording` has no transition guard at all → null-deref crash or phantom "recording"
  state.

### H13. Every realtime transcription stop stalls ~26 s
`lib/services/realtime_transcription_service.dart:146-153`

Drain debounce hardcodes `Timer(Duration(seconds: 25))` instead of `drainDelay` (5 s). UI sits
in `RecordingState.processing` (`transcription_provider.dart:444-459`) for ~26 s on **every**
successful realtime session.

### H14. Legacy migration: non-atomic, silently bricks on partial run
`lib/storage/legacy_migration.dart:37-58` + unique indexes (`replace: false`) + `lib/main.dart:20-24`

Crash after `_migrateServers` commits but before `legacyMigrationCompleted` is set → every next
launch re-runs, hits `IsarUniqueViolation`, exception swallowed with a `debugPrint` — chats/
transcriptions/defaults never migrate; user sees data "gone" with no error/retry.
**Also security (`:64-79`):** the backup file writes the raw servers list **including plaintext
API keys** to `{docs}/legacy-backup-<ts>.json`, never deleted, included in device/iCloud
backups — violating `secure_storage.dart`'s guarantee; a failing migration writes a new copy
each launch.

### H15. Saved transcription audio has the un-fixed absolute-path bug
`lib/services/audio_recorder_service.dart:89-102` + `transcription_entity.dart:21` + readers (`transcription_detail_screen.dart:76`, `transcription_list_item.dart:50`, `transcription_provider.dart:157-176`)

Absolute iOS-container paths stored verbatim, read with raw `File(path)` and no
`resolveExisting`-style re-rooting (the exact bug 7b35a62 fixed for chat images). Every iOS
app update orphans all transcription audio; deletes also miss the real files (disk leak).

### H16. Chat-history cold start: monolithic, fragile, unbounded memory
`lib/storage/chat_repository.dart:23-41, 94-106` + `lib/providers/chat_history_provider.dart:22-27`

Startup loads every message of every chat and `readAsBytes()`+base64-encodes **every
attachment** into provider state (tens of MB resident, multi-second cold start). And one
bad/corrupt attachment file throws out of the fire-and-forget `_loadChats()` — **entire chat
history renders empty** with no error and no retry.

### H17. Double-tap can buy a phone number twice (real money)
`lib/screens/nexus/get_number_screen.dart:100-130`

`_buyingDid` is set only after `await _confirmBuy(n)` — two quick taps stack two confirm
dialogs; confirming both places two `orderNumber` calls.

### H18. Delete-chat racing autosave resurrects the chat
`lib/providers/chat_history_provider.dart:104-117` + `lib/storage/chat_repository.dart:112-129`

Queued `upsertChat` behind Isar's write lock re-inserts the just-deleted chat + messages;
zombie chat reappears on next launch. (Same family as C1.)

---

## Systemic: raw exception text shown to the customer

No shared friendly-message mapper exists; ~40 sites render `'$e'` / `e.toString()` directly.
Offline/timeout shows things like
`LemonadeApiException: Network error: SocketException: Failed host lookup … status=… endpoint=/voice/numbers`
as page bodies, banners, and SnackBars:

- **Whole-page error bodies, no retry:** `pbx_tab.dart:121,269,385,477,606` (all five PBX
  sections), `plan_wallet_screen.dart:125-129` (entire billing page), `docs_tab.dart:302,347`,
  `team_screen.dart:29`, `agents_screen.dart:31`, `http_tools_screen.dart:31`,
  `knowledge_pages_screen.dart:32`, `plan_picker.dart:117`, `call_transcript_screen.dart:31`,
  `calls_tab.dart:127` (the `:454` substring check only rescues `capability_required`/401).
- **Sign-in:** `auth_gate.dart:56` — first screen subscription users see; wrong password shows
  `LemonadeApiException: … status=401 endpoint=/auth/login`; also missing `mounted` guard in
  the catch (setState-after-dispose).
- **Live-call surfaces:** `live_call_overlay.dart:55,63,99`, `calls_tab.dart:76`.
- **Mutation toasts (save/upload/buy/delete/top-up):** `unlock_sheet.dart:72,91,108`,
  `flow_editor_overlay.dart:149,210,222`, `extension_editor_sheet.dart:95`,
  `number_routing_overlay.dart:81`, `settings_tab.dart:168`, `pbx_tab.dart:235,673,691`,
  `docs_tab.dart:65,247`, `agents_screen.dart:173,212,244,260`,
  `knowledge_pages_screen.dart:130,152,184`, `http_tools_screen.dart:155,183,215`,
  `plan_wallet_screen.dart:61,80,111`, `get_number_screen.dart:94,126,202`.
- **Local-AI/admin:** `model_manager.dart:102,125,156,194,227,780`, `admin_backends_tab.dart:34,48,63`,
  `admin_models_tab.dart:50,65,78,93,154`, `admin_logs_tab.dart:52`, `admin_system_info_tab.dart:34`,
  `admin_dashboard_tab.dart:56`, `account_screen.dart:126,660,703,1020`, `servers_screen.dart:113`.
- **Local platform errors:** `voice_input_sheet.dart:88,138`, `talk_screen.dart:149`,
  `image_viewer_screen.dart:87,115,152`, `nexus_composer.dart:95,104,114`
  (`PlatformException(camera_access_denied, …)` etc.).

**Fix direction:** one `friendlyError(Object e)` mapper (typed `LemonadeApiException` →
message by status/kind; SocketException/Timeout → "Can't reach the server — retrying…") used
by every error branch, plus a shared error widget with a Retry button; log the raw string,
never render it.

---

## Missing caching

- **Every Nexus dataset is a bare `FutureProvider.autoDispose`** — no keepAlive, no disk
  hydration, no stale-while-revalidate: account summary/plans/subscription
  (`account_provider.dart:267-301`), entitlements/wallet/transactions/memberships
  (`billing_providers.dart:9-45`), agents/tools (`agents_providers.dart:7-36`), knowledge
  pages/collections (`knowledge_providers.dart:7-30`), voice flows/voicemail/CDR
  (`voice_providers.dart:57,72,80`). Every screen open = full-screen spinner + refetch;
  reopening 5 s later repeats it. `plansProvider` (public static catalog) is the clearest
  offender. The model catalog got the persist+hydrate treatment (50510ee) — these peers didn't.
- **PBX sub-sections refetch on every section flip** (`pbx_tab.dart:51-57` builds only the
  active section + autoDispose providers); voicemail audio re-downloads after every flip
  (`pbx_tab.dart:637,683`).
- **`hasCapabilityProvider` returns false while entitlements are cold-loading**
  (`billing_providers.dart:18-21`) → gated features flash locked on every remount.
- **TTS: no cache, temp files never cleaned** (`tts_service.dart:24-36`; also
  `duplex_voice_session.dart:340`, `voice_mode_provider.dart:690`) — identical text
  re-synthesized every time; `tts_<µs>.mp3` files accumulate.
- **WS port discovery re-probed every voice/transcription start**
  (`audio_transcription_service.dart:71-93`) — up to ~10 s dead time per call start against
  servers without `/health`; never cached per server.
- **Silero VAD recreated + ONNX model reloaded per utterance**
  (`voice_mode_provider.dart:272-310`) — per-turn latency and missed first words.
- **KB search fires per keystroke, no debounce** (`knowledge_providers.dart:36-50`).
- **`http.Client` per web-tool call** (`tool_executor.dart:415-433,442-469`) — new TCP+TLS
  handshake per search round; no per-turn result cache.

---

## Medium

- `lib/storage/file_storage.dart:26-31` — attachment writes not atomic; a kill mid-write
  leaves a truncated file at the sha256 path and the dedup `exists()` check makes the
  corruption permanent. Write temp + rename.
- `lib/storage/chat_repository.dart:142-156,192-202` — deleting chats removes attachment
  rows but never files; no GC → unbounded disk growth (`deleteByPath` has no caller).
- `lib/storage/folder_repository.dart:51-59,83-104` — read-modify-write with the read outside
  the txn (rename/move/setChatFolder) → chats pointing at deleted folders, resurrection after
  `deleteAll`. Also `create`/`ensureInbox` (`:23-30,45`) lack the isOpen guard and can create
  duplicate Inboxes.
- `lib/storage/legacy_migration.dart:275-288` — legacy file-path images stored as absolute
  paths outside the content store → unrecoverable after next container move.
- `lib/providers/account_provider.dart:223-229` vs `app_mode_provider.dart:55,100-112` —
  sign-in while in Local AI mode: server-selection tug-of-war ends with `fetchModels` +
  force-select silently overriding the user's local model.
- `lib/omni/agent_loop.dart:196-199,330-338` + `chat_provider.dart:242-259` — edit-image
  artifact replacement broken end-to-end (`turnArtifacts.last` after in-place replace emits
  the wrong artifact; provider always appends; ChatDone skips reconciliation) → generate-then-edit
  shows both images or loses the edit.
- `lib/omni/agent_loop.dart:186-191` + `tool_executor.dart:244-259` — same-round tool calls
  run concurrently but context is applied post-`Future.wait` → `generate_image` +
  `edit_image` in one round edits the wrong/no image. Stop also can't cancel in-flight tools
  (up to 4-min image jobs keep burning GPU).
- `lib/providers/chat_provider.dart:269,301-316` — `_maybeAutoTitle` awaited inside the turn:
  composer stays blocked up to 20 s after the reply visibly finished.
- `lib/services/call_takeover_audio.dart:68-81` — downlink buffer grows without bound →
  monotonically increasing audio delay over a long takeover.
- `lib/providers/servers_provider.dart:110-136, 24-45` — renaming the selected server drops
  selection (app goes dead until manual re-select); constructor `_load()` races `addServer`
  (just-added server vanishes until restart); `updateServer` equality match can silently skip
  the in-memory update (`:119`); keychain writes not try/caught.
- setState-after-dispose / missing `mounted`: `pbx_tab.dart:683`, `agents_screen.dart:258`,
  `model_manager.dart:177-191`, `auth_gate.dart:56`, `calls_tab.dart:60-73`,
  `plan_wallet_screen.dart:106-112`, `docs_tab.dart:239-242`.

## Low

- `lemonade_client.dart:58-66` — `rootUriFor` drops path prefixes (reverse-proxy deployments
  always fail `/live`).
- `sse_parser.dart:23` — strict `utf8.decoder` kills the stream on one bad byte; final
  unterminated frame dropped.
- `realtime_audio_socket.dart:83-105` — timed-out connect candidates never cancelled (zombie
  sockets); `connect()` twice leaks the old channel (also `logs_socket.dart:35-55`, plus
  dispose-after-use adds on closed controllers in both).
- `voice_mode_provider.dart:731-738,833-864` — stale `_speakReply` finally can dispose a
  newer call's player; `_fail` after dispose throws.
- `transcription_provider.dart:188-189` — controller never wired to `ref.onDispose`;
  `dispose()` is dead code.
- `chat_history_provider.dart:26-39`, `folders_provider.dart:10-33`,
  `model_defaults_provider.dart:57-82`, `admin_mode_provider.dart:10-14`,
  `image_resolution_provider.dart:36-50` — constructor `_load()` clobbers fast user writes
  (cold-start window).
- `secure_storage.dart:82-88` — `deviceId()` get-then-put race (mismatched rotation key).
- `chat_repository.dart:113` etc. — all mutations silently no-op when DB isn't open (UI
  "succeeds", nothing persists, no log).
- `chat_repository.dart:131-140` — `setActive` rewrites every chat row per switch (O(N) txn).
- `model_downloads_provider.dart:48,109-117` — server switch drops active downloads with no
  Finish event (90% download silently vanishes).
- `docs_tab.dart:217`, `get_number_screen.dart:135` — dialog TextEditingController leaks;
  `servers_screen.dart:36-70` — no double-tap guard on add-server (duplicate rows).

---

## Cross-reference to known bug reports

- `bugs` #3 (call mode WebSocketException shown raw) → H4 (no reconnect/fallback; WS-vs-HTTP
  decided once) + systemic raw-error section.
- `bugs` #4 (network error 500 after a few rounds) → H2 (error text persisted and replayed to
  the model each turn, growing/polluting context) + H7 (no retry on the 500).
- TestFlight #3's fix (friendly capability card) exists only in `calls_tab.dart:454` as a
  substring special-case — the systemic section is the generalization it needs.

## Verified solid (no action)

- `ToolCallAssembler` fragment accumulation; typed-exception mapping in both gateway bases.
- Chat send button is double-tap safe (`chatStreamingProvider` set synchronously).
- Tab switches don't refetch (IndexedStack keeps the six main tabs alive).
- Chat image bubbles use pre-cached bytes (no per-frame base64 decode).
- Model catalog per-server persist/hydrate (50510ee) is the right pattern — extend it.
