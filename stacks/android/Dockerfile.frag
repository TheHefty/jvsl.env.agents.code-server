# Installs the Android SDK for platform (API level) {{VERSION}} — Android
# platform packages aren't apt packages, the `android` CLI against Google's
# repo is the only way to get a specific platform/build-tools set. Requires
# the `java` stack (see requires.json): it needs a JDK already on PATH, so
# this fragment doesn't install one of its own — it'd duplicate whatever JDK
# version was chosen for `java` and setup already enforces java being
# selected alongside android.
ENV ANDROID_HOME=/opt/android-sdk
ENV ANDROID_SDK_ROOT=$ANDROID_HOME
# Set to the golden copy's own location for the `avdmanager create avd` RUN
# step below, then overridden to the actual runtime location further down
# (see the comment there for why). Needed even though that step also passes
# an explicit `--path`: verified empirically that `--path` only controls
# where the AVD's *content* directory lands — the separate top-level
# `<name>.ini` registry file avdmanager also writes goes by
# ANDROID_AVD_HOME/HOME instead, defaulting to `$HOME/.android/avd` (root's,
# during the build) if this isn't set to match `--path` at RUN time.
ENV ANDROID_AVD_HOME=$ANDROID_HOME/avd
ENV PATH=$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/emulator:$ANDROID_HOME/platform-tools:$PATH

# The emulator needs libX11 even to run headless — `emulator` itself, both qemu
# binaries, and libgfxstream/libemugl/libandroid-emu-shared all carry
# libX11.so.6 as a hard DT_NEEDED, so its absence fails at load time rather
# than degrading to no-graphics. It does resolve in this image today, but only
# by accident: core's Tauri build dependencies (libwebkit2gtk-4.1-dev and
# friends, present to build `start`) drag the whole GTK/X11 stack in, and no
# fragment declares an X library for the emulator's sake anywhere. Trimming
# those -dev packages out of a runtime image — a perfectly reasonable cleanup —
# would therefore break the emulator with nothing recording why. Declaring it
# here puts the dependency where it actually belongs.
#
# libxkbfile1 is deliberately included on a weaker justification, worth stating
# so it isn't mistaken for a headless requirement: only the *windowed*
# qemu-system-x86_64 needs it, and transitively at that
# (libQt6WebEngineCoreAndroidEmu.so.6 -> libxkbfile.so.1) — the `-headless`
# variant this AVD is meant to run links no Qt WebEngine at all. Measured with
# LD_LIBRARY_PATH set the way the launcher sets it: the headless binary resolves
# in full, the windowed one is short exactly that one library. So this buys no
# capability (there's no display server here either way, see docs/OVERVIEW.md)
# — it buys a legible failure. Without it, forgetting `-no-window` dies on
# "libxkbfile.so.1: cannot open shared object file", which points at nothing a
# caller would connect to a missing flag; with it, the run gets far enough to
# fail on the missing display, which is the actual problem.
RUN apt-get update && apt-get install -y --no-install-recommends \
    libx11-6 \
    libxkbfile1 \
    && rm -rf /var/lib/apt/lists/*

# cmdline-tools build number is pinned (Google doesn't publish a stable
# "latest" URL) — bump this comment/URL together when a newer tools release
# is needed. build-tools/NDK versions are likewise fixed, independent of the
# platform API level selected above — bump these when a newer Android Gradle
# Plugin (which enforces its own build-tools floor, ignoring whatever a
# consuming project pins in its own build.gradle) or React Native template
# (which pins its own NDK revision) needs a newer one than what's here.
#
# `cmake` belongs alongside the NDK rather than being treated as optional:
# React Native drives its native build through CMake via the Android Gradle
# Plugin, so an image shipping the NDK alone still can't build an RN app —
# AGP tries to auto-install `cmake;3.22.1` mid-build and dies against the
# read-only SDK ("The SDK directory is not writable"). Unlike a build-tools
# mismatch, no consuming-project setting avoids this: the toolchain has to
# come from the SDK, so it's installed here.
#
# The emulator system image is x86_64 (not arm64): the realistic host for
# this template is a Linux machine with Intel/AMD hardware virtualization,
# which is also the only case `start` passes /dev/kvm through (see
# start/src/main.rs) — an arm64 image would only make sense targeting Apple
# Silicon hosts, which can't expose KVM into a Linux container the same way.
# `google_apis` (not `google_apis_playstore` or plain AOSP `default`): Google
# APIs without the Play Store bundle is the common baseline for app dev/test
# — smaller than the Play Store variant, and unlike plain AOSP still has
# Google Play services for any app that expects them.
#
# This devcontainer has no display server (see docs/OVERVIEW.md) — the AVD
# created below is only ever meant to run headless, e.g.:
#   emulator -avd devcontainer -no-window -no-audio -no-boot-anim -gpu swiftshader_indirect
# KVM hardware acceleration (the emulator's default, `-accel auto`) depends
# on the host exposing /dev/kvm, which `start` only passes through when
# present (core/cont-init/20-kvm-gid.sh aligns the in-container 'kvm' group
# to match). Without it the emulator does not boot at all for this x86_64
# image — verified empirically (see docs/OVERVIEW.md): recent emulator
# releases hard-require an accelerator for x86_64 guests, there's no
# TCG/software-CPU fallback left to fall back to. An arm64 system image
# would sidestep this on Apple Silicon hosts (which use their own native
# accelerator, not /dev/kvm), but isn't an option here — this template only
# targets Linux hosts.
#
# AVDs are created below under $ANDROID_HOME/avd, a "golden" copy baked into
# the image — not the actual runtime ANDROID_AVD_HOME (see the ENV override
# further down for why).
#
# The final `chmod -R a+rX` (rather than the `chown -R abc:abc` this used to
# end with) is what makes the SDK usable as the runtime user at all. A
# build-time `chown` to `abc` bakes in abc's *image* identity (911:1001),
# but LinuxServer's init remaps abc to PUID/PGID at container start — so the
# ownership ends up orphaned, abc falls into "other", and Google ships most
# of these binaries mode 744 (no group/other execute). Net effect was
# `emulator: Permission denied` for the very user meant to run it, across
# ~1900 executables (emulator, adb, aapt2, …); only cmdline-tools'
# `avdmanager`/`sdkmanager` are 755, which masked the problem. `a+rX`
# restores traversal/execution regardless of what PUID the host picks.
#
# Read+execute is deliberately all the runtime user gets: the AVD (the one
# thing that genuinely needs writing at runtime) lives under /config instead,
# see the ANDROID_AVD_HOME override below. A Gradle build *will* still try to
# write here if a project asks for an SDK component this image doesn't ship —
# it auto-installs missing ones, and fails with "The SDK directory is not
# writable" when it can't. That's the intended outcome, not a gap to paper
# over by loosening these permissions: a build that silently mutates the SDK
# is a build whose result depends on what a given machine happened to
# download. The fix belongs in the consuming project, pinning the versions
# it needs to what the image provides.
RUN mkdir -p $ANDROID_HOME/cmdline-tools \
    && curl -fsSL https://dl.google.com/android/repository/commandlinetools-linux-15859902_latest.zip -o /tmp/cmdline-tools.zip \
    && unzip -q /tmp/cmdline-tools.zip -d $ANDROID_HOME/cmdline-tools \
    && mv $ANDROID_HOME/cmdline-tools/cmdline-tools $ANDROID_HOME/cmdline-tools/latest \
    && rm /tmp/cmdline-tools.zip \
    && android sdk install "platform-tools" "build-tools;36.0.0" "platforms;android-{{VERSION}}" "ndk;27.1.12297006" "cmake;3.22.1" "emulator" "system-images;android-{{VERSION}};google_apis;x86_64" \
    && mkdir -p $ANDROID_HOME/avd \
    && echo "no" | avdmanager create avd --name devcontainer --package "system-images;android-{{VERSION}};google_apis;x86_64" --path "$ANDROID_HOME/avd/devcontainer.avd" --force \
    && chmod -R a+rX $ANDROID_HOME

# ANDROID_AVD_HOME (what `emulator` actually reads at lookup time) points at
# /config, not the golden copy above under $ANDROID_HOME — /config is the
# runtime named volume (see start/src/main.rs), writable regardless of
# ai-jail's sandboxing of the Claude Code agent's own shell, unlike
# $ANDROID_HOME (/opt/android-sdk): ai-jail (bwrap) mounts /opt read-only
# for the agent specifically (confirmed empirically — a human working
# directly in code-server's terminal doesn't hit this), which broke the
# emulator's own runtime writes (qemu-version.txt, snapshot state) under
# $ANDROID_HOME/avd. cont-init/30-android-avd-home.sh seeds /config/android-avd
# from the golden copy the first time a given volume boots, since anything
# baked directly under /config at build time would just be shadowed by the
# volume mount on first run.
ENV ANDROID_AVD_HOME=/config/android-avd

COPY stacks/android/cont-init/30-android-avd-home.sh /custom-cont-init.d/30-android-avd-home.sh
RUN chmod +x /custom-cont-init.d/30-android-avd-home.sh

# Installs the code-server extension for Kotlin (Open VSX) — Android's
# default language today; Java/Maven support already comes from the java
# stack this one requires
RUN /app/code-server/bin/code-server \
    --extensions-dir /config/extensions \
    --user-data-dir /config/data \
    --install-extension fwcd.kotlin || true
