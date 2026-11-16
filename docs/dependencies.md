# Dependency and ownership decision (J-1)

The supervisor approved no dependency in either direction between this package
and SurfacePlugins (2026-11-16). This follows ARCHITECTURE section 4: the host
runtime assembles the two packages. Kernel IDs remain opaque identifiers.

SurfacePlugins alone defines parameter ranges/steps/quantization, business
plugins and consumer control-contract sessions. Kernel source must not define
these types or implementations, and must not own business parameter values.
The checker evaluates `swift package dump-package`, enforces the target DAG,
rejects external products/packages, and checks real Swift parsed imports.
Source guards reject known duplicated authority and quantization patterns;
review remains necessary to detect renamed semantic reimplementations.

The kernel has five targets, including one test-support library. Production
targets cannot import or depend on the conformance target. Context/connection/
feedback targets in J-1 carry only linked boundary markers. No behavioral
reducer is implemented, shadow-compared or adopted at this stage.

All production source is platform-neutral. Conditional compilation is rejected
because Swift's parse dump omits inactive branches; platform-specific code
belongs in adapters. Parser format changes or omitted files fail the check.
Local variables and value-instance properties may mutate; parsed top-level
variables, static mutable variables, reference/actor types and known mutable
Foundation reference containers are forbidden. Immutable literal static values
are allowed. Checks do not claim a formal proof of side-effect freedom.
