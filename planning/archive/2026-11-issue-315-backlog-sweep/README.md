## Outcome

The 52 open issues were read in full, body and comments, by three digest agents. Each premise was checked against `origin/main` at 1dcc7a3 (v0.55.1), and the main session probed every closure claim itself. The result is a new `planning/backlog.md`: 8 moves carrying 9 batches (umbrellas #318-#325), 5 singles, and 5 issues on two cross-repo tracks. Two research re-verification issues were filed (#316, #317), and 10 issues were closed with their reasons: four done, one superseded, and five old topic umbrellas whose members are now placed. #231's misstated id_segment mechanism was corrected before it closed (#295). Three code-check rounds each found real defects: Touches lines written from each issue's headline function instead of every file the fix reaches, an upstream ping copied in from an issue title, and a lane note that an earlier fix made wrong. The loop ended on an enumeration of all 36 batch pairs.

## Measurement

- Coverage: 53 of 53 frozen open issues are named in the file (52 plus #315).
- Lanes: once the Touches lines were complete, 22 of the 36 batch pairs share an edited path; every one is ordered through `waits on`, with no cycle. Free at the end: #318 (move 1) and #324 (move 7).
- Before round 1's fix, `lanes` read moves 2/6, 3/6 and 1/4 as free to run together; round 2 found 4-6, 3-4 and 4-7 the same way. Each pair shares a file the Touches lines had missed.
- The first enumeration saw 0-2 paths for batches 4 and 8, because those issues name functions, not files. Resolving `frs_*()` to its defining file raised them to 8 and 1.

## Evidence

Review files in this directory: `review-round*.md`, `review-verdict.md`. The digests are summarised in `findings.md`.

Closed by: PR for branch `315-backlog-sweep-batch-the-52-open-issues-i` (Fixes #315)
