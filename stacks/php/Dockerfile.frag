# Installs PHP {{VERSION}} + common extensions + Composer (ondrej/php PPA —
# the de facto standard for multi-version PHP on Ubuntu/Debian)
RUN apt-get update && apt-get install -y --no-install-recommends software-properties-common \
    && add-apt-repository -y ppa:ondrej/php \
    && apt-get update && apt-get install -y --no-install-recommends \
    php{{VERSION}} \
    php{{VERSION}}-cli \
    php{{VERSION}}-mbstring \
    php{{VERSION}}-xml \
    php{{VERSION}}-curl \
    composer \
    && update-alternatives --install /usr/bin/php php /usr/bin/php{{VERSION}} 100 \
    && rm -rf /var/lib/apt/lists/*
