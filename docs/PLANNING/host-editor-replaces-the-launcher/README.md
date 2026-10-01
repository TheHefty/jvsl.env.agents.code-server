# Epic: the host editor replaces the launcher

**Opening a project in the host's editor becomes how the work is done, and `start` is retired.**

This repository has no SRS of its own, deliberately: it is a product already at 2.0.0, and writing
charter and SRS retroactively would describe what was long since decided rather than design
anything. The chain starts here, at the epic, for work that is new.

The epic itself is owned by the extension's SRS, in
[`jvsl.env.agents.vscode`](https://github.com/TheHefty/jvsl.env.agents.vscode) — `docs/SRS.md`
there carries the ordered list of all five stories, the requirements they deliver, and the spike
results they were grilled against. That document is the source of truth for the decomposition;
this folder holds the stories whose pull requests land **here**.

Why the split: the editor moves to the host, but half of what the first release needs is a change
to this image — the user's login shell, the metadata a dev container client reads, idempotent
ownership repair, a `.vscode/` the sandbox cannot write. Those are verified by this repository's
CI, which is the only one that builds images.

## Stories in this repository

| # | Story | Status |
|---|---|---|
| 1 | [`opening-a-configured-project`](opening-a-configured-project/) | **Done** — template `v2.1.0`, `v2.2.0`; extension `v0.1.0`, `v0.2.0`, `v0.2.1` |
| 3 | [`host-secrets-stay-on-the-host`](host-secrets-stay-on-the-host/) | Draft |
| 4 | the remote editor arrives equipped | not yet grilled |
| 5 | the launcher announces its retirement | not yet grilled |

Story 2 — refusing what cannot be opened — is the extension's, and lives in that repository.

The epic closes when opening through the extension is the normal path and `start` says where to
migrate. Removal of `start` in the following major is a scheduled consequence, not outstanding
work.
