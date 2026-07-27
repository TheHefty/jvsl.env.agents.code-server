# Installs Java {{VERSION}} + Maven
RUN apt-get update && apt-get install -y --no-install-recommends \
    openjdk-{{VERSION}}-jdk \
    maven \
    && rm -rf /var/lib/apt/lists/*

# Installs the code-server extension for Java (Open VSX — code-server's
# default marketplace, since ms-* extensions aren't published there)
RUN /app/code-server/bin/code-server \
    --extensions-dir /config/extensions \
    --user-data-dir /config/data \
    --install-extension redhat.java || true
