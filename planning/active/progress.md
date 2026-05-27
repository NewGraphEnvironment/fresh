# Progress — frs_wsg_drainage (#211)

## Session 2026-05-27

- Plan-mode exploration — phases approved by user
- Created branch `211-frs-wsg-drainage-fwa-wsg-drainage-closur` off main (off `90af475`)
- Scaffolded PWF baseline from issue #211 with approved phases (commit `1dc1145`)
- **Phase 1 complete:** `public.wsg_outlet` column confirmed as `wsg varchar(4)` (with `outlet ltree`, `lvl integer`); regression baseline run — PARS+BULK → 15 WSGs, exact match: `KISP, KLUM, LKEL, LSKE, MSKE, USKE, BULK, FINA, LBTN, LPCE, MORR, PARA, PCEA, UPCE, PARS` (DS-first, depths 1×6, 2×8, 3×1)
- Next: Phase 2 — write `R/frs_wsg_drainage.R`
