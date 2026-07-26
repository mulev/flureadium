# ADR: Car bridge mechanism (Dart↔native content/control for CarPlay + Android Auto)

**Status:** Accepted as **implementation default** — cold-path functional validation **PENDING** (gate defined below; must pass on the first runnable Phase 3/4 build before the mechanism is considered proven).
**Date:** 2026-07-26
**Decision:** **(a) app-scoped headless `FlutterEngine` + `MethodChannel`** — not (b) native read-through cache.

## Context

The car surfaces (CarPlay scene, Android `MediaLibraryService`) must render Fablum's **library**, which lives only in Dart (`BookRepository`/sqflite). Today they don't: both derive content **natively** from the one `Publication` the reader already opened —

- iOS: `CarPlaySceneDelegate` reads `CarPlayPlaybackBridge.shared.chapters` (a native singleton). The scene runs on a per-scene *implicit* Flutter engine (`AppDelegate.didInitializeImplicitFlutterEngine`); the CarPlay scene has **no `FlutterViewController` and no `binaryMessenger`** of its own.
- Android: `PluginLibrarySessionCallback` is fed by `publicationProvider: () -> Publication?`; browse callbacks run in a background service with no Flutter UI guaranteed.

So a library browser needs a Dart↔native bridge that answers browse/search/play **when no Flutter UI is alive** (cold CarPlay connect, backgrounded Android Auto). Two mechanisms were considered.

**(a) App-scoped headless `FlutterEngine` + `MethodChannel`.** A long-lived, UI-less `FlutterEngine` owned at app scope runs a Dart entrypoint that can call `BookRepository`. The CarPlay scene delegate and the Android media service each attach a `MethodChannel` to that engine's `binaryMessenger` and request nodes.

**(b) Native read-through cache + native commands.** Dart writes a native-readable snapshot of the browse tree (+ a search index + playable file paths) on every library change; native callbacks read it synchronously. Playback commands drive the media session natively.

## Decision & rationale (documentation + architecture grounded)

Chosen: **(a)** as the implementation default. Reasons 1–3 below are settled by the codebase's own structure and primary-source capability facts. Reason 4 is a *necessary-but-not-sufficient* capability fact: it proves a headless engine is possible in general, **not** that Fablum's specific Dart stack boots and answers from a CarPlay-cold-launched process — that is the open question the validation gate closes.

1. **DRY / single source of truth.** (a) reuses *all* existing Dart logic — `BookRepository.getAllBooks`/`searchBooks`, `SortField.lastOpened`, the playable-in-car policy, `ttsCanSpeak`. (b) requires a **parallel native mirror** of the library **and** a native search index, plus an invalidation path on every import/delete/progress write — a whole duplicate subsystem that can drift from the DB.
2. **The callbacks are already async-friendly.** Android `MediaLibraryService.Callback.onGetChildren`/`onSearchResult` return `ListenableFuture` — designed to complete later. iOS CarPlay supports setting an initial `CPListTemplate` and then calling `updateSections(_:)` when data arrives. So an async method-channel answer fits both surfaces natively; neither requires a synchronous read. (b)'s only advantage — synchronous reads — solves a problem we don't have.
3. **(b) does not actually remove the engine.** Cold "play book X" must open *that* publication and start audio/TTS. That is inherently engine/native-reader work (`openPublicationFromUrl` + `play`/`ttsEnable`). (b) removes the engine from *browse* only, while still needing an engine or a bespoke native open+play path for *control*. So (b) pays the full cost of a cache subsystem and still can't avoid the engine for playback — the worst of both.
4. **Headless `FlutterEngine` is a documented, supported capability** — *possible in principle, unproven for our stack.* A `FlutterEngine` can be created and `run()` with a Dart entrypoint without a `FlutterViewController` (the pattern behind background execution and app extensions), and CarPlay *audio* apps are (re)launched by the system when the user selects the app, firing `templateApplicationScene(_:didConnect:)`. What this does **not** prove: that `BookRepository`/`sqflite` open, that `GeneratedPluginRegistrant` registers the plugins the car engine needs, and that a `MethodChannel` round-trips **from a process launched cold by CarPlay** (not by a normal app launch). Those are Fablum-specific integration facts the validation gate must confirm.

**The real risks of (a)** — both closed by the gate, not by this document: (i) whether the headless car engine boots the Fablum Dart stack (DB + plugins) cold; (ii) cold-start spin-up latency (Dart isolate + plugin registration), mitigated by the async-update pattern (placeholder list → `updateSections`/complete-future when nodes arrive) and by keeping the engine warm for the session. Latency is a tuning concern; (i) is a viability concern and is the primary thing the functional gate proves.

## What Phase 1 settles, and what the gate must still prove

The spike was originally framed as "measure cold-start latency on both platforms." Reframed honestly:

- **Settled now (this ADR):** the mechanism *choice* — (a) over (b) — on DRY, async-callback, and engine-dependency grounds (reasons 1–3). This is enough to build Phases 2–5 against, which are written mechanism-neutral so a later pivot is bounded.
- **NOT settled — the validation gate must prove it:** that Fablum's Dart stack actually boots and answers from a CarPlay-cold-launched (and Android backgrounded-service) process, and that the tap→play command round-trips. Do **not** treat (a) as proven until this passes.
- **Representative latency** (real numbers) is device/head-unit-specific; the iOS Simulator CarPlay window and Android DHU are **functional** rigs, not performance rigs. Simulator timings are directional only, never thresholds.
- Phase 1 **keeps no prototype code** — a throwaway prototype would largely re-implement the real Phase 2 transport + a slice of Phase 3/4 rendering. The functional gate is therefore **staged** (see Validation plan): STAGE 1 (the decisive engine-cold + channel proof, stub nodes) runs against the **flureadium example app** in Phases 3/4; STAGES 2–3 (real library, tap→play) run against **Fablum** in Phases 5/6. **If STAGE 1 fails, this decision is reversed — variant (b) (native cache + native commands) reopens as the fallback** — and the mechanism-neutral Phases 2–4 absorb the swap before Phases 5+ commit further to (a).

## Validation plan

### Instrumentation points (add lightweight timestamped logs at each; they double as functional probes)
- `t0` — scene connected (`didConnect`) / service callback entered (`onGetChildren`)
- `t1` — engine start requested / engine already warm
- `t2` — Dart method-channel handler ready (or cache read begins, for comparison)
- `t3` — provider response returned to native (`children` nodes ready)
- `t4` — first template/list update painted (`updateSections` / `LibraryResult` delivered)
- `tap` — row tap → play command dispatched → playback started

### Functional GO/NO-GO — staged (this is the gate that proves variant (a))

**STAGE 1 — engine boots cold + channel round-trips (flureadium *example app*, stub provider; Phases 3/4).** This is the decisive (a)-viability test and needs no Fablum. In the example app with a stub `CarContentProvider` (fake nodes):
1. **Cold browse:** fully quit the example app. iOS: `defaults write com.apple.iphonesimulator CarPlay -bool YES`, relaunch Simulator, I/O ▸ External Displays ▸ CarPlay, tap the example's icon → **stub** rows appear (not empty). Android: DHU, example not foregrounded → stub browse populated. Expect `t0→t4`.
2. **Tap round-trip:** tap a row → a round-trip is logged back into Dart (stub handler; no real playback yet).
3. **Lifecycle:** quit + reconnect ×3 (iOS) / rebind the service (Android) → still populates.

**STAGE 2 — real library cold (Fablum; Phase 5).** With Fablum cold, the car root shows **real `BookRepository`/sqflite rows** — proves the Dart *data* stack (DB open + plugin registration) boots from the cold car-launched process.

**STAGE 3 — tap→play (Fablum; Phase 6).** Tapping a real row starts playback (audiobook / read-aloud). Completes the proof.

**Failure of STAGE 1 reverses the decision** (variant (b) reopens). STAGES 2–3 are integration milestones on top of a proven engine, not (a)-vs-(b) decisions.

### Representative latency (real device / real head unit — **follow-up validation, NOT a Phase 1 blocker**)
- `t4−t0` cold (engine cold-start included), `t4−t0` warm, `tap→play`. Recorded on a physical CarPlay head unit + Android Auto car/phone. Used to tune the warm-keep + loading-state behavior, not to reverse the mechanism choice unless (a) proves functionally non-viable.

## Consequences

- **Phase 2 transport** = `CarContentTransport` as a `MethodChannel` handler (variant-(a) sub-path). It routes native `rootTabs`/`children`/`search`/`play`/`nowPlayingChapters` requests to the registered Dart `CarContentProvider` and returns encoded `CarBrowseNode`s. The cache-writer sub-path (variant b) is dropped.
- **App bootstrap (fablum, Phase 5)** stands up / owns an app-scoped `FlutterEngine` for the car layer (or reuses the existing implicit engine if it can be made durable across the CarPlay scene lifecycle — an implementation detail for Phase 2/3). `registerCarContentProvider` runs on that engine.
- **iOS (Phase 3)** `CarPlaySceneDelegate` attaches a `MethodChannel` to the car engine and drives `CarTemplateRenderer`; initial template set synchronously, populated via `updateSections` on the async response.
- **Android (Phase 4)** `PluginLibrarySessionCallback` gets a `CarContentSource` backed by a `MethodChannel` to the car engine; callbacks return `ListenableFuture` completed from the coroutine that awaits the channel.
- **Search cold path** is answered by the same engine (`provider.search` → `BookRepository.searchBooks`) — no native search index needed.

## Rejected option (b) — failure mode

(b) requires: a native serialization of the entire browsable tree, a native search index, and an invalidation hook on every library mutation (import, delete, progress, categorization) — a duplicate of the DB that silently drifts if any writer forgets to refresh. And because cold playback still needs to open the selected publication, (b) *also* needs an engine or a bespoke native open+play+ttsEnable path. Net: more code, a second source of truth, and the engine dependency it was meant to avoid. It would only win if the car callbacks required strictly synchronous reads — which, per the async-callback facts above, they do not.

## References

- Codebase: `fablum/ios/Runner/{AppDelegate,SceneDelegate,CarPlaySceneDelegate}.swift`, `flureadium/.../carplay/CarPlayPlaybackBridge.swift`, `flureadium/.../android/.../{PluginMediaService,PluginLibrarySessionCallback,FlureadiumPlugin,PublicationChannel}.kt`.
- Apple: CarPlay Audio App Programming Guide; `CPTemplateApplicationSceneDelegate`; `CPListTemplate.updateSections(_:)`; Using the CarPlay Simulator.
- Android: `MediaLibraryService.Callback` (`onGetChildren`/`onSearch`/`onGetSearchResult` return `ListenableFuture`).
- Plan: `project_plans/fablum/todo/fablum_epic_in_car_experience/plan.md` (mechanism-neutral Phases 2–4).
