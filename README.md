# DoS Protect

DoS Protect is a Metamod:Source plugin for **Left 4 Dead** and **Left 4 Dead 2** that filters zero-length UDP datagrams before they reach the Source packet parser.

It is based on the original DoS Protect by **ZombieX2.net**. The packet handling has been rewritten around `DROP-WOULDBLOCK` and tested on dedicated servers for both games.

The plugin is intentionally focused on this specific packet condition. It is not a replacement for network-level DDoS protection.

## Supported games

| Game | Platform | Binary |
| --- | --- | --- |
| Left 4 Dead | Windows x86 | `dosprotect_l4d1_mm.dll` |
| Left 4 Dead 2 | Windows x86 | `dosprotect_l4d2_mm.dll` |

The 2.0.0 release is built and tested with **Metamod:Source 1.12-git1225.**

## How it works

DoS Protect hooks `g_pVCR->Hook_recvfrom`. Normal datagrams and socket errors pass through unchanged.

When Winsock returns a zero-length UDP datagram, the plugin consumes it instead of handing it to the Source packet parser. If more data is already queued, additional zero-length datagrams are drained up to a bounded per-call budget. The first real datagram encountered is forwarded unchanged. If there is nothing useful left to deliver, the hook returns `SOCKET_ERROR` with `WSAEWOULDBLOCK`.

The drain budget keeps one receive callback from monopolizing the server thread during a burst.


### Left 4 Dead

Copy the files to:

```text
left4dead/addons/dosprotect/bin/dosprotect_l4d1_mm.dll
left4dead/addons/metamod/dosprotect.vdf
```

Use `config/dosprotect_l4d1.vdf` as `addons/metamod/dosprotect.vdf`.

### Left 4 Dead 2

Copy the files to:

```text
left4dead2/addons/dosprotect/bin/dosprotect_l4d2_mm.dll
left4dead2/addons/metamod/dosprotect.vdf
```

Use `config/dosprotect_l4d2.vdf` as `addons/metamod/dosprotect.vdf`.

Restart the server and check:

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
| `dosp_drain_budget` | `256` | Maximum zero-length datagrams drained in one hook call. Range: `1..4096`. |
| `dosp_max_sources` | `4096` | Maximum IPv4 source records kept for telemetry. Range: `128..65536`. |
| `dosp_expire_seconds` | `900` | Removes inactive source records after this many seconds. `0` disables expiry. |
| `dosp_version` | — | Plugin version. |

Source tracking is telemetry only. If the source table is full, zero-length datagrams are still dropped.

## Building

Requirements:

- Visual Studio with Desktop development with C++ and x86 tools
- Git
- PowerShell

Build both targets:

```powershell
.\scripts\build.ps1 -Target all
```

Or build one game:

```powershell
.\scripts\build.ps1 -Target l4d
.\scripts\build.ps1 -Target l4d2
```

The build script fetches the pinned Metamod:Source and HL2SDK revisions and writes the packages under `artifacts/`.

## Credits

- **ZombieX2.net** — original DoS Protect project and source
- **Kussun** — rewrite
