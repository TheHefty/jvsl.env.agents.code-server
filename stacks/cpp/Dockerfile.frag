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

# Installs the code-server extension for C/C++ (Open VSX — ms-vscode.cpptools
# isn't published there, clangd is the closest maintained equivalent)
RUN /app/code-server/bin/code-server \
    --extensions-dir /config/extensions \
    --user-data-dir /config/data \
    --install-extension llvm-vs-code-extensions.vscode-clangd || true
