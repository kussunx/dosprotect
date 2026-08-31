# DoS Protect

DoS Protect is a small Metamod:Source plugin for **Left 4 Dead** and **Left 4 Dead 2** that filters zero-length UDP datagrams before they reach the Source packet parser.

This repository is a maintained rewrite of the original DoS Protect by **ZombieX2.net**. The current version is maintained by **Kussun** and uses the `DROP-WOULDBLOCK` handling path that has been runtime-tested on both games.

> DoS Protect is intentionally narrow in scope. It is not a general-purpose DDoS firewall.

## Supported games

| Game | Binary |
| --- | --- |
| Left 4 Dead | `dosprotect_l4d1_mm.dll` |
| Left 4 Dead 2 | `dosprotect_l4d2_mm.dll` |

Current builds target **Windows x86 / Win32** and Metamod:Source.

## How it works

The plugin hooks `g_pVCR->Hook_recvfrom`. Normal datagrams and socket errors are returned to the engine unchanged.

When Winsock returns a zero-length UDP datagram, DoS Protect consumes it instead of passing it to the packet parser. If more data is already queued, it drains additional zero-length datagrams up to a bounded per-call budget. The first real datagram encountered is forwarded unchanged. If there is nothing useful left to deliver, the hook returns `SOCKET_ERROR` with `WSAEWOULDBLOCK`.

The drain is deliberately bounded so a burst cannot keep one receive callback busy indefinitely.

## Installation

Metamod:Source must already be installed.

### Left 4 Dead

Copy:

```text
addons/dosprotect/bin/dosprotect_l4d1_mm.dll
addons/metamod/dosprotect.vdf
```

Use `config/dosprotect_l4d1.vdf` from this repository as `addons/metamod/dosprotect.vdf`.

### Left 4 Dead 2

Copy:

```text
addons/dosprotect/bin/dosprotect_l4d2_mm.dll
addons/metamod/dosprotect.vdf
```

Use `config/dosprotect_l4d2.vdf` from this repository as `addons/metamod/dosprotect.vdf`.

Restart the server, then verify:

```text
meta list
dosp_status
```

## Commands

| Command | Description |
| --- | --- |
| `dosp_status` | Shows protection state, counters, PPS and the busiest tracked sources. |
| `dosp_top` | Shows the top 20 tracked IPv4 sources. |
| `dosp_reset` | Clears telemetry and tracked sources without disabling protection. |

## ConVars

| ConVar | Default | Description |
| --- | ---: | --- |
| `dosp_enable` | `1` | Enables or disables the recvfrom hook. |
| `dosp_drain_budget` | `256` | Maximum zero-length datagrams drained in one hook call. Effective range: `1..4096`. |
| `dosp_max_sources` | `4096` | Maximum IPv4 source records kept for telemetry. Effective range: `128..65536`. |
| `dosp_expire_seconds` | `900` | Removes inactive source records after this many seconds. `0` disables expiry. |
| `dosp_version` | — | Plugin version. |

The protection itself does not depend on source tracking. If the telemetry table is full, zero-length datagrams are still dropped.

## Building

Requirements:

- Windows
- Visual Studio with Desktop development with C++ and x86 tools
- Git
- PowerShell

Build both games:

```powershell
.\scripts\build.ps1 -Target all
```

Or build one target:

```powershell
.\scripts\build.ps1 -Target l4d
.\scripts\build.ps1 -Target l4d2
```

The build script downloads the pinned Metamod:Source and HL2SDK revisions automatically and writes packages under `artifacts/`.

## Credits

- **ZombieX2.net** — original DoS Protect project and source
- **Kussun** — current rewrite and maintenance

## License

The original source snapshot did not include a clear standalone license. This repository does not invent or assert a new license for the inherited code. Metamod:Source and HL2SDK are external build dependencies and keep their respective upstream licenses.
