# ControlSurfaceKit

Deterministic, device-neutral building blocks for control-surface adapters.
NorthBoundWisdom · MIT · Swift 6 · Foundation only · macOS and Linux.

J-2 adds immutable device-neutral contracts and test-support scenario assets.
Host adoption is tracked by the workspace review, not inferred from this package.
Context, connection and feedback targets deliberately contain boundary markers
only; their reducers must first pass host shadow runs.

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

Prepare the schema-check environment once with `python3 -m venv build/schema-validation`
and `build/schema-validation/bin/python -m pip install jsonschema`. Run the whole
check set with `build/schema-validation/bin/python -B scripts/check.py`. The boundary checker
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

See [field-by-field contract mapping and shadow procedure](docs/neutral-contract-mapping.md),
[unchanged scenario interface](docs/controller-regression.md),
[original-asset hashes/test mapping](docs/scenario-asset-manifest.json), and
[new-device paper example and current evidence limits](docs/new-device-example.md).
Caller code supplies fixture `Data`; production Sources never load files/resources.
The unchanged Python validator remains the full closed-schema/reference authority.
The Swift typed reader and exact assertion/trace helpers add no ideal host reducer.
