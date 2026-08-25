#!/usr/bin/env bash
# The php stack is the only one that installs from a third-party archive, so it
# is the only one that carries a signing key. This checks the key beside it is
# the key the fragment says it is.
#
# Offline on purpose. The obvious version of this test downloads the PPA's
# InRelease and verifies it, which is how the key was derived in the first
# place — and which would put every CI run back at the mercy of a Launchpad
# outage, the exact failure the pin exists to remove. What is worth guarding
# here is drift between the three places the key appears: the file, the
# fingerprint written in the fragment, and the fragment still being wired to
# use it at all.
#
# To re-derive the key (after a rotation, or to check this by hand):
#   curl -fsSLO https://ppa.launchpadcontent.net/ondrej/php/ubuntu/dists/noble/InRelease
#   gpg --verify InRelease           # names the signing key ids
#   curl -fsS "https://keyserver.ubuntu.com/pks/lookup?op=get&options=mr&search=0x<FPR>" \
#     -o stacks/php/ondrej-php.asc
#   gpg --homedir "$(mktemp -d)" --import stacks/php/ondrej-php.asc && gpg ... --verify InRelease
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KEY="$HERE/ondrej-php.asc"
FRAG="$HERE/Dockerfile.frag"

# The key that signs https://ppa.launchpadcontent.net/ondrej/php/ubuntu, read
# off that archive's own InRelease on 2026-08-25.
EXPECTED_FPR="14AA40EC0831756756D7F66C4F4EA0AAE5267A6C"

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

# The point of the pin: no build-time call to Launchpad's API. add-apt-repository
# is what made that call, and it is an easy thing to reintroduce while fixing
# something else in this file.
check "the build does not reach for Launchpad's API" \
    "$(grep -v '^#' "$FRAG" | grep -c 'add-apt-repository' || true)" "0"

check "and the archive is trusted through this key alone" \
    "$(grep -c 'signed-by=/etc/apt/keyrings/ondrej-php.asc' "$FRAG")" "1"

# An expired key fails the build the day it expires, with an apt error that
# reads like a network problem. This one does not expire; if it is ever
# replaced by one that does, that is worth knowing before it happens.
expiry="$(gpg --homedir "$home" --show-keys --with-colons "$KEY" 2>/dev/null \
    | awk -F: '$1=="pub"{print $7; exit}')"
check "the pinned key has no expiry date to walk into" \
    "${expiry:-none}" "none"

exit "$failures"
