# Installs GCC/G++ {{VERSION}} + CMake, GDB, and Make
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc-{{VERSION}} \
    g++-{{VERSION}} \
    cmake \
    gdb \
    make \
    && rm -rf /var/lib/apt/lists/* \
    && update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-{{VERSION}} 100 \
    && update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-{{VERSION}} 100
