# Consolidation and splitting

Use this branch when coordinated versions are required, remaining CI savings justify combining updates, or a diagnosed failure warrants splitting an approved batch. The parent skill's approval and merge gates apply to each resulting PR.

Compare the future cost of processing individuals with validating and merging a replacement. Already-completed runs are sunk cost. Keep unrelated ecosystems/major migrations separately assessable and preserve urgent security progress.

Prepare a concrete replacement in an isolated worktree. Record each constituent URL and head, intended manifest/resolved changes, shared base, compatibility repairs, replacement diff and expected remaining CI savings. Resolve overlapping lockfile changes with the relevant package manager; inspect transitive results for accidental scope expansion. Include the replacement and allowed split/repair fallbacks in the approval plan. Specifying one PR does not implicitly authorise adding other constituents.

After approval, publish the replacement with provenance links and a ledger mapping every intended update to its current PR. Keep originals open while it is pending, failing, unmerged or queued. Constituent green checks do not validate combined content: obtain independent applicable checks on the actual replacement head and compatible base, including fresh evidence after repairs or rebases.

Confirm the passing replacement actually merged before closing originals. Compare every original's live head/diff with the reviewed snapshot and merged content; close only fully superseded updates, with a comment linking the merged replacement. A bot revision may add an uncovered update: keep that original open and reassess it. Preserve unrelated and held work.

For splitting, diagnose first and construct compatible subsets from approved snapshots, keeping coupled versions together. Hold the failing update with its reason while approved independent subsets continue. Material scope changes need a new concrete proposal. Each subset needs its own applicable head/base evidence and confirmed merge before originals it fully supersedes are closed. Preserve partly uncovered originals, and close an obsolete combined PR only once all intended work is represented by subsets or preserved originals.
