# Changelog

## 2.0.0-dev.4

- `DROP-WOULDBLOCK` is now the only mitigation path after successful runtime validation on both Left 4 Dead and Left 4 Dead 2.
- Removed the old `LEGACY-25` fallback, its selector ConVar and legacy-only telemetry.
- Reduced hot-path overhead by sharing one monotonic timestamp across each drained burst and moving expiry/PPS maintenance out of the per-datagram accounting function.
- Made PPS calculation use the actual elapsed window instead of whole-second truncation.
- Increased source-expiry maintenance interval to reduce attack-path work.
- Fixed hook-chain handling so disable/unload refuses to break a later recvfrom hook.
- Simplified the build checks, CI workflow and public documentation.
- Removed obsolete compatibility scaffolding and development-only regression documentation.

## 2.0.0-dev.3

- Introduced the bounded `DROP-WOULDBLOCK` mitigation.
- Added configurable drain budget and drain-budget telemetry.
- Added runtime source tracking, expiration, PPS statistics and diagnostics.
- Added separate L4D1 and L4D2 Win32 binaries and packages.

## 2.0.0-dev.1 / dev.2

- Established the dual-game build baseline.
- Modernized source tracking and hook lifecycle around the original plugin behavior.
