#!/usr/bin/env bash
# What each dependency is called in each distribution's package manager.
#
# A file of its own so that `init` and the test beside it read the same table.
# The risk this carries is specific: `init` offers to install what this returns,
# so a wrong name installs the wrong thing on somebody's host, and an **absent**
# name is worse — the package silently drops out of the list, the install
# succeeds, and the dependency is still missing.
#
# The names are not derived from the command: `whiptail` comes from `newt` on
# Fedora and `libnewt` on Arch, `cc` from `build-essential`, `gcc` or
# `base-devel`, and the pkg-config names are their own thing again.

packages_for() {
    local manager="$1" want="$2"
    case "$manager:$want" in
        apt:jq|dnf:jq|pacman:jq) echo jq ;;
        apt:whiptail) echo whiptail ;;
        dnf:whiptail) echo newt ;;
        pacman:whiptail) echo libnewt ;;
        apt:docker) echo docker.io ;;
        dnf:docker|pacman:docker) echo docker ;;
        *) echo "" ;;
    esac
}
