# Progress: Backlog sweep (#315)

## Session 2026-11-22

- Plan-mode exploration (the sweep's steps 0-4); report approved by the owner
- Created branch `315-backlog-sweep-batch-the-52-open-issues-i` off origin/main
- Scaffolded PWF baseline from issue #315 with approved phases
- Next: start Phase 1
- Filed research issues #316, #317 and umbrellas #318-#325 (moves 1-8); umbrella bodies scanned clean (`public_leak_scan`) before filing. The gate heading in the bodies reads "To decide at the gate", since those are questions for each move's plan
- Wrote `planning/backlog.md`: coverage 53 of 53; `lanes` showed clashes over `R/frs_habitat.R`, `R/frs_break.R`, `R/utils.R` and the overlay/classify files, so lane A runs moves 1, 2, 3, 5, 8 in order and lanes B, C, D (docs, parity, docker) are sequenced by `waits on`; every open move ticks cleanly on a copy; free now: #318, #321, #324
- Edited #231's "Shared mechanism" paragraph (two assignment sites, the in-group collision), then closed #64, #73, #243, #256, #295, #231, #232, #233, #235, #236, each with its reason; public scan of backlog.md clean
