# Versioning and releases

- **release-please, driven by the commit history.** Tags and GitHub releases come from
  `.github/workflows/release-please.yml`: it keeps a release PR open with the next version and the
  accumulated changelog, and cuts the tag when that PR is merged. The history was already written
  in conventional commits from the first commit, so nothing had to change about how commits are
  written — the changelog is derived from what was already there. Chosen over tagging by hand
  because of how this repo is consumed: a monorepo vendors it as a submodule and pins a commit, and
  pinning a tag instead is only an improvement if the tag reliably exists and carries notes.
- **`release-type: simple`** — this isn't a package on any registry (no root crate, no
  `package.json`), so the strategy that only maintains `version.txt` + `CHANGELOG.md` and tags is
  the one that fits. `.release-please-manifest.json` is the version's source of truth.
- **There is no `extra-file` any more, and there was one.** The launcher's `tauri.conf.json` carried the
  template's version through a `jsonpath`, so the launcher was versioned in lockstep rather than on
  its own. The launcher is gone, and the entry went with it — left behind it would have failed at
  release time, pointing at a path that no longer exists, which is the worst moment for a
  configuration error to surface. `version.txt` and `CHANGELOG.md` are now the only versioned
  artifacts, which is what `release-type: simple` means with nothing added to it.
- **With merge commits, the release is decided by the *last* commit on the branch — not by any of
  the others.** Measured on 2026-10-01, when a `feat!` carrying a `BREAKING CHANGE:` footer produced
  no major bump and no changelog entry at all.

  What the action's log says, for every merge commit this repository makes:

  ```
  ❯ Fetching merge commits on branch main
  ❯ commit could not be parsed: 85c07a9 Merge pull request #82 from TheHefty/feat/...
  ```

  A merge commit's own subject is never conventional, so none of them parse. What release-please
  reads instead is the merge commit's **second parent**, which is the tip of the branch — and nothing
  behind it. Three merges on the same day, same shape, three outcomes:

  | pull request | last commit on the branch | result |
  |---|---|---|
  | #80 | `feat!: delete the launcher …` | seen — `3.0.0` with `BREAKING CHANGES` |
  | #82 | `docs: the task record names the pull request …` | **invisible** — the `feat!` behind it never read |
  | #83 | `fix: the split carried two launcher references …` | seen — `3.0.1` |

  The commit that buried #82's breaking change was a `docs:` fixing a pull request number. **So the
  rule is: the commit that should appear in the changelog has to be the branch's last commit.** A
  tidy-up commit pushed after it hides it, silently, and the only symptom is a version number that
  looks one release too small.

  The alternative is squash merging, where the message is the pull request's and there is only one.
  That is a bigger change to how this repository works and has not been made; until it is, this is a
  discipline rather than a mechanism, which means it will be forgotten at least once more.

  **This also makes the rule about non-conventional pull request titles narrower than it reads.**
  Giving a feature pull request a non-conventional title avoids a duplicated changelog entry, which
  is real — but it only works because the entry comes from the branch commit. It does nothing to
  protect a branch whose last commit is a `chore` or a `docs`.

- **The first tag is `1.0.0`, forced with a `Release-As: 1.0.0` footer** on the commit that added
  the workflow. Left alone the first release PR would have proposed `0.1.0`: the seeded manifest is
  `0.0.0` and the history is all `feat`/`fix`, which never produces a major on its own. The
  template had been in real use across projects well before this point, so naming the first tag
  `1.0.0` describes its actual state rather than what the commit history could infer.
- **Runs under a PAT, not the default `GITHUB_TOKEN`** — the `RELEASE_PLEASE_TOKEN` secret, needing
  Contents and Pull requests (read/write) on this repo only. The reason is the next point. Two
  consequences worth keeping in mind: the repo setting "Allow GitHub Actions to create and approve
  pull requests" no longer matters here, because the PR does not come from Actions; and the token
  expires, at which point releases silently stop being proposed until it is rotated. Going back to
  the `GITHUB_TOKEN` means deleting the `token:` line, not just the secret: the action's default is
  `${{ github.token }}`, but a default only applies to an *omitted* input, and a deleted secret
  leaves `token:` present and empty.
- **`main` is protected**, which is also why the repo is public — branch protection is a paid
  feature on private repos. Every change lands through a pull request; no approvals are required
  (single maintainer) but the rule applies to administrators too, and force-pushes and branch
  deletion are blocked. The one required check is `ci-green`: the per-stack jobs are a matrix built
  from `ls stacks`, so their names change whenever a stack is added or removed, and a required check
  that stops reporting blocks every merge forever. "Require branches to be up to date before
  merging" is deliberately **off** — see the next point for why turning it on would deadlock every
  release.
- **Why the PAT: a `GITHUB_TOKEN` release PR can never satisfy a required check.** Workflows are not
  triggered by events that the `GITHUB_TOKEN` causes, so the PR release-please opened got no CI run
  at all — `ci-green` never reported, and a required check that never reports leaves the PR
  `BLOCKED` with zero failures to look at. Closing and reopening the PR from a normal account is
  the manual way out, since the `reopened` event then comes from a user; that is what 1.0.2 needed,
  twice, before the PAT replaced it. Two related traps sit next to
  this one: a `pull_request` run uses the workflow file **from the head branch**, not from the
  merge commit, so a check added to `main` after the release branch was cut will never appear on
  that PR (the branch has to be recreated: close the PR, delete the branch, re-run the workflow);
  and release-please compares release *notes*, not files, so a `chore`/`ci`/`docs` commit landing
  on `main` leaves the existing release branch untouched (`PR remained the same` in the log). That
  is harmless unless the stale branch and `main` changed the same lines, which is exactly how the
  1.0.2 release PR ended up carrying a `Cargo.toml` bump that no longer belonged in it.
