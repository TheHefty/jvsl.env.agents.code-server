# A stand-in for the real image, carrying only what booted.test.sh asserts.
# See entrypoint.sh for what it emulates and what it deliberately does not.
FROM alpine:3.21
RUN apk add --no-cache bash coreutils \
    && adduser -D -s /bin/bash abc \
    && mkdir -p /config /custom-cont-init.d \
    && chown abc:abc /config
COPY core/cont-init/10-state-ownership.sh /custom-cont-init.d/10-state-ownership.sh
COPY core/booted.test.fixture/entrypoint.sh /entrypoint.sh
RUN chmod +x /custom-cont-init.d/10-state-ownership.sh /entrypoint.sh
LABEL devcontainer.metadata='[{"remoteUser":"abc"}]'
ENTRYPOINT ["/entrypoint.sh"]
