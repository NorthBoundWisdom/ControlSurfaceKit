# Scheduling differences at the J-round close

The supervisor's 2026-11-17 decision keeps scheduling in the hosts. The
`SurfaceDeviceConformance` candidate is test support; no production target may
depend on it. Feedback plan/proof/receipt adoption is a separate decision.
This page summarizes accepted evidence, without replaying deleted large traces.

| Area | Accepted result | Consequence for a later extraction |
| --- | --- | --- |
| Rate bucket, FIFO, same-key replacement, failure cooldown | B's independent bucket comparison covered 202 owners and 727 operations with zero differences. | These mechanisms have demonstrated reusable behavior. This does not prove the complete host schedulers equivalent or authorize a production switch. |
| Synchronous acknowledgement | B retains an actual admission result and receipt for every synchronous request. The candidate's accepted-receipt cache can suppress an identical request. | Preserve per-request acknowledgement. A cached success is not a new transmission or receipt. |
| Permission withdrawal and intent lifetime | After observe permission withdrawal, native policy drops intent while the fixed candidate retains it. | Drop/retain is a caller authorization and intent-lifetime policy to specify explicitly; it is not established as a B-only hardware rule. |
| Planned versus successful dedup | C has generation-time command caches; the candidate deduplicates only after an accepted matching receipt in the current scope. | Keep generated intent, actual accepted transmission and observed device state distinct. |
| Device safety and reentry | Touch, layer continuity/mismatch, motors, endpoint pins and B's callback linearization remain native. | Mandatory adapter policy stays outside Core; it cannot become an optional gate or configurable bypass. |

B's complete session comparison recorded 26,997 inputs and 2,618 scheduling
differences. The 828 cache-related missing proposals, 828 downstream alignment
differences, 822 direct dispositions and 88 withdrawal differences are associated
categories, not independent counts to add. Of 47 queue deltas, 12 causal
associations were independently checked. Five candidate-only proposals lack the
original native getter execution facts: their attribution remains unknown.
For C, 1,361 unproved attributions likewise remain unknown, rather than being
declared policy differences. These counts are not feedback-plan failures.

The accepted plan shadows compared B's 53,036 algorithm records with zero
differences (17,495 observation records counted separately) and C's 8,498
stage/preflight/receipt records with zero raw UTF-8 differences. They establish
the plan block's evidence, not scheduler equivalence or physical qualification.

A later proposal should specify synchronous acknowledgement, drop/retain and
dedup phase separately, then prove each adapter with independent inputs and its
own fresh gates. It must preserve ordered output, per-request receipts, current
scope eligibility and callback order, without filling missing evidence or
introducing a second parameter authority. Do not change existing published
contract semantics as a side effect of scheduler extraction.

Sources: workspace `reports/J_CONT_DECISIONS.md`, sections “J-4调度差异的监督裁定与原始格式返工范围”,
“两宿主J-4计划功能影子门闭合” and “C J4表示层首轮返工闭合”; candidate policy is in
[scheduler-candidate.md](scheduler-candidate.md). Reuse measurements and their
limits are in [extraction-measurements.md](extraction-measurements.md).

## O-4 production mechanism

The shared scheduling API is now defined in [scheduling-runtime.md](scheduling-runtime.md).
It makes the request-equality phase and permission-withdrawn intent lifetime
explicit while keeping mandatory device safety and callback order native. The
J-round counts above remain unchanged historical observations. Adding the API
is not host acceptance or a reclassification of previously unknown differences.
