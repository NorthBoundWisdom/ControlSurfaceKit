# ControlSurfaceKit

Deterministic, device-neutral building blocks for control-surface adapters.
NorthBoundWisdom · MIT · Swift 6 · Foundation only · macOS and Linux.

J-1 establishes the package and mechanically checked boundaries. No host has
adopted kernel behavior yet. Context, connection and feedback targets deliberately
contain boundary markers only; their reducers must first pass host shadow runs.

| Target | Responsibility | May depend on |
| --- | --- | --- |
| SurfaceDeviceContracts | Input, observation, effect and endpoint vocabulary | Foundation |
| SurfaceBindingContext | Opaque bindings and context invalidation | Contracts |
| SurfaceConnectionState | Caller-driven value reducer and connection generations | BindingContext |
| SurfaceFeedbackPlanning | Immutable plans and pre-send validation | ConnectionState |
| SurfaceDeviceConformance | Scenario data, strict assertions and trace test support | All four, tests only |

This is not a device driver, parameter store, business plugin, remote service,
transport or GUI. SurfacePlugins remains the sole owner of parameter definitions,
quantization, business plugins and consumer control-contract sessions. The two
libraries have no dependency on each other. The host runtime joins opaque IDs;
there is no second parameter authority in this package.

For a new device, provide stable element/endpoint identities, a protocol decoder,
an effect encoder, structured capability and side-effect declarations, and all
device-specific policies. The host supplies monotonic time and serial ownership.
Device touch/layer/motor/preset safety is mandatory adapter logic, not optional
kernel switches. See [adapter integration](docs/new-device.md).

Run the whole check set with `python3 -B scripts/check.py`. The boundary checker
reads the evaluated SwiftPM manifest and the Swift parser AST, then applies source
rules. Its negative fixtures are tested separately. It is a guardrail, not a proof
of semantic purity; review and differential evidence are still required.
CI shares the existing workspace strategy: toolchain-keyed build cache, tracked
Git mtimes restored before compilation, one Swift build/test invocation per run.

Hosts acquire this repository using the same managed, clean, atomically populated
full-SHA lock mechanism as SurfacePlugins. Development checkouts are acquisition
sources only. Push order: SurfacePlugins → ControlSurfaceKit → hosts; verify each
exact remote SHA's CI before dependent locks advance. The remote is
`https://github.com/NorthBoundWisdom/ControlSurfaceKit.git`, created by the user.
The initial remote commit is preserved; pushes require supervisor review and
exact-SHA CI.
