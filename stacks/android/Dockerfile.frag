# Installs the Android SDK for platform (API level) {{VERSION}} — Android
# platform packages aren't apt packages, sdkmanager against Google's repo is
# the only way to get a specific platform/build-tools set. Requires the
# `java` stack (see requires.json): sdkmanager needs a JDK already on PATH,
# so this fragment doesn't install one of its own — it'd duplicate whatever
# JDK version was chosen for `java` and setup already enforces java being
# selected alongside android.
ENV ANDROID_HOME=/opt/android-sdk
ENV ANDROID_SDK_ROOT=$ANDROID_HOME
ENV PATH=$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH

# cmdline-tools build number is pinned (Google doesn't publish a stable
# "latest" URL) — bump this comment/URL together when a newer tools release
# is needed. build-tools/NDK versions are likewise fixed, independent of the
# platform API level selected above — bump these when a newer Android Gradle
# Plugin (which enforces its own build-tools floor, ignoring whatever a
# consuming project pins in its own build.gradle) or React Native template
# (which pins its own NDK revision) needs a newer one than what's here.
RUN mkdir -p $ANDROID_HOME/cmdline-tools \
    && curl -fsSL https://dl.google.com/android/repository/commandlinetools-linux-15859902_latest.zip -o /tmp/cmdline-tools.zip \
    && unzip -q /tmp/cmdline-tools.zip -d $ANDROID_HOME/cmdline-tools \
    && mv $ANDROID_HOME/cmdline-tools/cmdline-tools $ANDROID_HOME/cmdline-tools/latest \
    && rm /tmp/cmdline-tools.zip \
    && yes | sdkmanager --licenses > /dev/null \
    && sdkmanager --install "platform-tools" "build-tools;36.0.0" "platforms;android-{{VERSION}}" "ndk;27.1.12297006" > /dev/null \
    && chown -R abc:abc $ANDROID_HOME

# Installs the code-server extension for Kotlin (Open VSX) — Android's
# default language today; Java/Maven support already comes from the java
# stack this one requires
RUN /app/code-server/bin/code-server \
    --extensions-dir /config/extensions \
    --user-data-dir /config/data \
    --install-extension fwcd.kotlin || true
