# UnityTraceLab v0.2 — authorized Unity IL2CPP function tracing

Companion research tool inspired by https://github.com/tien0246/IOS-Il2CppDumper. The original Dumper code is NOT YET EMBEDDED. This separately authored component adds tracing to the v0.1 prototype.

## Features

- IL2CPP method catalog from a running UnityFramework using exported runtime APIs.
- Method entrypoints from version-dependent MethodInfo layout with executable Mach-O __text validation.
- Image-relative RVA and absolute addresses. Absolute addresses can change due to ASLR.
- Up to 256 actual executable bytes per method, 64 distinct bounded samples, with SHA-256 manifest. These are not full functions or decompiled C#.
- Opt-in Dobby native instrument callbacks for one to eight *distinct* method addresses. No automatic instrumentation.
- Exact runtime call counters and bounded 16,384-sample trace ring, sampling one out of eight calls for per-hit events.
- Timed BASELINE and TARGET intervals with per-second call-rate comparisons and candidate ranking. Correlation is NOT proof of causality.
- Structured export: methods.jsonl, events.jsonl, trace.jsonl, comparisons.jsonl, code_manifest.jsonl and .bin samples.
- Floating UIKit controls for indexing, arming, comparing, exporting, and restoring hooks.

## Usage

1. In an authorized Unity IL2CPP test app, open the UT overlay.
2. Type a specific class or method name such as PlayerController::ApplyDamage (illustrative placeholder).
3. Press 1 to index methods and RVAs, then 2 to arm a filter that resolves to 1–8 executable functions.
4. Start BASELINE, perform ordinary/control actions, and end the interval.
5. Start TARGET, perform one experimental action, and end the interval.
6. Compare and export; repeat several controlled trials, then disarm hooks.

## Compatibility, safety, limitations

- Only for apps you own or are authorized to instrument. No anti-cheat evasion, license bypass or persistence.
- Runtime hooks can crash an app. DobbyDestroy attempts to restore changed code instructions at disarm.
- MethodInfo first-pointer ABI is not guaranteed in every Unity release; instrument only validated addresses.
- IL2CPP names may be stripped or obfuscated. Some apps may not load UnityFramework or export methods.
- Complete native function sizes are NOT provided by IL2CPP. Machine-code dumps are bounded partial executable samples, not reconstructed managed source.
- No automatic detection of specific gameplay features. Scores are hypotheses and can have false positives.
- Built for arm64 iOS 15+; TrollStore/TrollFools exist only on selected iOS 14–17.0 versions, NOT iOS 26.5.
- Requires compatible library injection / code-signing environment on an authorized test app.

## Reproducible build

GitHub Actions compiles a statically linked Dobby Apache-2.0 backend and unsigned iOS ARM64 dylib. No signing keys uploaded. Download the archive from a successful workflow run. It contains a dylib, not an installable IPA.

## Status

This is a compiled prototype only until physically tested in authorized iOS Unity builds. Dobby hooks are runtime-dependent; compilation alone does not prove that a given game permits instrumentation.

## License

UnityTraceLab source MIT © 2026 UnityTraceLab contributors. Dobby Apache-2.0 © Dobby authors. IOS-Il2CppDumper upstream MIT © 2024 tien0246 is referenced, but not yet copied into this version.
