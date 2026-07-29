# Installs the Android SDK for platform (API level) {{VERSION}} — Android
# platform packages aren't apt packages, sdkmanager against Google's repo is
# the only way to get a specific platform/build-tools set. Requires the
# `java` stack (see requires.json): sdkmanager needs a JDK already on PATH,
# so this fragment doesn't install one of its own — it'd duplicate whatever
# JDK version was chosen for `java` and setup already enforces java being
# selected alongside android.
ENV ANDROID_HOME=/opt/android-sdk
ENV ANDROID_SDK_ROOT=$ANDROID_HOME
# AVDs live under $ANDROID_HOME (not the real $HOME's ~/.android/avd) so they
# land in the one tree the chown below already covers, and survive
# independently of whichever $HOME the emulator ends up invoked from.
# `emulator` reads ANDROID_AVD_HOME directly at lookup time; `avdmanager
# create avd` (verified empirically against this cmdline-tools build)
# ignores ANDROID_AVD_HOME/HOME on its own and needs an explicit `--path`
# pointed at an already-existing directory (the mkdir below) to put both the
# AVD's content directory and its .ini registry file there instead of
# defaulting to ~/.android/avd.
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
# to match). Without it the emulator still boots, just via much slower,
# fully-software CPU emulation.
RUN mkdir -p $ANDROID_HOME/cmdline-tools \
    && curl -fsSL https://dl.google.com/android/repository/commandlinetools-linux-15859902_latest.zip -o /tmp/cmdline-tools.zip \
    && unzip -q /tmp/cmdline-tools.zip -d $ANDROID_HOME/cmdline-tools \
    && mv $ANDROID_HOME/cmdline-tools/cmdline-tools $ANDROID_HOME/cmdline-tools/latest \
    && rm /tmp/cmdline-tools.zip \
    && yes | sdkmanager --licenses > /dev/null \
    && sdkmanager --install "platform-tools" "build-tools;36.0.0" "platforms;android-{{VERSION}}" "ndk;27.1.12297006" "emulator" "system-images;android-{{VERSION}};google_apis;x86_64" > /dev/null \
    && mkdir -p $ANDROID_AVD_HOME \
    && echo "no" | avdmanager create avd --name devcontainer --package "system-images;android-{{VERSION}};google_apis;x86_64" --path "$ANDROID_AVD_HOME/devcontainer.avd" --force \
    && chown -R abc:abc $ANDROID_HOME

# Installs the code-server extension for Kotlin (Open VSX) — Android's
# default language today; Java/Maven support already comes from the java
# stack this one requires
RUN /app/code-server/bin/code-server \
    --extensions-dir /config/extensions \
    --user-data-dir /config/data \
    --install-extension fwcd.kotlin || true
