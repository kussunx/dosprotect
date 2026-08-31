# Changelog

## 2.0.0

- Reworked the original recvfrom mitigation around the bounded `DROP-WOULDBLOCK` path and validated it on dedicated Left 4 Dead and Left 4 Dead 2 servers.
- Added separate Win32/x86 binaries and packages for L4D1 and L4D2.
- Added bounded draining of consecutive zero-length UDP datagrams without fabricating packet lengths for the engine.
- Added source tracking, expiry, PPS statistics and runtime diagnostics.
- Added configurable drain budget and bounded source telemetry.
- Hardened recvfrom hook installation and removal so the plugin does not break a later hook in the chain.
- Reduced hot-path work during bursts and corrected PPS calculation to use the actual elapsed window.
- Added reproducible builds with pinned Metamod:Source and HL2SDK revisions.
- Removed the old `LEGACY-25` path and obsolete compatibility code.
