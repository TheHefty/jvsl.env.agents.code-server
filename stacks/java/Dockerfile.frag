# Instala Java {{VERSION}} + Maven
RUN apt-get update && apt-get install -y --no-install-recommends \
    openjdk-{{VERSION}}-jdk \
    maven \
    && rm -rf /var/lib/apt/lists/*
