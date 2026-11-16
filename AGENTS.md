# ControlSurfaceKit rules

Organization: NorthBoundWisdom. License: MIT. Default branch: main.
The parent workspace AGENTS.md applies. One writer; no branches/worktrees/stash;
fetch before work and commits when an origin exists. Do not create the remote.
Until the user creates it, commit locally; hosts must not push unreachable locks.

This package owns deterministic device-neutral value types and pure functions.
Production code imports only Foundation and earlier targets in the enforced DAG.
Every exposed value must be Sendable. Time and endpoint identities are supplied
by the caller. No I/O, clocks, timers, callbacks, mutable globals or device names,
addresses, counts, layouts, protocol codecs or device safety policies in Sources.
Never store a second parameter authority or reimplement SurfacePlugins parameter
quantization, business plugins, or control-contract sessions. Neither repository
depends on the other; hosts bridge opaque IDs and own parameter values.

SurfaceDeviceConformance is test support, forbidden as a production dependency.
A new reducer is adopted only after stepwise shadow comparison, unchanged scenario
hashes, full host suites and byte-identical golden sequences. Device-specific
safety remains in adapters. No real hardware is connected by this repository.

Before committing: python3 -B scripts/check_boundaries.py; python3 -B -m unittest
discover -s scripts/tests -v; swift test --build-path build/swiftpm. Keep original
logs and exact counts in the workspace build/j-main/k and append reports/K.md.
No root-workspace commits, tags, Releases, fixture weakening or test skipping.
