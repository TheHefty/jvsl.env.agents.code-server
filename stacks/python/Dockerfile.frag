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
RUN apt-get update && apt-get install -y --no-install-recommends software-properties-common \
    && add-apt-repository -y ppa:deadsnakes/ppa \
    && apt-get update && apt-get install -y --no-install-recommends \
    python{{VERSION}} \
    python{{VERSION}}-venv \
    python{{VERSION}}-dev \
    && update-alternatives --install /usr/bin/python3 python3 /usr/bin/python{{VERSION}} 100 \
    && curl -fsSL https://bootstrap.pypa.io/get-pip.py | python{{VERSION}} - --break-system-packages \
    && rm -rf /var/lib/apt/lists/*

# Installs the code-server extension for Python (ms-python.python — unlike
# most ms-* extensions, this one is published to Open VSX too)
RUN /app/code-server/bin/code-server \
    --extensions-dir /config/extensions \
    --user-data-dir /config/data \
    --install-extension ms-python.python || true
