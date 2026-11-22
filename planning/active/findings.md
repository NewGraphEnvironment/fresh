# Findings: Backlog sweep (#315)

## Issue context

**If we do it:** the 52 open issues are grouped into a few moves by the files they edit and the cost they share, in `planning/backlog.md`. Each move gets an umbrella issue that one `/planning-init` plans and one PR lands. Closures are proposed only with a stated reason. **If we never do:** the queue stays a flat list ordered by filing date, and older issues whose premise the code has since overtaken stay open as spec.

## Scope

- Read every open issue's body and its comments, and check each older premise against `main`.
- Group them into batches and moves (`/backlog-sweep`), and rank the top three.
- Propose closures, each with its reason.
- Flagged research files: `research/fwa_waterbody_key_polygons.md` and `research/fwapg_channel_width.md` carry no `**Verified:**` date.

Nothing is written or closed before the owner's go on the report.


## Method

Three Explore agents digested 17 or 18 issues each: body, comments, premise against origin/main 1dcc7a3, the files a fix touches, and references. The main session probed every closure claim itself (`mirai_map` at R/frs_habitat.R:579, `db-local` in the org's database skill, tibble at DESCRIPTION:38, #255's roadmap task, #231's paragraph) before reporting.

## Errors Encountered

| Error | Resolution |
|-------|------------|
| `public_leak_scan` flagged soul#593 / soul#605 in a public file; the bare name "soul" is not scanned | Rewrote in words; grepped every tracked file and issue body this pass wrote for the bare name |
| My clash-ordering check matched no pair | `lanes` prints the second move as `2:`; strip the colon |
