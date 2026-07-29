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

# cmdline-tools build number is pinned (Google doesn't publish a stable
# "latest" URL) — bump this comment/URL together when a newer tools release
# is needed. build-tools/NDK versions are likewise fixed, independent of the
# platform API level selected above — bump these when a newer Android Gradle
# Plugin (which enforces its own build-tools floor, ignoring whatever a
# consuming project pins in its own build.gradle) or React Native template
# (which pins its own NDK revision) needs a newer one than what's here.
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
RUN mkdir -p $ANDROID_HOME/cmdline-tools \
    && curl -fsSL https://dl.google.com/android/repository/commandlinetools-linux-15859902_latest.zip -o /tmp/cmdline-tools.zip \
    && unzip -q /tmp/cmdline-tools.zip -d $ANDROID_HOME/cmdline-tools \
    && mv $ANDROID_HOME/cmdline-tools/cmdline-tools $ANDROID_HOME/cmdline-tools/latest \
    && rm /tmp/cmdline-tools.zip \
    && android sdk install "platform-tools" "build-tools;36.0.0" "platforms;android-{{VERSION}}" "ndk;27.1.12297006" "emulator" "system-images;android-{{VERSION}};google_apis;x86_64" \
    && mkdir -p $ANDROID_HOME/avd \
    && echo "no" | avdmanager create avd --name devcontainer --package "system-images;android-{{VERSION}};google_apis;x86_64" --path "$ANDROID_HOME/avd/devcontainer.avd" --force \
    && chown -R abc:abc $ANDROID_HOME

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
