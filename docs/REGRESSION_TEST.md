# Runtime regression acceptance test

This procedure validates that a new DoS Protect build still blocks the same real-world UDP attack case that motivated the original plugin.

The source/CI guard only verifies that the legacy compatibility path remains present. Runtime acceptance must still be performed on actual L4D1 and L4D2 dedicated servers.

## Required builds

- L4D1: `dosprotect_l4d1_mm.dll`
- L4D2: `dosprotect_l4d2_mm.dll`

Both must come from the same tested source revision.

## Test each game independently

Run the complete sequence once on Left 4 Dead and once on Left 4 Dead 2.

### 1. Establish the unprotected control

1. Stop the dedicated server.
2. Ensure DoS Protect is not loaded, or start it with protection disabled for the control condition.
3. Start the server and confirm normal operation.
4. Reproduce the already-known disruptive UDP test case from the controlled test environment.
5. Confirm the expected unprotected symptom is reproducible.
6. Stop the test traffic.

Do not accept a protection result if the control condition cannot reproduce the known issue; otherwise the test cannot distinguish a successful mitigation from an inactive test case.

### 2. Validate the protected build

1. Install the correct target package.
2. Restart the server.
3. Run `meta list` and verify DoS Protect is loaded.
4. Run `dosp_status` and verify:
   - `Status: ENABLED`
   - `Compatibility: LEGACY-25`
   - the expected game and binary are shown.
5. Reproduce the same controlled UDP test case with the same test setup used for the control.
6. Confirm the disruptive server effect is blocked or materially mitigated to the same degree as the known-working original plugin.
7. Run `dosp_status` and verify `Total zero UDP intercepted` increased.
8. Run `dosp_top` and verify source accounting is plausible when a valid IPv4 source is available.

### 3. Validate protection toggling

1. Run `dosp_enable 0`.
2. Run `dosp_status` and verify `Status: DISABLED`.
3. Run `dosp_enable 1`.
4. Run `dosp_status` and verify `Status: ENABLED` and the hook reactivates without requiring a restart.

### 4. Validate telemetry reset

1. Record the current counters from `dosp_status`.
2. Run `dosp_reset`.
3. Verify counters and retained sources reset to zero/empty.
4. Verify `Status: ENABLED` remains unchanged.
5. Repeat a short controlled protection test and confirm counters begin increasing again.

## Acceptance criteria

A build is accepted only when all of the following are true for both L4D1 and L4D2:

- Metamod loads the target-specific DLL successfully.
- The known unprotected control condition reproduces the disruptive behavior.
- With DoS Protect enabled, the same test case is blocked to the expected degree.
- `dosp_status` confirms `LEGACY-25` compatibility mode and increments interception telemetry.
- Disabling and re-enabling the hook works without a server restart.
- Telemetry reset does not alter protection state.
- Normal player connections, gameplay and server query behavior remain functional during a representative smoke test.

## Change-control rule

Do not replace or remove `ret == 0 -> return 25` solely because it appears unconventional in isolation. A replacement packet-handling strategy is acceptable only after it passes this full runtime regression procedure against the same known attack case on both supported games.
