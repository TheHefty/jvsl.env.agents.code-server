# Installs CPython {{VERSION}} from astral-sh/python-build-standalone, pinned by
# release, version and SHA-256 in stacks/python/standalone.json.
#
# **It used to be the deadsnakes PPA**, whose path says `ubuntu`. That archive
# exists only for Ubuntu, and Debian has no equivalent: asked of
# api.ftp-master.debian.org, trixie carries python3.13 and neither 3.11 nor
# 3.12. (`packages.debian.org/trixie/python3.11` answers HTTP 200 and that is
# not evidence — the page exists, the package is not in the suite.) So a base
# that is not Ubuntu leaves two of the three versions this stack offers with no
# distribution package at all.
#
# One tarball replaces three packages, which was measured rather than assumed
# before this was written: it carries include/python{{VERSION}}/Python.h, a
# libpython shared object, bin/pip, and the venv module — so it stands in for
# python{{VERSION}}, -dev and -venv together.
#
# **And it removes a `curl | python` from the build.** The old line piped
# bootstrap.pypa.io/get-pip.py into the interpreter as root, unverified — the
# one thing in this fragment the pin-and-verify convention never covered. pip is
# in the archive. The `--no-wheel` and `--break-system-packages` flags that line
# needed go with it: the first existed because core's Tauri build dependencies
# dragged in a Debian `python3-packaging` that pip then could not replace, and
# those dependencies left with the bundled launcher; the second because PEP 668
# marks the *system* interpreter as externally managed, and this one is not the
# system's.
#
# The project publishes no .sha256 assets, so the digests in standalone.json are
# ours, measured with sha256sum. A release asset can be replaced; the digest is
# what makes this fail instead of installing something else.
# Three things about the RUN below, kept here because no other fragment in this
# repository puts comments inside a RUN and a continuation full of them is a
# parser quirk to rely on rather than a style to introduce:
#
#   - **the tarball is per-architecture**, and a wrong guess composes a URL that
#     404s. A 404 on a release asset says nothing about why, so the `case` names
#     the architecture it does not know and stops;
#   - **`--strip-components=1`** because the archive unpacks a single `python/`
#     directory, and its contents belong directly under the version's prefix —
#     which is what the interpreter's own `sysconfig` paths expect;
#   - **`/opt`** because the agent's sandbox maps it read-only. That is the same
#     arrangement the Android SDK has: an interpreter the agent can run and
#     cannot modify.

COPY stacks/python/standalone.json /tmp/python-standalone.json
RUN set -eu \
    && PY_VERSION="{{VERSION}}" \
    && entry="$(jq -r --arg v "$PY_VERSION" '.[$v] // empty' /tmp/python-standalone.json)" \
    && if [ -z "$entry" ]; then \
         echo "python stack: no pinned build for ${PY_VERSION} in stacks/python/standalone.json." >&2; \
         echo "  versions.json offers it, so one of the two files is out of step with the other." >&2; \
         exit 1; \
       fi \
    && release="$(printf '%s' "$entry" | jq -r .release)" \
    && full="$(printf '%s' "$entry" | jq -r .version)" \
    && want_sha="$(printf '%s' "$entry" | jq -r .sha256)" \
    && case "$(uname -m)" in \
         x86_64)  triple=x86_64-unknown-linux-gnu ;; \
         aarch64) triple=aarch64-unknown-linux-gnu ;; \
         *) echo "python stack: no python-build-standalone triple known for $(uname -m)." >&2; exit 1 ;; \
       esac \
    && asset="cpython-${full}+${release}-${triple}-install_only_stripped.tar.gz" \
    && url="https://github.com/astral-sh/python-build-standalone/releases/download/${release}/${asset}" \
    && curl -fsSL -o /tmp/cpython.tar.gz "$url" \
    && echo "${want_sha}  /tmp/cpython.tar.gz" | sha256sum -c - \
    && mkdir -p "/opt/python/${PY_VERSION}" \
    && tar -xzf /tmp/cpython.tar.gz -C "/opt/python/${PY_VERSION}" --strip-components=1 \
    && rm -f /tmp/cpython.tar.gz /tmp/python-standalone.json \
    && update-alternatives --install /usr/bin/python3 python3 "/opt/python/${PY_VERSION}/bin/python3" 100 \
    && update-alternatives --install /usr/bin/pip3 pip3 "/opt/python/${PY_VERSION}/bin/pip3" 100 \
    && python3 -V \
    && python3 -m pip --version
