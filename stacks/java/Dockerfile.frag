# Installs OpenJDK {{VERSION}} from the distribution's own archive.
#
# **It offered 17 and 21 until the base became Debian trixie, which does not
# package 17.** Asked of api.ftp-master.debian.org: `openjdk-17-jdk` and
# `openjdk-24-jdk` are absent from trixie, `openjdk-21-jdk` and
# `openjdk-25-jdk` are there. So the list is 21 and 25.
#
# Moving to Adoptium would have kept 17 — `packages.adoptium.net` serves trixie
# and carries temurin-8 through temurin-27 — and was weighed against the cost: a
# second third-party repository with a key to vendor, verify and rotate, for one
# version of one stack. Taking what the distribution packages was chosen
# instead, and the capability lost is real: a project pinned to Java 17 has to
# say so itself.
#
# The android stack depends on this one, so it now builds against 21.
RUN apt-get update && apt-get install -y --no-install-recommends \
    openjdk-{{VERSION}}-jdk \
    maven \
    && rm -rf /var/lib/apt/lists/*
