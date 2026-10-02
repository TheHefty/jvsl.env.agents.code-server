#!/usr/bin/env bash
# Runs INSIDE a built php-stack image. Asserts that the PHP the manifest asked
# for is the PHP that answers, and that composer answers at all.
#
# Why this exists at all: `docker build` succeeding proves `apt-get install`
# exited zero. It does not prove **which** PHP arrived. The fragment ends with
# `update-alternatives --install /usr/bin/php php /usr/bin/php{{VERSION}} 100`,
# so `php -v` answers confidently whatever was installed — a version other than
# the requested one is a silent pass, and the archive this stack reads from
# changed hosts in the same breath as this file was added.
#
# `composer` is the one package in the fragment that does **not** come from
# sury: it is the distribution's own. So the measurement that said sury carries
# php8.0 through 8.6 on both distributions says nothing about it, which is
# exactly why it is asserted here.
#
# Run by .github/workflows/ci.yml's stack-build job, against the image it has
# just built, with this directory mounted read-only at /image-test.
set -uo pipefail

failures=0

check() {
    if [ "$2" = "$3" ]; then
        echo "ok   $1 ($2)"
    else
        echo "FAIL $1"
        echo "     expected: $3"
        echo "     got:      $2"
        failures=$((failures + 1))
    fi
}

# The version the composer defaults to when no manifest names one — the first
# entry of versions.json — which is what CI builds. Read from the file rather
# than hardcoded, so adding a version to the list cannot make this assert about
# a version nobody builds.
WANT="$(sed -n 's/.*\[[[:space:]]*"\([0-9.]*\)".*/\1/p' /image-test/versions.json)"
if [ -z "$WANT" ]; then
    echo "FAIL could not read the first version out of /image-test/versions.json"
    exit 1
fi
echo "ok   versions.json's first entry is $WANT"

# `php -v`'s first line is "PHP 8.2.29 (cli) ...". The major.minor is what the
# manifest selects; the patch is the archive's business.
got="$(php -v 2>/dev/null | sed -n '1s/^PHP \([0-9]*\.[0-9]*\).*/\1/p')"
check "the PHP that answers is the one the manifest asked for" "${got:-none}" "$WANT"

# Installed as `php{{VERSION}}` and reachable as `php` only because of
# update-alternatives. Both are asserted: the alternative being unset is a
# different failure from the package being absent, and they read the same from
# outside.
direct="$(command -v "php$WANT" >/dev/null 2>&1 && echo present || echo absent)"
check "it is installed under its versioned name too" "$direct" "present"

composer="$(composer --version 2>/dev/null | grep -c '^Composer' || true)"
check "composer answers" "$composer" "1"

# The extensions the fragment names, each because something needs it. A missing
# one is not a build failure: PHP starts fine and the first script that uses it
# dies at runtime.
for ext in mbstring xml curl; do
    have="$(php -m 2>/dev/null | grep -icx "$ext" || true)"
    check "the $ext extension is loaded" "$have" "1"
done

echo
echo "php/image.test: $failures failure(s)."
exit "$failures"
