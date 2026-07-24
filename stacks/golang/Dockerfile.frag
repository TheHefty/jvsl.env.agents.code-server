# Installs Go {{VERSION}} (official tarball — Ubuntu's golang-go package
# doesn't offer per-version selection)
RUN curl -fsSL https://go.dev/dl/go{{VERSION}}.linux-amd64.tar.gz | tar -C /usr/local -xz
ENV PATH=/usr/local/go/bin:$PATH
