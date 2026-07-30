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
# libx11-xcb1 is the same accident with a different failure mode, and the
# measurement above is exactly why it was missed: it is not a DT_NEEDED of
# anything in the SDK. The gfxstream backend dlopen()s it by name at startup
# (libgfxstream_backend.so is the only binary in the tree that so much as
# mentions the string), so `readelf -d` over every emulator binary — which is
# what produced the libx11-6 line above — reports nothing at all. It is fatal
# regardless, and fatal *headlessly*, which is what makes it worth declaring
# rather than filing under "windowed only" the way libxkbfile1 below is: with
# it absent the launcher logs
#   SharedLibrary::open for [libX11-xcb]
#   Could not open libX11-xcb.so.1, give up
# and the emulator process dies right there, before the guest starts, leaving
# whatever waits on it (`adb wait-for-device`) to hang until it times out
# rather than fail. The SDK does ship its own copy at
# emulator/lib64/qt/lib/libX11-xcb.so.1, but a headless run never puts that Qt
# directory on the loader path, so it does not help. Measured 2026-07-30
# against a bare image carrying exactly the two packages this RUN used to
# install: the boot dies at that line; adding libx11-xcb1 and changing nothing
# else, the same AVD reaches boot_completed=1.
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
    libx11-xcb1 \
    libxkbfile1 \
    && rm -rf /var/lib/apt/lists/*

# cmdline-tools build number is pinned (Google doesn't publish a stable
# "latest" URL) — bump this comment/URL together when a newer tools release
# is needed.
#
# Fetched in its own RUN, separate from the SDK install below, for one
# reason: the two fail independently and the second one is expensive. This
# download is ~175MB; the install below is several GB (the system image and
# NDK dominate), so folding them into one layer means any hiccup in either
# re-runs both.
#
# The retry flags aren't decoration — this exact line has already killed a
# real build with `curl: (28) Failed to connect to dl.google.com port 443
# after 134079 ms`, i.e. a transient connect failure that bare `-fsSL` turns
# into a dead build several minutes in. Each flag covers a distinct half of
# that:
#   --connect-timeout 15  is what makes --retry useful at all. curl's default
#                         connect timeout is ~2min (the 134s above), so
#                         without it the retries mostly wait rather than
#                         retry.
#   --speed-limit/-time   catches the other failure mode --retry can't see: a
#                         connection that opens and then stalls mid-transfer.
#                         curl only retries what it considers a failure, and a
#                         transfer moving at 0 B/s forever is not one. Abort
#                         below 1KB/s for 30s, then let --retry do its job.
# Deliberately *not* `--max-time`: a hard ceiling can't distinguish a stalled
# transfer from an honestly slow link, so it would fail the very networks
# this hardening exists for. --no-progress-meter rather than -s so retry
# warnings still reach the build log — the next failure should be diagnosable
# from the log alone.
RUN mkdir -p $ANDROID_HOME/cmdline-tools \
    && curl -fL --no-progress-meter --proto '=https' --tlsv1.2 \
         --retry 5 --retry-all-errors --retry-delay 5 \
         --connect-timeout 15 --speed-limit 1024 --speed-time 30 \
         https://dl.google.com/android/repository/commandlinetools-linux-15859902_latest.zip \
         -o /tmp/cmdline-tools.zip \
    && unzip -q /tmp/cmdline-tools.zip -d $ANDROID_HOME/cmdline-tools \
    && mv $ANDROID_HOME/cmdline-tools/cmdline-tools $ANDROID_HOME/cmdline-tools/latest \
    && rm /tmp/cmdline-tools.zip

# build-tools/NDK versions are fixed, independent of the platform API level
# selected above — bump these when a newer Android Gradle Plugin (which
# enforces its own build-tools floor, ignoring whatever a consuming project
# pins in its own build.gradle) or React Native template (which pins its own
# NDK revision) needs a newer one than what's here.
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
# The `chmod -R a+rX` each install applies (rather than the `chown -R abc:abc`
# this used to end with) is what makes the SDK usable as the runtime user at
# all — it lives in stacks/android/sdk-install.sh now, scoped per package
# rather than run once over the whole tree, see the note there for why. A
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
#
# The SDK is installed one package per RUN, not all seven in one, and that is
# a deliberate trade of image layers for build resumability.
#
# The failure this addresses is real and was measured rather than imagined:
# connects to dl.google.com from here succeed about 80% of the time, while
# other hosts (registry.npmjs.org, storage.googleapis.com) sit at 100% — so
# there is genuine, hostname-correlated loss upstream of this container that
# nothing in the image can configure away. Against that, one atomic install of
# ~5GB has to win every coin flip in a row or discard everything it downloaded,
# which is how a full day of rebuilds can produce nothing. Split per package,
# Docker's own layer cache makes progress permanent: a build that dies on the
# NDK re-uses the layers for every package before it, and the rebuild resumes
# at the failure. Each RUN also carries its own retry loop (see
# stacks/android/sdk-install.sh).
#
# Packages are ordered smallest-first for the same reason. The largest ones are
# the likeliest to be interrupted, so putting them last means an interruption
# preserves the most already-cached work.
#
# `sdkmanager` rather than the newer `android sdk install`, despite the latter
# being the non-deprecated path: the `android` CLI is a launcher that fetches a
# ~229MB bundle of its own on first use, from that same flaky host, with no
# retry of its own and nothing this Dockerfile can wrap around it — the one
# download in the whole stack that could not be hardened. sdkmanager is a plain
# Java tool already present in cmdline-tools and needs no bundle at all.
# Verified here: it installs against a clean SDK root with HOME empty.
COPY stacks/android/sdk-install.sh /usr/local/bin/sdk-install
RUN chmod +x /usr/local/bin/sdk-install

RUN sdk-install "platform-tools" "platform-tools"
RUN sdk-install "build-tools;36.0.0" "build-tools"
RUN sdk-install "cmake;3.22.1" "cmake"
RUN sdk-install "platforms;android-{{VERSION}}" "platforms"
RUN sdk-install "emulator" "emulator"
# The system image gets a higher ceiling than the shared default, set here
# rather than in sdk-install.sh so raising it doesn't invalidate the package
# layers above. It has earned it twice: 9 attempts to land when this package
# set was populated by hand, and a real build lost at "attempt 5/5" after 2219
# seconds. Attempts are only spent on failure, so a package that installs
# first try costs nothing extra for the headroom.
RUN SDK_INSTALL_ATTEMPTS=40 sdk-install "system-images;android-{{VERSION}};google_apis;x86_64" "system-images"

# AVD creation is local work — no network, nothing to retry — and gets its own
# layer only because it has to follow the system image above. It writes just
# $ANDROID_HOME/avd, so the chmod here is scoped to that plus the licence
# acknowledgements sdkmanager records, rather than re-walking the whole SDK
# (which would duplicate the entire tree into this layer).
#
# Placed before the NDK rather than after all seven packages for cache
# ordering alone: the AVD needs only the system image, so running it here
# means an exhausted NDK download leaves a cached AVD layer behind instead of
# forcing it to be recreated on the next attempt.
#
# It is deliberately *not* justified by scan cost, though an earlier version
# of this comment claimed it was. `avdmanager` does walk the SDK tree with
# stat() before writing anything (LocalRepoLoaderImpl.collectPackages), and it
# was once observed taking upwards of 45 minutes of straight CPU — but nothing
# about that reproduces. It was blamed on the fuse-overlayfs named volume it
# ran against; re-running this exact command against that same volume on
# 2026-07-30 completed in **one second**, so the volume is not the cause
# either. Hiding the NDK from the walk had already changed nothing (still
# running after 14 minutes with the NDK absent), and the tree is small anyway
# (23,619 files, 8,676 of them the NDK's, 36 symlinks, no loops), so file count
# never explained it. The cause remains unestablished; what is established is
# that neither a normal image build nor a volume-backed SDK reproduces it.
RUN set -eu; \
    mkdir -p $ANDROID_HOME/avd; \
    echo "no" | avdmanager create avd --name devcontainer \
      --package "system-images;android-{{VERSION}};google_apis;x86_64" \
      --path "$ANDROID_HOME/avd/devcontainer.avd" --force; \
    chmod -R a+rX $ANDROID_HOME/avd $ANDROID_HOME/licenses

RUN sdk-install "ndk;27.1.12297006" "ndk"

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
