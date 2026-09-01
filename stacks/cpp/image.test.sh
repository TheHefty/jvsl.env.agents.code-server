#!/usr/bin/env bash
# Runs INSIDE a built cpp-stack image. Asserts that the development headers the
# fragment installs are actually where a compiler will look for them.
#
# Why this exists at all: `docker build` succeeding proves `apt-get` ran. It does
# not prove a header is on the include path, and for this particular list the
# difference is invisible until much later and somewhere else. SDL configured
# without alsa/asoundlib.h does not fail — it compiles, links, and produces a
# binary with no audio backend in it, which is silent on every machine. A build
# that passes and a capability that exists are two different claims, and until
# this file the template could only make the first one.
#
# Run by .github/workflows/ci.yml's stack-build job, against the image it has
# just built. The convention is the filename: any stacks/<name>/image.test.sh is
# executed the same way, so a stack that needs to assert something about its own
# image has somewhere to put it.
set -uo pipefail

failures=0

# Each header, and what is lost when it is missing. The comment is the reason
# the package is in the fragment; keep the two lists together.
check_header() {
    local header="$1" consequence="$2"
    if [ -f "/usr/include/$header" ]; then
        echo "ok   $header"
    else
        echo "FAIL $header is missing — $consequence"
        failures=$((failures + 1))
    fi
}

check_header alsa/asoundlib.h           "SDL builds with no ALSA backend and is silent"
check_header pulse/pulseaudio.h         "SDL builds with no PulseAudio backend"
check_header libudev.h                  "no gamepad hotplug"
check_header X11/extensions/scrnsaver.h "no SDL_DisableScreenSaver; the screensaver covers the window"
check_header libdecor-0/libdecor.h      "undecorated Wayland windows"
check_header asio.hpp                    "Cucumber.cpp cannot configure its wire server"
check_header nlohmann/json.hpp           "Cucumber.cpp cannot encode the wire protocol"
check_header tclap/CmdLine.h             "Cucumber.cpp cannot build its command-line runner"

# The compiler and build tools the stack is nominally about. Cheap to assert
# here, and it catches an update-alternatives that silently stopped applying.
for tool in gcc g++ cmake make gdb pkg-config ruby cucumber; do
    if command -v "$tool" >/dev/null 2>&1; then
        echo "ok   $tool is on PATH"
    else
        echo "FAIL $tool is not on PATH"
        failures=$((failures + 1))
    fi
done

# cucumber-cpp v0.8.0 still speaks the legacy wire protocol. Its own Gemfile
# pins this exact pair, so checking only that a `cucumber` executable exists
# would allow a newer, incompatible major to turn every feature yellow before
# a C++ step definition is reached.
if command -v ruby >/dev/null 2>&1; then
    for gem_and_version in "cucumber 7.1.0" "cucumber-wire 6.2.1"; do
        read -r gem_name gem_version <<< "$gem_and_version"
        if ruby -e 'gem_name, gem_version = ARGV; Gem::Specification.find_by_name(gem_name, "= #{gem_version}")' \
            "$gem_name" "$gem_version"; then
            echo "ok   $gem_name $gem_version is installed"
        else
            echo "FAIL $gem_name $gem_version is missing — cucumber-cpp's wire runner is incompatible" >&2
            failures=$((failures + 1))
        fi
    done
fi

if [ "$failures" -ne 0 ]; then
    echo "$failures check(s) failed" >&2
    exit 1
fi
echo "all checks passed"
