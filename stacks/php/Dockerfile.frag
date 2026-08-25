# Installs PHP {{VERSION}} + common extensions + Composer (ondrej/php PPA —
# the de facto standard for multi-version PHP on Ubuntu/Debian)
#
# The PPA is added by hand rather than with `add-apt-repository`, which fetches
# the signing key through Launchpad's *API* at build time. On 2026-08-25 that
# API answered HTTP 500 / GPGKeyTemporarilyNotFoundError for at least ten
# minutes and took every build of this stack down with it — while the archive
# itself was serving fine — so this was the one stack whose build depended on a
# third-party web service being up, against the pin-and-verify convention the
# rest of the image already follows. The key is versioned beside this file, so
# a build now needs only the archive.
#
# It is the key the archive itself names: `InRelease` is signed by
# 14AA40EC0831756756D7F66C4F4EA0AAE5267A6C ("Launchpad PPA for Ondřej Surý"),
# and the file below is that key, checked to verify that signature. Sending it
# straight to `signed-by` means apt trusts this archive with this key only —
# not, as `apt-key` once did, everything with everything. If Launchpad ever
# rotates it, apt refuses the archive loudly rather than installing anything:
# the fix is to re-derive the key from `InRelease`, not to drop the pin.
#
# ondrej-php.asc stays ASCII-armored: apt reads an armored `signed-by` keyring
# directly, so nothing here needs gpg installed to dearmor it at build time.
COPY stacks/php/ondrej-php.asc /etc/apt/keyrings/ondrej-php.asc
RUN . /etc/os-release \
    && echo "deb [signed-by=/etc/apt/keyrings/ondrej-php.asc] https://ppa.launchpadcontent.net/ondrej/php/ubuntu ${VERSION_CODENAME} main" \
       > /etc/apt/sources.list.d/ondrej-php.list \
    && apt-get update && apt-get install -y --no-install-recommends \
    php{{VERSION}} \
    php{{VERSION}}-cli \
    php{{VERSION}}-mbstring \
    php{{VERSION}}-xml \
    php{{VERSION}}-curl \
    composer \
    && update-alternatives --install /usr/bin/php php /usr/bin/php{{VERSION}} 100 \
    && rm -rf /var/lib/apt/lists/*

# Installs the code-server extension for PHP (Open VSX)
RUN /app/code-server/bin/code-server \
    --extensions-dir /config/extensions \
    --user-data-dir /config/data \
    --install-extension bmewburn.vscode-intelephense-client || true
