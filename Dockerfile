# EasyTier-Web - Docker packaging of the fnOS "EasyTier-Web" suite.
#
# The image bundles the two prebuilt EasyTier 2.4.5 binaries that ship in the
# original .fpk package (they are statically linked, so a musl base is fine):
#   * easytier-web-embed  - web dashboard + REST API + config server
#   * easytier-core       - EasyTier networking daemon
#
FROM alpine:3.20

LABEL org.opencontainers.image.title="EasyTier-Web" \
      org.opencontainers.image.description="EasyTier Web management dashboard and EasyTier core, packaged for Docker" \
      org.opencontainers.image.version="2.4.5" \
      org.opencontainers.image.licenses="LGPL-3.0" \
      org.opencontainers.image.url="https://github.com/EasyTier/EasyTier"

# bash for the entrypoint, iproute2/iptables for TUN + route setup, tzdata for TZ.
RUN apk add --no-cache \
        bash \
        iproute2 \
        iptables \
        ip6tables \
        jq \
        tzdata \
        ca-certificates \
 && update-ca-certificates \
 && rm -rf /var/cache/apk/*

WORKDIR /app/server

COPY app/server/easytier-core app/server/easytier-web-embed ./
RUN chmod 0755 easytier-core easytier-web-embed

COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY docker/healthcheck.sh /usr/local/bin/healthcheck.sh
RUN chmod 0755 /usr/local/bin/entrypoint.sh /usr/local/bin/healthcheck.sh

# Persisted state: sqlite db, config.json and logs all live under /data.
VOLUME ["/data"]

ENV DATA_DIR=/data \
    CONFIG_SERVER_PORT=22020 \
    NO_TUN=0 \
    TZ=Asia/Shanghai

# 11211 web dashboard/API, 22020 config server (loopback), 11010/11011 EasyTier listeners.
EXPOSE 11211/tcp 22020/udp 11010/tcp 11010/udp 11011/tcp 11011/udp

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD ["/usr/local/bin/healthcheck.sh"]

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
