# ControlSurfaceKit

Deterministic, device-neutral building blocks for control-surface adapters.
NorthBoundWisdom · MIT · Swift 6 · Foundation only · macOS and Linux.

J-2 adds immutable device-neutral contracts and test-support scenario assets.
J-3 adds first-match binding lookup, exact lifecycle scopes, connection transitions
and ordered scoped resource ownership. See [runtime integration](docs/context-runtime.md).
J-4 adds immutable feedback plans, explicit stage/full native proof validation and
actual-attempt receipts. See [feedback integration](docs/feedback-runtime.md).
Host adoption is tracked by the workspace review, not inferred from this package.
Each runtime block must pass independent host shadow runs before it controls
product behavior. Rate/dedup scheduling remains native pending its separate
executable shadow/difference report.

| Target | Responsibility | May depend on |
| --- | --- | --- |
| SurfaceDeviceContracts | Input, observation, effect and endpoint vocabulary | Foundation |
| SurfaceBindingContext | Opaque bindings and context invalidation | Contracts |
| SurfaceConnectionState | Caller-driven value reducer and connection generations | BindingContext |
| SurfaceFeedbackPlanning | Immutable plans, native proof and receipts | Contracts, BindingContext, ConnectionState |
| SurfaceDeviceConformance | Scenario data, strict assertions and trace test support | All four, tests only |

This is not a device driver, parameter store, business plugin, remote service,
transport or GUI. SurfacePlugins remains the sole owner of parameter definitions,
quantization, business plugins and consumer control-contract sessions. The two
production libraries have no dependency on each other. The host runtime joins opaque IDs;
there is no second parameter authority in this package.

For a new device, provide stable element/endpoint identities, a protocol decoder,
an effect encoder, structured capability and side-effect declarations, and all
device-specific policies. The host supplies monotonic time and serial ownership.
Device touch/layer/motor/preset safety is mandatory adapter logic, not optional
kernel switches. See [adapter integration](docs/new-device.md).

Prepare the schema-check environment once with `python3 -m venv build/schema-validation`
and `build/schema-validation/bin/python -m pip install jsonschema`. Run both checks:

```sh
build/schema-validation/bin/python -B scripts/check.py
build/schema-validation/bin/python -B scripts/check_integration.py
```

The first command checks the production Kit graph, boundaries, unchanged scenario
assets and unit suites. The boundary checker reads the evaluated SwiftPM manifest
and Swift parser AST; its negative fixtures run separately. It remains a guardrail,
not a proof of semantic purity.

The second command checks two independent **test-only** graphs. Main integration
uses current Kit plus managed SP5ff; AuthorityBridge uses managed BCR366 with its
original SP12ba/Kit655 pins, in a separate process/scratch directory. Those older
bridge libraries never substitute for current Kit in the device pipeline.
Production libraries gain no cross-dependency. See [complete integration,
identities and evidence](docs/j5-integration.md).

Across both commands there are three SwiftPM graphs: Core, main integration and
authority bridge, each with one build/test invocation and its own cache. Compiled
executables serve every scenario; no case rebuilds a graph. CI restores keyed
caches/mtimes, still verifies all managed sources, and runs both complete commands
within each existing five-minute macOS/Linux job. Whole workflow time, including
queue/cold/post-processing, must also meet the workspace budget.

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
