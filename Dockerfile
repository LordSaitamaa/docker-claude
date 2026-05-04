FROM alpine:3.21

LABEL org.opencontainers.image.title="claude-code"
LABEL org.opencontainers.image.description="Hardened Claude Code dev environment"

# Linux: set USER_UID/USER_GID to match host (id -u && id -g)
# Windows/macOS: keep defaults – entrypoint handles permissions at runtime
ARG USER_UID=1000
ARG USER_GID=1000

# Create user before installing packages and Claude
RUN addgroup -g ${USER_GID} claude \
    && adduser -u ${USER_UID} -G claude -h /home/users/claude -s /bin/bash -D claude \
    && mkdir -p /home/users/claude/.claude /home/users/claude/workspace \
    && chown -R claude:claude /home/users/claude \
    && chmod 700 /home/users/claude/workspace

RUN apk add --no-cache \
        tmux git curl ca-certificates bash su-exec

ENV SHELL=/bin/bash

COPY --chown=claude:claude config/tmux.conf /home/users/claude/.tmux.conf
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN sed -i 's/\r//' /usr/local/bin/entrypoint.sh \
    && chmod 755 /usr/local/bin/entrypoint.sh

USER ${USER_UID}:${USER_GID}

# Install Claude Code natively as claude user
RUN curl -fsSL https://claude.ai/install.sh | bash

ENV PATH="/home/users/claude/.local/bin:${PATH}"

# Ensure PATH survives in interactive shells (Alpine /etc/profile resets it)
RUN echo 'export PATH="/home/users/claude/.local/bin:${PATH}"' >> /home/users/claude/.bashrc \
    && echo 'export PATH="/home/users/claude/.local/bin:${PATH}"' >> /home/users/claude/.profile

# Starts as root – entrypoint fixes permissions, then drops to claude via su-exec
WORKDIR /home/users/claude/workspace
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["bash"]
