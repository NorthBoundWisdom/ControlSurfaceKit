# J-round extraction measurements

Measured on immutable Git objects, using the method in workspace
`reports/KIT_PROPOSAL.md` and `build/h-main/refresh_kit_inventory.py`.
The before revisions are B `3e81ac22f53712a464c44ab7bcf9dc348b541cba`
and C `4739a205e58ae6908ff7d71274ebd56bb719e2f4`; the close-preparation snapshot
is B `297dbc1f3c0085ad508a145f5f1f39622e764f53` and C
`f8dc367675829f093f6ae92766b86e7dd7cc8acf`. At this snapshot B has adopted feedback
planning; C has a zero-difference shadow and has not switched production planning.
These are snapshot measurements, not a claim that both hosts have completed J-4.

Physical lines include comments and blanks. The compared file sets are exactly
the original proposal's four groups; overlapping files must not be summed.
Whole-file equality compares SHA-256 bytes across the two hosts. Literal
matching trims line edges, removes blank/comment/import/standalone-brace lines,
then uses `difflib.SequenceMatcher(autojunk=False)` to count equal contiguous
blocks of at least four lines, without renaming identifiers. Neither measure
establishes semantic duplication or a percentage of functions extracted.

| Original file group | B physical lines before → after | C physical lines before → after | Equal complete files before → after | Matched literal lines per side before → after |
| --- | ---: | ---: | --- | ---: |
| Neutral device contract | 455 → 470 | 171 → 186 | 0/4 → 0/4 | 0 → 0 |
| Binding context | 719 → 835 | 482 → 533 | 0/8 → 0/8 | 6 → 6 |
| Connection/session | 1,059 → 1,846 | 1,024 → 1,651 | 0/4 → 0/4 | 0 → 0 |
| Feedback plan/scheduling | 954 → 1,118 | 441 → 993 | 0/4 → 0/4 | 0 → 0 |

Binding's six matching declaration lines are unchanged. Their proportions are
B 6/493 = 1.22% → 6/575 = 1.04%, and C 6/316 = 1.90% → 6/353 = 1.70%.
The other groups remain 0% in both literal and whole-file comparisons.
The lower binding percentages come from a larger denominator, not removed
duplicate lines. Host growth includes adapter and diagnostic work; these file
sets are not a complete current host footprint. New `FeedbackRuntime.swift`
and `CompactFeedbackRuntime.swift` are listed separately in evidence and are
not silently added to the original denominator.

Actual reuse is evidenced by shared contracts/scenario ownership and adopted
binding/connection/feedback decisions, not by matching host source text. The
unchanged 30-scenario, 78-step data set has 100% shared data reuse; executors and
device safety remain adapters. Scheduler extraction is still unadopted.

Reproducible workspace evidence: `build/j-finish/k/measure_duplication.py` and
`duplication.json` contain the exact full revisions, every compared path/blob
SHA-256, denominators and matching lines. The baseline is
`build/h-main/kit-inventory.json`. This static check does not rerun host traces.
