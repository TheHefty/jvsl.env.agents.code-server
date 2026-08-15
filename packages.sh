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
        apt:curl|dnf:curl|pacman:curl) echo curl ;;
        apt:wget|dnf:wget|pacman:wget) echo wget ;;
        apt:file|dnf:file|pacman:file) echo file ;;
        apt:pkg-config) echo pkg-config ;;
        dnf:pkg-config) echo pkgconf-pkg-config ;;
        pacman:pkg-config) echo pkgconf ;;
        apt:cc) echo build-essential ;;
        dnf:cc) echo gcc ;;
        pacman:cc) echo base-devel ;;
        apt:webkit2gtk-4.1) echo libwebkit2gtk-4.1-dev ;;
        dnf:webkit2gtk-4.1) echo webkit2gtk4.1-devel ;;
        pacman:webkit2gtk-4.1) echo webkit2gtk-4.1 ;;
        apt:libxdo) echo libxdo-dev ;;
        dnf:libxdo) echo libxdo-devel ;;
        pacman:libxdo) echo xdotool ;;
        apt:openssl) echo libssl-dev ;;
        dnf:openssl) echo openssl-devel ;;
        pacman:openssl) echo openssl ;;
        apt:librsvg-2.0) echo librsvg2-dev ;;
        dnf:librsvg-2.0) echo librsvg2-devel ;;
        pacman:librsvg-2.0) echo librsvg ;;
        apt:x11) echo libx11-dev ;;
        dnf:x11) echo libX11-devel ;;
        pacman:x11) echo libx11 ;;
        apt:gl) echo libgl1-mesa-dev ;;
        dnf:gl) echo mesa-libGL-devel ;;
        pacman:gl) echo mesa ;;
        apt:ayatana-appindicator3-0.1) echo libayatana-appindicator3-dev ;;
        dnf:ayatana-appindicator3-0.1) echo libappindicator-gtk3-devel ;;
        pacman:ayatana-appindicator3-0.1) echo libayatana-appindicator ;;
        *) echo "" ;;
    esac
}
