# Installs Python {{VERSION}} + venv + pip (deadsnakes PPA — Ubuntu's
# default repos only ship a single python3 version). Uses PyPA's own
# get-pip.py instead of `ensurepip`: Ubuntu 24.04 ships 3.12 as its own
# native python3 package (not from deadsnakes, unlike every other version
# offered here), and Debian patches `ensurepip` to refuse running for
# whichever Python is the OS-provided one — confirmed by actually running it
# (3.11/3.13 install fine with ensurepip, only 3.12 fails). get-pip.py works
# uniformly across all versions instead of branching this fragment per one.
# `--break-system-packages` is needed too: Debian's PEP 668
# externally-managed-environment marker blocks a plain get-pip.py run as well.
#
# `--no-wheel` is what keeps this building. get-pip.py installs `wheel`
# alongside pip by default, and wheel 0.47.0 added a `packaging>=24.0`
# dependency; pip then tries to replace the `packaging` already present as a
# Debian package and aborts with `uninstall-no-record-file` ("no RECORD file
# was found"), since apt-installed dists carry no RECORD for pip to remove
# them by. That `python3-packaging` (24.0) comes from *core*, not from here —
# `libglib2.0-dev-bin` pulls it in behind core's Tauri build deps — which is
# why the failure only ever showed up in a composed image and never in the
# stack fragment on its own. Nothing here needs a global `wheel` anyway:
# modern pip builds through PEP 517 with build isolation and fetches wheel
# into the isolated build env itself when a project actually needs it.
# Verified against all three versions this stack offers, not just the 3.11
# that CI builds.
# The PPA is added by writing its list file and its key, and **not** with
# `add-apt-repository`. That command is not a line in sources.list: it pulls in
# `software-properties-common` (packagekit, dbus, a systemd unit — all visible
# in the build log and none of it wanted in this image), then uses launchpadlib
# to ask **api.launchpad.net** which PPA is meant before writing anything. That
# API call is a second network dependency in the middle of a build, and it is
# the one that failed: `TimeoutError: [Errno 110] Connection timed out` after
# 146 seconds, as a Python traceback, from a step whose actual job is to append
# one line to a file.
#
# Writing it directly needs the archive host, which apt needs anyway, and the
# signing key, whose fingerprint is pinned here and was checked against the key
# the server actually serves rather than copied from a blog:
#
#     F23C 5A6C F475 9775 95C8  9F51 BA69 3236 6A75 5776
#     uid: Launchpad PPA for deadsnakes
#
# `signed-by` scopes that key to this one repository, so a compromise of it
# cannot sign packages for the rest of the system — which `add-apt-repository`
# also does now, and is the only part of it worth keeping.
#
# The codename comes from the base image rather than being pinned: this
# fragment is composed onto whatever `core` is FROM, and hardcoding `noble`
# would break silently on the next base bump — apt would 404 on a dists path
# that does not exist and say nothing about why.
RUN . /etc/os-release \
    && curl -fsSL "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0xF23C5A6CF475977595C89F51BA6932366A755776" \
        | gpg --dearmor -o /usr/share/keyrings/deadsnakes.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/deadsnakes.gpg] https://ppa.launchpadcontent.net/deadsnakes/ppa/ubuntu $VERSION_CODENAME main" \
        > /etc/apt/sources.list.d/deadsnakes.list \
    && apt-get update && apt-get install -y --no-install-recommends \
    python{{VERSION}} \
    python{{VERSION}}-venv \
    python{{VERSION}}-dev \
    && update-alternatives --install /usr/bin/python3 python3 /usr/bin/python{{VERSION}} 100 \
    && curl -fsSL https://bootstrap.pypa.io/get-pip.py | python{{VERSION}} - --no-wheel --break-system-packages \
    && rm -rf /var/lib/apt/lists/*

# Installs the code-server extension for Python (ms-python.python — unlike
# most ms-* extensions, this one is published to Open VSX too)
RUN /app/code-server/bin/code-server \
    --extensions-dir /config/extensions \
    --user-data-dir /config/data \
    --install-extension ms-python.python || true
