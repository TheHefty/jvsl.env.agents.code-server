# The agent in the terminal

One finding, and it is the reason an editor default in this image looks arbitrary. Referenced by
name from `setup.md` and from `core/cont-init/30-editor-defaults.test.sh`, which is why it has a
file of its own rather than a paragraph in somebody else's.

- **Selecting text inside Claude Code does nothing, and it is not the clipboard.** Reported as
  "I can't copy Claude's prompt": dragging the mouse over the CLI's output in the integrated
  terminal highlights nothing at all, while the same drag works in a plain shell one line above it.
  The same shape as the accented-characters bullet above — it works fine *outside* Claude Code's
  prompt — and the same trap, because the obvious theory is the WebView's clipboard and the obvious
  theory is wrong. `enable_clipboard_access()` was already on the window and the injected title bar
  does not touch the keyboard; neither was involved.
  - What it actually is: the CLI turns on **mouse tracking**. `grep -a -F -- '[?1000h'` and
    `'[?1006h'` over `/usr/lib/node_modules/@anthropic-ai/claude-code/bin/claude.exe` both hit —
    normal button tracking plus SGR extended coordinates. xterm.js, which is the terminal
    code-server draws, hands mouse events to the application when the application asks for them and
    disables its own selection layer while that is true. Its one escape is
    `SelectionService._shouldForceSelection()`, and off macOS that is exactly "is Shift held".
  - So **Shift+drag selects** and `Ctrl+Shift+C` copies. That is the whole fix, and it is folklore
    — nothing in the editor, the terminal or the CLI says it anywhere, which is why this is written
    down here rather than left to be rediscovered.
  - `"terminal.integrated.copyOnSelection": true` is now a default, so Shift+drag *is* the copy and
    there is no second keystroke to know about. It is the smaller half of the fix and it is not
    free: every selection in every terminal now replaces the system clipboard, so selecting a line
    of output merely to read it costs whatever was on the clipboard before. That is the long-
    standing X11/tmux convention and this environment is one where copying agent output is a
    constant, which is why it is the default — but it is a behaviour change, not a bug fix, and
    `"terminal.integrated.copyOnSelection": false` set once stays set (the boot merge only ever
    adds absent keys; see "Default editor settings" in [`setup.md`](setup.md)).
  - **The other lever, deliberately not pulled: `CLAUDE_CODE_DISABLE_MOUSE=1`.** The CLI reads it
    (it is in the binary's env table alongside `CLAUDE_CODE_DISABLE_MOUSE_CLICKS` and
    `CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN`), and setting it restores plain drag-select by turning
    the tracking off at the source. It is not baked into the image because it pays for that by
    removing whatever the CLI uses the mouse for, for everyone, to fix a selection gesture that
    Shift already fixes. Export it in your own shell if you would rather have the trade.
  - Tested in `core/cont-init/30-editor-defaults.test.sh`: that the key is really in the shipped
    defaults (a documented default missing from the file reaches nobody), that an environment whose
    volume predates it receives it anyway, and that turning it off survives a restart — the last
    one verified by inverting the merge and watching it go red.

**Confirmed end-to-end** at the time, against the bundled launcher that brought the container up and
opened a window onto code-server. That launcher is gone; the finding is kept because the editor
default it explains is still shipped.
