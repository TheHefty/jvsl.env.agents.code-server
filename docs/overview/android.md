# The Android SDK and the emulator

Two findings that cost a day each, both about ownership and both invisible until the emulator
refused to start.

- **Google's SDK packages need a `chmod`, not a `chown`, to be usable by the runtime user.** The
  android stack used to end its install with `chown -R abc:abc $ANDROID_HOME`, which looks right and
  silently isn't: at build time `abc` is the base image's `911:1001`, but LinuxServer's init remaps
  `abc` to `PUID`/`PGID` when the container starts, orphaning that ownership. The runtime `abc` then
  falls into "other" — and Google ships most SDK binaries mode `744`, no group/other execute — so
  `emulator`, `adb`, `aapt2` and ~1900 other executables fail with `Permission denied` for the exact
  user meant to run them. (`cmdline-tools`' `avdmanager`/`sdkmanager` are `755`, so those kept
  working and masked it.) Replaced with `chmod -R a+rX $ANDROID_HOME`, which is independent of
  whatever `PUID` a host picks; nothing needs to *write* under `$ANDROID_HOME` at runtime now that
  the AVD lives under `/config`.
- **Seeding the runtime AVD is conditional on the image's AVD definition, not on the runtime copy
  merely being absent.** Because `/config` is a persistent named volume, a seed-once guard pins the
  AVD to whatever the *first* image to boot that volume produced, and every later rebuild is
  silently ignored — observed for real: a leftover `android-31` AVD against an `android-36`-only
  SDK, which the emulator refuses outright (`Broken AVD system path. Check your ANDROID_SDK_ROOT`).
  `30-android-avd-home.sh` therefore `cmp`s the golden `config.ini` against the runtime one and
  re-seeds on any difference. `config.ini` is the right comparison target: it carries the target API
  level and `image.sysdir` (exactly what goes stale), holds no absolute paths, and is left
  byte-identical by a full emulator boot — verified empirically — so an unchanged image keeps its
  emulator state (`hardware-qemu.ini`, `*.qcow2`, `snapshots/`) across ordinary container restarts.

