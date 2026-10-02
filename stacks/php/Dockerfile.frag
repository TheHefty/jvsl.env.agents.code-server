# Installs PHP {{VERSION}} + common extensions + Composer, from
# packages.sury.org/php — Ondřej Surý's own Debian/Ubuntu archive, the de facto
# standard for multi-version PHP.
#
# **It used to be the ondrej/php Launchpad PPA, and the path said `ubuntu`.** The
# codename was read from the base image on purpose, so a base bump could not
# silently 404 — but the distribution in the path was fixed, so moving the base
# to Debian would have 404'd anyway, on a dists path that exists for no Debian
# codename. sury serves `trixie`, `bookworm`, `noble` and `jammy`, with php8.0
# through 8.6 in each, so this archive follows the base wherever it goes.
#
# The repository is added by hand rather than with `add-apt-repository`, which
# fetches the signing key through a third party's *API* at build time. On
# 2026-08-25 Launchpad's answered HTTP 500 / GPGKeyTemporarilyNotFoundError for
# at least ten minutes and took every build of this stack down with it — while
# the archive itself was serving fine. Changing hosts does not retire that: the
# key is versioned beside this file, so a build needs only the archive.
#
# It is the key the archive itself names: `InRelease` is signed by
# 15058500A0235D97F5D10063B188E2B695BD4743, and the `apt.gpg` sury publishes
# carries exactly that fingerprint as its primary key — so the published key is
# the signing key, verified rather than trusted. Sending it straight to
# `signed-by` means apt trusts this archive with this key only. If it is ever
# rotated, apt refuses the archive loudly rather than installing anything: the
# fix is to re-derive the key from `InRelease`, not to drop the pin.
#
# **This key expires on 2028-02-04, and the PPA's did not.** The test beside this
# file pins the date so that the build walking into it is something written down
# rather than an apt error that reads like a network problem.
#
# sury-php.asc stays ASCII-armored — sury publishes the binary form — because apt
# reads an armored `signed-by` keyring directly, so nothing here needs gpg to
# dearmor it at build time.
COPY stacks/php/sury-php.asc /etc/apt/keyrings/sury-php.asc
RUN . /etc/os-release \
    && echo "deb [signed-by=/etc/apt/keyrings/sury-php.asc] https://packages.sury.org/php/ ${VERSION_CODENAME} main" \
       > /etc/apt/sources.list.d/sury-php.list \
    && apt-get update && apt-get install -y --no-install-recommends \
    php{{VERSION}} \
    php{{VERSION}}-cli \
    php{{VERSION}}-mbstring \
    php{{VERSION}}-xml \
    php{{VERSION}}-curl \
    composer \
    && update-alternatives --install /usr/bin/php php /usr/bin/php{{VERSION}} 100 \
    && rm -rf /var/lib/apt/lists/*
