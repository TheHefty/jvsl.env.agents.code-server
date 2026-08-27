# `.githooks/pre-push`

- **Everything CI checks that does not need a Docker build**: shell syntax, the host package table,
  the editor-defaults merge, the injected title bar, and `cargo test --release --locked`. Enabled
  per clone with `git config core.hooksPath .githooks`, because git config is not versioned.
- **What is left out is the point.** `core-build` and `stack-build` build images and take minutes,
  and a hook that takes minutes is a hook people skip with `--no-verify` — at which point it checks
  nothing at all. CI runs those and cannot be skipped.
- **It refuses a push straight to `main`**, before running anything. This is **not** branch
  protection and must not be read as one: nothing on the server refuses it, a fresh clone does not
  have the hook, `--no-verify` skips it, and the web UI, the API, `gh` and Actions never run it.
  What it buys is catching a slip, which is the failure that actually happens — merging with
  `--delete-branch` puts the checkout back on `main`, which is where the next piece of work then
  lands. The ref is checked rather than the sha, so a force-push and a deletion are refused too.

