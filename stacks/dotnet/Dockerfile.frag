# Installs the .NET {{VERSION}} SDK (Microsoft's own apt feed — Ubuntu's
# default repos don't carry per-version .NET SDK packages)
RUN curl -fsSL https://packages.microsoft.com/config/ubuntu/24.04/packages-microsoft-prod.deb -o /tmp/packages-microsoft-prod.deb \
    && dpkg -i /tmp/packages-microsoft-prod.deb \
    && rm /tmp/packages-microsoft-prod.deb \
    && apt-get update && apt-get install -y --no-install-recommends \
    dotnet-sdk-{{VERSION}} \
    && rm -rf /var/lib/apt/lists/*
