# Installs Python {{VERSION}} + venv + pip (deadsnakes PPA — Ubuntu's
# default repos only ship a single python3 version)
RUN apt-get update && apt-get install -y --no-install-recommends software-properties-common \
    && add-apt-repository -y ppa:deadsnakes/ppa \
    && apt-get update && apt-get install -y --no-install-recommends \
    python{{VERSION}} \
    python{{VERSION}}-venv \
    python{{VERSION}}-dev \
    && update-alternatives --install /usr/bin/python3 python3 /usr/bin/python{{VERSION}} 100 \
    && python{{VERSION}} -m ensurepip --upgrade \
    && rm -rf /var/lib/apt/lists/*
