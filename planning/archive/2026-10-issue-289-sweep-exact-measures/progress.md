# Progress — point_snap_tie_sweep.R sends measures at 7 significant digits (#289)

## Session 2026-10-31

- Plan-mode exploration — phases approved by user
- Created branch `289-point-snap-tie-sweep-r-sends-measures-at` off origin/main
- Scaffolded PWF baseline from issue #289 with approved phases
- Next: start Phase 1
- Phase 1 (f6154e5): exact measures sent, read-back guard, exact CSV output
- Phase 2: head-case sample scripted; smoke run green (findings.md)
- Plan review landed (review-plan.md): B1, G1, G3, A2, A3 fixed in the script; smoke 2 green
- Phase 3: full sweep run and logs committed (findings.md, Full run)
- Phase 4: research note, gate-test comment revised; NEWS correction moved to PR body
- code-check round 1: premise corrected (11 decimals, not 7); sent_exact() now checks chunked()'s own text; issue #289 body + title edited
- code-check round 2: overclaims fixed (14-16 digits -> 12,260 moved by <= 5e-12 m, measured; 'every fresh code path'); task_plan frame and Phase 2 text match what was built; issue body re-edited
- code-check round 3: mechanism named, 56-claim enumeration; 5 fixed and re-measured; issue body re-edited
