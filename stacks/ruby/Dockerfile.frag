# Installs Ruby {{VERSION}}, built from source via ruby-build — no actively
# maintained PPA covers multi-version Ruby on current Ubuntu releases
# (brightbox/ruby-ng's last published dist is 'zesty', ~2017). rustc, needed
# to build YJIT, is already provided by core/.
RUN apt-get update && apt-get install -y --no-install-recommends \
    autoconf \
    patch \
    libssl-dev \
    libyaml-dev \
    libreadline-dev \
    zlib1g-dev \
    libncurses-dev \
    libffi-dev \
    libgdbm-dev \
    uuid-dev \
    libgmp-dev \
    && rm -rf /var/lib/apt/lists/* \
    && git clone --depth 1 https://github.com/rbenv/ruby-build.git /tmp/ruby-build \
    && /tmp/ruby-build/bin/ruby-build {{VERSION}} /usr/local \
    && rm -rf /tmp/ruby-build
