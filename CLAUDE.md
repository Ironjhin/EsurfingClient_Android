# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Top priority: obey the user's feedback

**Start here, always.** The maintainer (劳福铨 / `Ironjhin`) has the final say, even when it contradicts the README, this file, or Claude's own inference.

- If the user tells you something about the project — a fact, a layout, a convention, a target file, a "this is correct" statement — **treat it as authoritative unless the user explicitly walks it back**.
- Do **not** second-guess the user because the code or README says something different. Code can be stale; the README is user-facing and may lie; the working copy may have uncommitted or untracked states that contradict the index. The live human takes precedence.
- If the user's instruction conflicts with what you inferred from the repo, **ask first** ("you said X, but the README says Y — should I follow you?"), then follow the user's answer. Never silently "correct" the user.
- If you **do** spot a real technical error that will break the build or logic, flag it as a *suggestion*, not a decision. Example: "Heads-up — `<data_dir>/run.log` from the README doesn't match what `path_provider` actually produces on some devices. Want me to still go with the README's wording, or adjust?" Then implement whichever the user picks.

The rest of this file is Claude's inference from the codebase. Use it, but don't let it overrule a direct instruction.

### When the active model is LongCat-2.0

The user may switch away from the default Opus model via `/model`. If the active model is **LongCat-2.0** and it starts behaving oddly (missing context, skipping steps, refusing to read files, being terse in ways that hurt correctness):

- **Just do the legwork anyway.** Re-read files you need, search for the symbol, fetch the reference — don't reason around it hoping to save tokens.
- **Why**: LongCat-2.0 is chosen specifically to be budget-friendly; on this model, prompt-cache hits on the system prompt and `CLAUDE.md` are essentially free, so spending tool calls to re-read or verify costs nothing extra while saving the user's time and preserving correctness.
- This **only** applies to LongCat-2.0. On other tiers (default Opus or anything else), preserve tokens as normal — don't do unnecessary reads just because the model acts sluggish.
- Regardless of model, treat the model's own output as the least-trusted input in the loop. If it wants to guess instead of open a file, open the file; if it wants to skip a step, do the step.

### ADB for debugging

When you need `adb` (install APK, read `logcat`, pull `run.log`, forward ports, etc.), the local binary lives at:

```
D:\UNLOCKER\莫离然然搞机工具箱v4.7.5-2026.3.17\Tools\adb.exe
```

Use the full path so the call works regardless of whether the dir is on `PATH`:

```
"D:\UNLOCKER\莫离然然搞机工具箱v4.7.5-2026.3.17\Tools\adb.exe" devices
```

If a bare `adb ...` call fails for the user because their shell doesn't have it on `PATH`, prepend the quoted path above.

You have **no ability to view, analyze, or reason about images, screenshots, or any non-text binary**. You are a text-only model.

- If the user shares an image or screenshot, **don't pretend to understand it.** Ask the user to describe what they want, or to paste relevant text (error messages, code snippets, log excerpts, UI text) into the conversation.
- If you need information that lives only in image form (a diagram, a settings screen, a screenshot from the running app), **ask the user to narrate it** — do not guess from the filename or surrounding context and present the guess as fact.
- This is not modesty. A confident wrong read of an image is worse than admitting you can't see it. When in doubt, say "I can't see the image — please describe / paste the text".
- The one exception is when the image is merely decorative (a logo in the README, an icon asset whose content doesn't matter to the task) — in that case you can note you're skipping it rather than agonizing.

`ESurfingClient_Android` — an Android client for authenticating to Guangdong Telecom's campus ("校园网 / Tianyi") network. The UI is Flutter; the actual protocol engine (signing / state machine / captive-portal probing / keepalive) runs in a C daemon compiled with the Android NDK and loaded via Dart FFI. There are two distribution tracks on separate branches:

* `main` → Flutter **APK** version (this branch). No root required.
* `magisk` → pure-C Magisk module, ~1–2 MB, boots with the device and exposes a web admin panel.

Each push to `main` triggers `.github/workflows/build-apk.yml`, which runs `flutter build apk --release` in GitHub Actions and publishes an auto-numbered `v1.1.<run_number>` Release. There is no local CI; APK is the output of the workflow.

## Project layout

The working copy at `/c/Users/LFQ/Desktop/esurfing_flutter` contains a **nested** Flutter project. Treat the nested folder as the source of truth for anything labeled "Flutter root":

* Repo root (outermost, where `.git`, `README.md`, `.github/workflows/build-apk.yml`, `pubspec.yaml`, `lib/`, and top-level `android/` live). Per the README, "push `main` → cloud pipeline builds APK" — this is the directory the CI runs in. `flutter build apk` from here is what the CI does.
* `android/app/src/main/cpp/**` — the NDK side: `ffi_bridge.{h,c}` exports the FFI surface (`esurfing_client_init/start/stop/is_stopped/destroy/clear_log`, `init_native_env`); `CMakeLists.txt` pulls in libcurl and cJSON via `FetchContent` and compiles `DialerClient.c`, `NetClient.c`, `States.c`, plus `cipher/`, `utils/`, `webserver/`, `external/`, `inc/`. Output: `libesurfing_client.so` for `arm64-v8a / armeabi-v7a / x86_64 / x86`.
* `esurfing_flutter/` (nested) — contains its own `pubspec.yaml`, `lib/main.dart`, and a duplicated `android/` with its own `cpp/`. Commit history, branches (`main`, `magisk`, `try-v1.0.37`) tracked at `origin` (`https://github.com/Ironjhin/EsurfingClient_Android.git`) live **here**. Most recent commits (uptime display, force re-auth, CI/action changes) represent the true project state.

There is redundancy between the outer `android/` and `esurfing_flutter/android/`. Before editing C/CMake sources, verify which copy the active build path reads — the CI job runs from the outer directory, but the nested one is the most recently modified. Confusing the two produces edits that don't reach the APK.

## Architecture (the cross-cutting part)

The thing you can't see from any one file is split across three layers:

1. **Native C daemon** (`android/app/src/main/cpp/...`)
   - Owns libcurl + cJSON + pthreads. Auth state machine lives in `States.c`; protocol/crypto in `cipher/`; network IO in `NetClient.c` / `DialerClient.c`; logging + a small HTTP server in `utils/` and `webserver/`.
   - Spawns its own background `pthread` for the dial-and-probe loop. `ffi_bridge.c` is the only file that crosses into Dart — it never calls back into Flutter, it only exports functions.
   - Logs to `<data_dir>/run.log` after `init_native_env(sandbox_path)` re-targets the C-side path.

2. **Dart FFI layer** (`lib/src/native/`)
   - `bindings.dart` — mirrors `ffi_bridge.h` with `dart:ffi` signatures; opens `libesurfing_client.so` on Android.
   - `auth_controller.dart` — wraps the blocking C calls in an `Isolate` so the UI thread never stalls; owns a small message protocol (`_StartCommand` / `_StopCommand`) and polls `esurfing_client_is_stopped()` to detect native thread death. **Critical**: the C side creates its own pthread, so the Dart Isolate is only the lifecycle container, not the worker.

3. **Flutter side** (`lib/src/{ui,model,services,i18n}`, `lib/main.dart`)
   - `model/config.dart` — single source of truth for credentials + channel (`phone` vs `pc` → different User-Agent strings) in `SharedPreferences`. Changing `userAgent` here is the supported way to switch between "手机版" and "PC 版" portal flows.
   - `services/log_reader.dart` — 1-second `Timer`-based poll of `run.log`, **byte-offset incremental** (not full-rewindowed). Clear = in-process `esurfing_client_clear_log()` plus offset reset. Memory cap at 512k chars with rotation detection (file shorter than recorded offset ⇒ reset to 0).
   - `ui/home_page.dart`, `ui/settings_page.dart`, `widgets/log_viewer.dart` — Material 3, portrait-locked, light/dark via `Color(0xFF1565C0)` seed.
   - `i18n/app_localizations.dart` — manually-authored localizations (not ARB-generated); `main.dart` wires `GlobalMaterialLocalizations` + a custom `AppLocalizationsDelegate`.

Global error paths: `FlutterError.onError` and a `runZonedGuarded` both append to `<docs>/run.log` with re-entry guard `_isLoggingError` and a `debugPrint` fallback when the app sandbox isn't ready.

## Version numbering (updated 2026-07-06)

- Current prefix: **v1.2.x** — v1.0.x was retired at v1.0.65; v1.1.x was a brief
  intermediate track before the user requested the scheme below.
- `build-apk.yml` does **not** use `github.run_number` as the patch number. Instead,
  a dedicated step scans all existing `v1.2.*` git tags, takes the max x, and +1's
  it — so the first `main` push produces `v1.2.0`, the next `v1.2.1`, etc.
- `run_number` still shows up in release notes as an internal build counter, but
  never appears in the APK's `versionName` or the Release tag.
- Release notes use `git log <latest pre‑v1.2 tag>..HEAD` for the changelog.
- The same repo‑scope `run_number` counter powers the `magisk` branch; magisk and
  main share it, so their releases never collide (magisk uses `magisk-v*`).

## Editing rules that matter

* **Native edits**: only the outer `android/app/src/main/cpp/**` is what the active CI pipeline reads. The nested `esurfing_flutter/android/...` copy is out of sync — verify before editing so your change actually ships.
* **Bridge sync**: if you add/remove/rename an exported symbol in `ffi_bridge.{h,c}`, you must mirror the mangled `typedef` and `lookupFunction` line in `lib/src/native/bindings.dart` and the call in `auth_controller.dart`. A mismatch fails at **runtime** (no static check), with an `DynamicLibrary` lookup error.
* **Log reader contract**: `LogReader.clear()` calls C-side `esurfing_client_clear_log()` — which truncates the file *from inside the same process* — **then** resets the byte offset. Don't change one without the other, or you replay the whole file on next poll.
* **Flutter lint config**: project uses `flutter_lints: ^4.0.0` from `pubspec.yaml`. Run `flutter analyze` before pushing — the CI will reject the build on warnings it surfaces.
* **Magisk sync**: the `magisk` branch shares protocol code with `main`. When fixing something in `cipher/` or `NetClient.c`, check whether the same change needs cherry-picking to Magisk (recent commits show this pattern: "sync from magisk").
* **Accessibility keepalive** (added 2026-07-06):
  - `ESurfingMainActivity.kt` (renamed from `MainActivity.kt`) replaces the
    Flutter-default `MainActivity` in `AndroidManifest.xml`. It registers a single
    MethodChannel `com.example.esurfing_client/keepalive` that Dart
    (`lib/src/native/keep_alive_channel.dart`) calls for two methods:
    `isAccessibilityEnabled` (reads `Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES`)
    and `openAccessibilitySettings` (launches `Settings.ACTION_ACCESSIBILITY_SETTINGS`).
  - Do NOT place hand-written Kotlin under `kotlin/com/example/...`. CI step
    `flutter create --platforms=android .` *regenerates* that path's `MainActivity.kt`
    on every build — any custom code placed there gets overwritten, and a file with
    the same package + simple name under `java/` *and* `kotlin/` triggers Kotlin
    `Redeclaration`. Keep the hand-authored file under `java/` with a **different
    simple name** (`ESurfingMainActivity`, ESurfingKeepAliveService).
  - The auto-generated `kotlin/com/example/esurfing_client/MainActivity.kt` is
    dead code (manifest points to `.ESurfingMainActivity`), but leave it alone —
    deleting it is fragile across Flutter tooling upgrades.
  - `accessibility_keepalive.xml`'s `settingsActivity` must be
    `com.example.esurfing_client.ESurfingMainActivity` (not the old `.MainActivity`)
    or Android's "open settings from this service" link is broken.
  - The corresponding AccessibilityService class is now `ESurfingKeepAliveService`.
    The string `accessibility_service_description` lives in `res/values/strings.xml`.
  - Dart fallback contracts: `KeepAliveChannel.isAccessibilityEnabled` → `false`
    on `PlatformException` / `MissingPluginException`; `openAccessibilitySettings`
    no-ops on same. UI degrades to a "please open settings manually" message.
* **Log auto-truncation** (added 2026-07-06): `LogReader._poll()` checks newline
  count on each chunk; when it exceeds 1000 it calls
  `esurfing_client_clear_log()` + resets content + zeroes the byte offset. C-side
  `Logger.c:max_lines` was reduced from 10000 to 1000 as a backup rotation
  threshold (fires only if the Dart side App is dead or skipped).
* **Force re-auth** (added 2026-07-06): a visible "强制重新认证" `TextButton.icon`
  appears under the Start/Stop button when `_isRunning == true`. It routes through
  `AuthController.forceAuthReset()` → `bindings.esurfingClientForceAuthReset()` →
  C-side `esurfing_client_force_auth_reset()` (sets `is_need_reset=1`,
  picked up by the next heartbeat tick and rebuilds the dialer chain without
  waiting for the next backoff cycle). The button is hidden when stopped so idle
  users can't bypass the config-required check.

## Common tasks

From the **repo root** (outer directory — what the CI uses):

```bash
# Install Dart/Flutter deps
flutter pub get

# Static analysis (the project pins flutter_lints ^4.0.0)
flutter analyze

# Run widget/unit tests
flutter test
flutter test path/to/some_test.dart   # single file

# What GitHub Actions runs to produce the release APK
flutter build apk --release --android-skip-build-dependency-validation \
  --build-name=1.1.<N> --build-number=<N>
```

Notes on the build step:
- The build pulls libcurl ~8.9.0 from GitHub via `FetchContent` and compiles four ABIs. It's slow on a clean cache — expect several minutes for the native half alone.
- Because the C `CMakeLists.txt` uses `FetchContent` for curl/cJSON, an outbound network connection is required for the first NDK build. Offline second builds are fine.
- Output APK lands at `build/app/outputs/flutter-apk/app-release.apk`.

There is no `ios/`, `web/`, or `linux/` target configured — only `android`. Editing native code inside `android/app/src/main/cpp/` is the only way to change protocol behavior; Flutter-only changes never touch the C daemon.

## Editing rules that matter for this repo

* **Native edits**: only the outer `android/app/src/main/cpp/**` is what the active CI pipeline reads. The nested `esurfing_flutter/android/...` copy is out of sync — verify before editing so your change actually ships.
* **Bridge sync**: if you add/remove/rename an exported symbol in `ffi_bridge.{h,c}`, you must mirror the mangled `typedef` and `lookupFunction` line in `lib/src/native/bindings.dart` and the call in `auth_controller.dart`. A mismatch fails at **runtime** (no static check), with an `DynamicLibrary` lookup error.
* **Log reader contract**: `LogReader.clear()` calls C-side `esurfing_client_clear_log()` — which truncates the file *from inside the same process* — **then** resets the byte offset. Don't change one without the other, or you replay the whole file on next poll.
* **Flutter lint config**: project uses `flutter_lints: ^4.0.0` from `pubspec.yaml`. Run `flutter analyze` before pushing — the CI will reject the build on warnings it surfaces.
* **Magisk sync**: the `magisk` branch shares protocol code with `main`. When fixing something in `cipher/` or `NetClient.c`, check whether the same change needs cherry-picking to Magisk (recent commits show this pattern: "sync from magisk").

## README vs reality

The `README.md` is primarily user-facing — install steps, operation guide, and a 13-item "fixed vs original CVersion" table. For development truths (build command, layout, FFI contract), rely on this CLAUDE.md, not the README. The README's "push to `main` → wait 5–8 min" note is accurate for CI latency; the local build is not mentioned there.
