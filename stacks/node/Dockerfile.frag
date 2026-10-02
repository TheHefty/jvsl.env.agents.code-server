# Installs Node.js {{VERSION}} (NodeSource), replacing the core's own Node.js
# 22 (installed only to bootstrap the Claude Code CLI) with the version
# selected for the monorepo's own code. Needs an explicit version pin +
# `--allow-downgrades`: NodeSource's repo priority (600) isn't high enough
# for apt to treat it as a downgrade candidate over an already-installed
# newer version (APT only auto-downgrades above priority 1000), so
# `apt-cache policy`'s own "Candidate:" line still reports the core's Node
# 22 here — pulling the version from `apt-cache madison`'s nodesource entry
# instead is what actually reflects the repo just configured above.
RUN curl -fsSL https://deb.nodesource.com/setup_{{VERSION}}.x | bash - \
    && NODE_PKG_VERSION="$(apt-cache madison nodejs | awk -F'|' '/nodesource/ {gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2; exit}')" \
    && apt-get install -y --allow-downgrades "nodejs=$NODE_PKG_VERSION" \
    && rm -rf /var/lib/apt/lists/*
