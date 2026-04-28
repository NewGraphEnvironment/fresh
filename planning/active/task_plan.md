# Task: Enable startup quotes for fresh (frs)

Per `/quotes-enable` skill workflow. Per-package `inst/extdata/quotes.csv` + dependency-free `R/zzz.R` that prints a random quote on `library(frs)`.

## Inputs

### Artist tone calibration (user-curated, 25)

Travis Scott, Young Thug, Migos, Future, YoungBoy Never Broke Again, Yeat, Mike WiLL Made-It, Farruko, Bad Bunny, Mac Miller, Statik Selektah, Playboi Carti, Ty Dolla $ign, A$AP Rocky, Metro Boomin, 2 Chainz, Killer Mike, Rihanna, Florence + the Machine, M.I.A., Young Miko, Beyoncé, RZA, Danny Brown, Kodak Black.

### Domain layer (fresh = action on the river)

- **River writers / lyric reverence:** Norman Maclean, David James Duncan, Barry Lopez, Robert Macfarlane, Mary Oliver, Wendell Berry
- **Foundational ecology + restoration:** Aldo Leopold, Rachel Carson, John Muir, Eric Higgs, Robin Wall Kimmerer
- **Salmon + freshwater science:** Carl Walters, Tom Quinn, Jack Stanford, Daniel Pauly, Robert Naiman
- **Indigenous water + salmon voices:** Wet'suwet'en / Gitxsan / Haida leaders, Winona LaDuke, Indigenous Pacific salmon writers
- **Conservation + activism:** David Suzuki, Wade Davis, Yvon Chouinard, Bill McKibben

### Themes (broad)

art (music + all art forms — what art means to them), peace, justice, learning, connections, love.

## Phase 1: Calibration + targets confirmed

- [x] Artist list confirmed by user
- [x] Domain layer confirmed
- [x] Themes confirmed ("art" = broad: what art means to artists)

## Phase 2: Multi-agent quote research

- [x] Launch parallel WebSearch agents (15 total: 10 artist clusters + 5 domain buckets)
- [x] Each returns 5–10 candidates per artist with quote text + primary-source URL
- [x] Domain bucket research (one agent per bucket — Naiman empty, agent declined to fabricate)
- [x] Aggregate raw candidates into findings.md (~142 candidates total)

## Phase 3: Fact-check pass

- [x] Verify each quote against primary source (15 parallel fact-checker agents)
- [x] Drop any quote not verifiable to primary material — 3 mandatory drops (Walters paraphrase, Quavo Billboard reconstruction, Florence "Being put in boxes" misquote)
- [x] Record verified URL per quote (URL corrections for Mac Miller #4-5, Florence #4, Pauly #1, Killer Mike #4-6 → NPR canonical)

## Phase 4: Calibration filter

- [x] Cross-reference surviving quotes against fpr/rfp tone (intelligent, thought-provoking, not banal)
- [x] Drop or flag generic / motivational-poster quotes (5 calibration cuts: 2 Chainz x2, Statik #6, Tom Quinn, ASAP "Home...")

## Phase 5: User review

- [ ] Present surviving list with sources
- [ ] User vetoes individual entries

## Phase 6: Emit CSV + R/zzz.R

- [ ] Write `inst/extdata/quotes.csv` (UTF-8)
- [ ] Write `R/zzz.R` (dependency-free `.onAttach`)

## Phase 7: Verification

- [ ] `devtools::load_all()` then `library(frs)` — quote appears
- [ ] `R CMD check` — no new NOTE/WARN
- [ ] Preview 3 random draws

## Phase 8: PR

- [ ] Commit final state; ensure checkboxes match landed work
- [ ] Open PR via `/gh-pr-push`
