# Test-only authority bridge

Independent process for J5 composition, using only the existing production
BCRSurfaceDomain public library as a caller-owned parameter authority. It is not
a device host or released product. The main device pipeline uses the current
under-test Kit independently; this bridge keeps the host's original dependency
locks and does not claim to test that current device runtime.

Acquire BCR with `python3 configs/bcr_authority_dependency.py ensure`, then run
the acquired repository's original SP and Kit ensure scripts. All developer
source overrides are acquisition-only. Build only AuthorityBridge with
`BCR_PORTABLE_BUILD=1 swift build --product AuthorityBridge --build-path build/swiftpm`.

The reference vendored stdlib/Git manager is byte-identical to
BCR2000Dev commit36692f1422b0c3952f9048847a0bafd65421bc72,
`configs/managed_git_dependency.py`, under the same NorthBoundWisdom MIT license.
The separate test-only authority_source_manager.py adds the supervisor-approved
finite nested-artifact boundary: only the host's original separately verified
SP/Kit seeds and their regular locks. All other ignored/untracked/source changes
are rejected, with original remote/revision/ownership checked. No build output
may reside in the host source. No production manager is changed.
No FreeCM engine is imported. Prototype smoke evidence lives outside Sources
under the workspace's ignored build/j-main-cont/k directory. Do not treat smoke
as the17row/35step full-device acceptance result.

Actual prototype smoke (no shared scenarios):

```sh
python3 -B tests/managed_source_boundaries.py --evidence /path/to/ignored/evidence
python3 -B tests/smoke.py --bridge build/swiftpm/debug/AuthorityBridge --evidence /path/to/ignored/evidence
```

The bridge compiled against the public library without adding a host API.
The main smoke executes28bounded commands and checks the real write, rejection,
history, instance separation and destruction paths. Three malformed-frame
controls reject. The manager check has2positive and7negative checks and restores
its owned seeds afterward. These are prototype checks, not full scenario results
or main-package CI adoption. Logs and source identities are recorded by the
workspace K report. The original first build failure from strict rejection of
the host's own managed nested dependencies is retained; the limited test-only
manager extension was explicitly approved before the successful build.

The complete integration driver is `scripts/check_integration.py` in the parent
Kit repository. It preserves the original smoke/manager/framing checks and
registers the bridge graph separately from current device runtime. Full scenario
results and remaining platform-placement limit are in
[the integration document](../docs/j5-integration.md).
