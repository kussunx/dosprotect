# Runtime regression acceptance test

This procedure validates that a new DoS Protect build still blocks the same real-world UDP attack case that motivated the original plugin.

`2.0.0-dev.3` changes the default zero-length datagram response from `LEGACY-25` to `DROP-WOULDBLOCK`. The source/CI guard verifies that both paths remain present, but runtime acceptance must still be performed on actual L4D1 and L4D2 dedicated servers.

## Required builds

- L4D1: `dosprotect_l4d1_mm.dll`
- L4D2: `dosprotect_l4d2_mm.dll`

Both must come from the same tested source revision.

## Mitigation modes

Modern default:

```text
dosp_mitigation_mode 1
```

Expected status:

```text
Mitigation: DROP-WOULDBLOCK
```

Known-working fallback:

```text
dosp_mitigation_mode 0
```

Expected status:

```text
Mitigation: LEGACY-25
```

Changing the mode does not require a server restart.

## Test each game independently

Run the complete sequence once on Left 4 Dead and once on Left 4 Dead 2.

### 1. Establish the unprotected control

1. Stop the dedicated server.
2. Ensure DoS Protect is not loaded, or start it with `dosp_enable 0` for the control condition.
3. Start the server and confirm normal operation.
4. Reproduce the already-known disruptive UDP test case from the controlled test environment.
5. Confirm the expected unprotected symptom is reproducible.
6. Stop the test traffic.

Do not accept a protection result if the control condition cannot reproduce the known issue.

### 2. Validate modern DROP-WOULDBLOCK

1. Install the correct `2.0.0-dev.3` target package.
2. Restart the server.
3. Run `meta list` and verify DoS Protect is loaded.
4. Run `dosp_status` and verify:
   - `Status: ENABLED`
   - `Mitigation: DROP-WOULDBLOCK`
   - the expected game and binary are shown.
5. Reproduce the same controlled UDP test case with the same test setup used for the control.
6. Confirm the disruptive server effect is blocked or materially mitigated to the same degree as the known-working legacy build.
7. Run `dosp_status` and verify:
   - `Total zero UDP intercepted` increased;
   - `Modern drops` increased;
   - `Legacy-25 responses` remains zero unless the fallback was selected manually.
8. Run `dosp_top` and verify source accounting is plausible when a valid IPv4 source is available.
9. Confirm normal player connections, gameplay and server query behavior still work during and after the protected test.

### 3. A/B compare with LEGACY-25

If modern mode fails to block the known issue, behaves differently from the accepted baseline, or causes a compatibility regression:

1. Stop the test traffic.
2. Run:

```text
dosp_mitigation_mode 0
```

3. Run `dosp_status` and verify `Mitigation: LEGACY-25`.
4. Repeat the same controlled test without changing any other test variable.
5. Confirm the known legacy behavior still blocks the issue.
6. Record the difference between modern and legacy behavior before making further packet-path changes.

The ability to switch modes at runtime is specifically intended to make this comparison deterministic and fast.

### 4. Validate protection toggling

1. Run `dosp_enable 0`.
2. Run `dosp_status` and verify `Status: DISABLED`.
3. Run `dosp_enable 1`.
4. Run `dosp_status` and verify `Status: ENABLED` and the hook reactivates without requiring a restart.

### 5. Validate telemetry reset

1. Record the current counters from `dosp_status`.
2. Run `dosp_reset`.
3. Verify counters and retained sources reset to zero/empty.
4. Verify protection state and selected mitigation mode remain unchanged.
5. Repeat a short controlled protection test and confirm counters begin increasing again.

## Acceptance criteria for DROP-WOULDBLOCK

The modern mode is accepted only when all of the following are true for both L4D1 and L4D2:

- Metamod loads the target-specific DLL successfully.
- The known unprotected control condition reproduces the disruptive behavior.
- With `dosp_mitigation_mode 1`, the same test case is blocked to the expected degree.
- `dosp_status` confirms `DROP-WOULDBLOCK` and increments `Modern drops`.
- No fabricated positive receive length is used by the active modern path.
- Player connections, gameplay, Steam/server queries and ordinary UDP traffic remain functional.
- Disabling and re-enabling the hook works without a server restart.
- Telemetry reset does not alter protection state or mitigation selection.

## Change-control rule

Do not remove `LEGACY-25` yet. It is the known-working reference behavior and remains the immediate fallback for `dev.3`.

After `DROP-WOULDBLOCK` passes this full runtime regression procedure on both supported games, a later revision may promote it from experimental modern default to the established compatibility baseline. Removal of `LEGACY-25` should be a separate decision after additional soak testing.
