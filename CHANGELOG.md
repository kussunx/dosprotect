# Changelog

All notable revamp changes are tracked here.

## 2.0.0-dev.3

### Mitigation

- Added `DROP-WOULDBLOCK` as the new default zero-length UDP mitigation.
- The real `recvfrom()` still consumes the zero-length datagram, but the hook now reports `SOCKET_ERROR` with `WSAEWOULDBLOCK` on Windows instead of fabricating a positive packet length.
- Added runtime A/B selection through `dosp_mitigation_mode`.
- Kept the previously validated `LEGACY-25` path as `dosp_mitigation_mode 0` while the new path is regression-tested on both games.
- Added separate telemetry counters for modern drops and legacy fallback responses.
- Updated status output to report the active mitigation explicitly.
- Extended the source regression guard so CI requires both the modern default path and the emergency legacy fallback.

### Validation policy

- `DROP-WOULDBLOCK` must pass the same real runtime regression case already passed by `LEGACY-25` on L4D1 and L4D2.
- Normal player connections, server query behavior and gameplay must remain functional during the protected test.
- The legacy fallback is not removed as part of this revision.

## 2.0.0-dev.2

### Runtime

- Preserved the legacy compatibility contract: zero-length `recvfrom()` result -> `return 25`.
- Replaced the original linear `SourceHook::List<DoSCount *>` source lookup with a bounded `std::unordered_map`.
- Replaced 32-bit source counters with 64-bit counters.
- Added monotonic first/last-seen timestamps.
- Added bounded source retention with `dosp_max_sources` (default `4096`, effective range `128..65536`).
- Added inactivity expiration with `dosp_expire_seconds` (default `900`; `0` disables expiration).
- Added amortized maintenance instead of performing a full table scan for every intercepted packet.
- Added invalid/missing source-address accounting while preserving the mitigation response.
- Added accounting for packets not retained because the source table is full.
- Added total interception and PPS telemetry.
- Added ranked `dosp_top` output.
- Added `dosp_reset` for telemetry/source-table reset without disabling protection.
- Added safer `sockaddr`/`fromlen` validation.
- Added defensive hook lifecycle checks and idempotent enable behavior.
- Avoided overwriting a later third-party recvfrom hook when disabling/unloading.
- Kept the packet hot path free of per-packet logging.

### Build / packaging

- L4D1 binary renamed to `dosprotect_l4d1_mm.dll`.
- L4D2 binary renamed to `dosprotect_l4d2_mm.dll`.
- Added target-specific Metamod VDF descriptors.
- Added package validation for x86 PE architecture.
- Added validation for the Metamod `CreateInterface` export.
- Added validation that each packaged VDF references the matching target binary.
- Added `NOMINMAX` to avoid Windows macro collisions with the C++ standard library.

### Documentation

- Expanded README for dual-game build, installation, commands and ConVars.
- Added a runtime regression acceptance procedure.

## 2.0.0-dev.1

- Established a buildable dual-target baseline for L4D1 and L4D2.
- Added pinned Metamod:Source and HL2SDK dependencies.
- Added Windows x86 self-hosted GitHub Actions builds.
- Added a source regression guard for the legacy `ret == 0 -> return 25` behavior.
- Updated revamp authorship to Kussun while retaining credit to ZombieX2.net for the original project/source.
