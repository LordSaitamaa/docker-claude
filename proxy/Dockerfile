FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
        squid squidclient curl gettext-base \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

RUN squid -z --foreground 2>/dev/null || true

COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod 755 /usr/local/bin/docker-entrypoint.sh

EXPOSE 3128
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
