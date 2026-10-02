# The agent in the terminal

Two findings about the integrated terminal, and they are the reason two editor defaults in this
image used to look arbitrary. Both defaults are gone — the image stopped shipping editor settings
when code-server left it — and the findings are kept, because a symptom somebody can meet is worth
being able to recognise rather than rediscover.

It had a file of its own because `setup.md` and a boot hook's test both referenced it by name. The
hook is gone; the reason for the separate file is now simply that it is about the terminal and
nothing else.

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
    free: every selection in every terminal replaces the system clipboard, so selecting a line of
    output merely to read it costs whatever was on the clipboard before. That is the long-standing
    X11/tmux convention and this environment is one where copying agent output is a constant, which
    is why it was the image's default — **it no longer is.** The image stopped shipping editor
    settings when code-server left it, so `"terminal.integrated.copyOnSelection": true` is now
    yours to set if you want the trade.
  - **The other lever, deliberately not pulled: `CLAUDE_CODE_DISABLE_MOUSE=1`.** The CLI reads it
    (it is in the binary's env table alongside `CLAUDE_CODE_DISABLE_MOUSE_CLICKS` and
    `CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN`), and setting it restores plain drag-select by turning
    the tracking off at the source. It is not baked into the image because it pays for that by
    removing whatever the CLI uses the mouse for, for everyone, to fix a selection gesture that
    Shift already fixes. Export it in your own shell if you would rather have the trade.
  - **It used to be tested**, in `core/cont-init/30-editor-defaults.test.sh`: that the key was
    really in the shipped defaults, that an environment whose volume predated it received it anyway,
    and that turning it off survived a restart. There is nothing left to test — the image ships no
    editor setting that is not tied to an extension it installs — and the tests went with the
    machinery.

- **The terminal renderer and dead-key composition, which the image used to work around.** With GPU
  acceleration on, the canvas renderer's async redraw races with dead-key/IME composition: typing an
  accented vowel through a compose sequence can replay part of the composition buffer into the
  terminal, so what arrives is not what was typed. The image used to ship
  `"terminal.integrated.gpuAcceleration": "off"` for it, measured at the time against code-server's
  web build.

  **It does not any more, and whether the race exists in the desktop build is not recorded
  anywhere.** It was not measured when the setting was removed, because the rule removed it either
  way — a setting reaches the image's label only if something the label installs needs it, and this
  one needs nothing. The description is kept here for the reason the setting is not: whoever meets
  the symptom should be able to recognise it rather than rediscover it, and
  `"terminal.integrated.gpuAcceleration": "off"` in their own settings is the fix.

**Confirmed end-to-end** at the time, against the bundled launcher that brought the container up and
opened a window onto code-server. That launcher is gone; the finding is kept because the editor
default it explains is still shipped.
