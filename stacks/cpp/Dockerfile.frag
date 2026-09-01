# Installs GCC/G++ {{VERSION}} + CMake, GDB, and Make
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc-{{VERSION}} \
    g++-{{VERSION}} \
    cmake \
    gdb \
    make \
    && rm -rf /var/lib/apt/lists/* \
    && update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-{{VERSION}} 100 \
    && update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-{{VERSION}} 100

# Development headers for the things a graphical C++ program links against.
#
# The X11, Wayland, GL and EGL headers are already here, pulled in by the core
# stack's Tauri dependencies — these five are what is left, and each one is
# absent in a way that does not fail the build. SDL configured without them
# compiles, links, and produces a binary with the corresponding backend simply
# not in it. That is the failure this list exists to prevent: not a build error
# somebody fixes, but a program that runs and is silent, or that the screensaver
# covers, on every machine it will ever run on.
#
#   libasound2-dev    alsa/asoundlib.h            — no ALSA backend without it
#   libpulse-dev      pulse/pulseaudio.h          — no PulseAudio backend, which
#                                                   is what most desktops run
#   libudev-dev       libudev.h                   — no gamepad hotplug; a pad
#                                                   plugged in later is not seen
#   libxss-dev        X11/extensions/scrnsaver.h  — no SDL_DisableScreenSaver,
#                                                   so the screensaver covers a
#                                                   game played on a gamepad
#   libdecor-0-dev    libdecor-0/libdecor.h       — undecorated Wayland windows
#                                                   where the compositor draws
#                                                   no border itself
#
# Checked against SDL3 3.4.14's own cmake/sdlchecks.cmake rather than guessed.
# stacks/cpp/image.test.sh asserts each header is present in the built image,
# because `docker build` succeeding only proves apt-get ran.
RUN apt-get update && apt-get install -y --no-install-recommends \
    libasound2-dev \
    libpulse-dev \
    libudev-dev \
    libxss-dev \
    libdecor-0-dev \
    && rm -rf /var/lib/apt/lists/*

# C++ acceptance-test infrastructure. cucumber-cpp links against the three
# header-only libraries below and exposes step definitions over a TCP wire
# server. Ruby is the Gherkin runner on the other side of that connection.
RUN apt-get update && apt-get install -y --no-install-recommends \
    libasio-dev \
    nlohmann-json3-dev \
    libtclap-dev \
    ruby \
    ruby-dev \
    && rm -rf /var/lib/apt/lists/*

# cucumber-cpp v0.8.0 is a C++ wire server, not a Gherkin runner. Its own
# Gemfile pins Cucumber-Ruby and cucumber-wire to this compatible pair; newer
# Cucumber majors no longer speak the protocol it implements. Keep the runner
# in the image so a clean checkout can execute acceptance tests without a
# per-project gem install or network access at test time.
RUN gem install cucumber-wire --version 6.2.1 --no-document \
    && gem install cucumber --version 7.1.0 --no-document

# Installs the code-server extension for C/C++ (Open VSX — ms-vscode.cpptools
# isn't published there, clangd is the closest maintained equivalent)
RUN /app/code-server/bin/code-server \
    --extensions-dir /config/extensions \
    --user-data-dir /config/data \
    --install-extension llvm-vs-code-extensions.vscode-clangd || true
