# UnityTraceLab v0.1: iOS IL2CPP metadata and event markers

New, independently authored companion for https://github.com/tien0246/IOS-Il2CppDumper (MIT license). This first version does **not** yet include the original dump engine. Integrating it is planned.

## Implemented
- Floating UIKit UT button and menu inside a compatible injected iOS application.
- Passive IL2CPP method catalog: assembly/class/method, return and parameter types if exports are available.
- Keyword filter and JSONL output methods.jsonl (12,000 result cap).
- User-labeled baseline/target event markers with timestamps, events.jsonl.
- Explicit errors, file export using the iOS share sheet.
- GitHub Actions unsigned arm64 .dylib build.

## Critical limitation
Cataloged methods are NOT necessarily executed methods. Baseline and target markers do NOT automatically trace function calls or identify headshot handlers. Runtime hooking, method RVA extraction, AI target ranking, and anti-cheat bypass are not implemented.

## Platform
The compiled dylib has a minimum iOS deployment target of 14, but TrollStore and TrollFools support a much smaller range: selected iOS versions 14.0–17.0. iOS 26.5 is unsupported by TrollStore. Injection into an arbitrary protected game is not guaranteed.

## Test in an authorized development app
Download the workflow artifact. On a device with supported TrollFools and a Unity IL2CPP build you own or are authorized to inspect, load the unsigned .dylib with a compatible injector. Tap UT. Type a keyword such as Damage, tap Index matching IL2CPP methods, then use baseline/target markers and Export logs to Files / Share.

Logs live under the host application's Documents/UnityTraceLab. No network communication, code modification, or bypass behavior is included.

## Roadmap
- v0.2: opt-in function call tracing in a test Unity app using known methods.
- v0.3: rank method calls by frequency during target vs baseline intervals.
- v0.4: upstream Dumper source integration and IDA/Ghidra exports.
- v0.5: structured error reports, recovery tests, device performance tuning.

## Attribution
New companion code MIT © 2026 UnityTraceLab contributors. Upstream IOS-Il2CppDumper MIT © 2024 tien0246. Retain its license when incorporating its code.
