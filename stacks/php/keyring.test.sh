#!/usr/bin/env bash
# The php stack is the only one that installs from a third-party archive, so it
# is the only one that carries a signing key. This checks the key beside it is
# the key the fragment says it is.
#
# Offline on purpose. The obvious version of this test downloads the archive's
# InRelease and verifies it, which is how the key was derived in the first
# place — and which would put every CI run back at the mercy of a third party's
# availability, the exact failure the pin exists to remove. What is worth guarding
# here is drift between the three places the key appears: the file, the
# fingerprint written in the fragment, and the fragment still being wired to
# use it at all.
#
# To re-derive the key (after a rotation, or to check this by hand):
#   curl -fsSLO https://packages.sury.org/php/dists/noble/InRelease
#   gpg --verify InRelease           # names the signing key id
#   curl -fsS https://packages.sury.org/php/apt.gpg -o apt.gpg
#   gpg --homedir "$(mktemp -d)" --import apt.gpg   # confirm the fpr matches
#   gpg --homedir "$(mktemp -d)" --armor --export <FPR> > stacks/php/sury-php.asc
#
# The published key is binary; the vendored one is armored, because apt reads an
# armored `signed-by` keyring directly and the build then needs no gpg.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KEY="$HERE/sury-php.asc"
FRAG="$HERE/Dockerfile.frag"

# The key that signs https://packages.sury.org/php, read off that archive's own
# InRelease on 2026-10-02 — `gpg --verify` names it, and the apt.gpg the project
# publishes carries it as its primary key, so the published key is the signing
# key rather than something taken on trust.
EXPECTED_FPR="15058500A0235D97F5D10063B188E2B695BD4743"

# **This key expires, and the previous one did not.** 2028-02-04 11:00 UTC. The
# assertion below used to read "the pinned key has no expiry date to walk into",
# with a comment saying that if it were ever replaced by one that expires, that
# would be worth knowing before it happens. It has been. So the expiry is pinned
# as a number instead: a rotation changes it and this says so, and the date is
# written down rather than arriving as an apt error that reads like a network
# problem.
EXPECTED_EXPIRY="1833274803"  # 2028-02-04

failures=0
check() {
    if [ "$2" = "$3" ]; then
        echo "ok   $1"
    else
        echo "FAIL $1"
        echo "     expected: $3"
        echo "     got:      $2"
        failures=$((failures + 1))
    fi
}

check "the signing key is versioned beside the fragment" \
    "$([ -f "$KEY" ] && echo present || echo absent)" "present"

home="$(mktemp -d)"
chmod 700 "$home"
trap 'rm -rf "$home"' EXIT

fprs="$(gpg --homedir "$home" --show-keys --with-colons "$KEY" 2>/dev/null \
    | awk -F: '$1=="fpr"{print $10}' | head -1)"
check "and it is the key the fragment names, not another one" \
    "$fprs" "$EXPECTED_FPR"

check "the fragment records that fingerprint, so the two cannot drift apart" \
    "$(grep -c "$EXPECTED_FPR" "$FRAG")" "1"

# The point of the pin: no build-time call to anybody's key API.
# add-apt-repository is what made that call, and it is an easy thing to
# reintroduce while fixing something else in this file. The host changed; the
# reason did not.
check "the build does not fetch the key at build time" \
    "$(grep -v '^#' "$FRAG" | grep -c 'add-apt-repository' || true)" "0"

check "and no stack fragment reaches for a Launchpad PPA any more" \
    "$(grep -v '^#' "$FRAG" | grep -c 'launchpad' || true)" "0"

check "and the archive is trusted through this key alone" \
    "$(grep -c 'signed-by=/etc/apt/keyrings/sury-php.asc' "$FRAG")" "1"

# An expired key fails the build the day it expires, with an apt error that
# reads like a network problem. This key does expire, which the one before it did
# not, so the date is pinned here: the build walking into 2028-02-04 is written
# down, and a rotation that moves it fails this assertion rather than surprising
# somebody.
expiry="$(gpg --homedir "$home" --show-keys --with-colons "$KEY" 2>/dev/null \
    | awk -F: '$1=="pub"{print $7; exit}')"
check "the pinned key's expiry is the one recorded here" \
    "${expiry:-none}" "$EXPECTED_EXPIRY"

check "and the fragment records that date, so nobody meets it as an apt error" \
    "$(grep -c '2028-02-04' "$FRAG")" "1"

exit "$failures"
