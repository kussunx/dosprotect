# DoS Protect

Modern revamp of the original **DoS Protect** Metamod:Source plugin, focused on preserving its proven Left 4 Dead UDP DoS mitigation behavior while updating the codebase, build process, diagnostics, and maintainability.

## Authorship

- **Revamp / current maintainer:** Kussun
- **Original project / original author:** ZombieX2.net

This repository is a substantial modernization effort based on the original DoS Protect source. Credit for the original implementation and concept remains with ZombieX2.net.

## Compatibility goal

The first compatibility requirement of the revamp is to preserve the original Left 4 Dead mitigation behavior around `recvfrom()` where a zero-length UDP datagram is handled using the legacy compatibility path (`ret == 0` -> `return 25`). That behavior is treated as a regression-sensitive feature and must not be removed without verified replacement behavior.

## Project status

The repository currently contains the original source baseline with updated revamp metadata. Build automation, modern project structure, diagnostics, and code modernization will be added incrementally while preserving the working L4D protection behavior.

## License

The original source snapshot does not include a clear standalone license file. No new license is asserted here until the licensing status of the original source is established.
