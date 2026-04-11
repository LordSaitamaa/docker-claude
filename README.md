# docker-claude

Hardened Docker environment for [Claude Code](https://docs.anthropic.com/en/docs/claude-code). All outbound traffic is routed through a Squid proxy that only allows whitelisted domains.

```text
claude-code ──[internal network]──► squid-proxy ──[external network]──► Internet
                 (no internet)                      (whitelist only)
```

## Setup

### Prerequisites

- Docker Engine 24+ with Compose V2
- An Anthropic API key **or** a Claude Pro/Max subscription

### Quick start

```bash
# 1. Clone
git clone https://github.com/your-user/docker-claude.git
cd docker-claude

# 2. Configure
cp .env.example .env
# Edit .env – at minimum set ANTHROPIC_API_KEY and REPO_PATH

# 3. Linux only – match your host UID/GID to avoid permission issues
# echo "USER_UID=$(id -u)" >> .env
# echo "USER_GID=$(id -g)" >> .env

# 4. Start
docker compose up -d
```

> **Windows / macOS (Docker Desktop):** Do not set `USER_UID` / `USER_GID`. The entrypoint detects root-owned bind mounts and fixes permissions automatically.

### Attach to the session

```bash
docker exec -it claude-code tmux attach -t claude
```

Detach with `Ctrl-a d`.

### Claude subscription login (no API key)

Leave `ANTHROPIC_API_KEY` empty in `.env`, then:

```bash
docker exec -it claude-code tmux attach -t claude
# Inside the container:
claude login
# Open the displayed URL in your host browser
```

The token is persisted in your mounted `~/.claude` directory.

## Security

The container follows a defense-in-depth approach:

| Layer | Mechanism |
| --- | --- |
| **Network isolation** | Claude container has no direct internet access. All traffic goes through the Squid proxy on an internal-only Docker network. |
| **Domain whitelist** | Squid blocks everything except `.anthropic.com` and `.claude.ai` by default. Additional domains can be added via `EXTRA_DOMAINS`. |
| **Least privilege** | All Linux capabilities are dropped. Only `CHOWN`, `SETUID`, and `SETGID` are added (required for the permission-fix entrypoint and `gosu`). |
| **Read-only rootfs** | The container filesystem is read-only. Writable paths (`/tmp`, `/home/claude/.local`, etc.) use size-limited `tmpfs` mounts. |
| **No privilege escalation** | `no-new-privileges` is set. The entrypoint starts as root solely to fix volume permissions, then drops to the `claude` user via `gosu`. |
| **Resource limits** | CPU (2 cores) and memory (2 GB) limits prevent resource exhaustion on the host. |
| **Seccomp** | Optional syscall filtering via `security/seccomp.json` (referenced in compose – provide your own profile or remove the line). |

## Configuration

All configuration is done via `.env` (copy from `.env.example`).

| Variable | Required | Default | Description |
| --- | --- | --- | --- |
| `ANTHROPIC_API_KEY` | yes* | – | API key. Leave empty when using `claude login`. |
| `REPO_PATH` | yes | `./workspace` | Absolute path to the repository to mount into the container. |
| `CLAUDE_CONFIG_PATH` | no | `~/.claude` | Path to Claude config directory (persists auth tokens). |
| `USER_UID` / `USER_GID` | no | `1000` | Host UID/GID for volume permissions. **Linux only** – do not set on Windows/macOS. |
| `EXTRA_DOMAINS` | no | – | Comma-separated list of additional domains to whitelist (e.g. `.github.com,.npmjs.org`). |

### Adding domains to the whitelist

Set `EXTRA_DOMAINS` in `.env`:

```env
EXTRA_DOMAINS=.github.com,.npmjs.org,registry.npmjs.org
```

Then restart:

```bash
docker compose restart squid
```

## Usage

### Start / stop

```bash
docker compose up -d      # start
docker compose down        # stop
docker compose restart     # restart both containers
```

### Attach to Claude Code

```bash
docker exec -it -u claude claude-code tmux attach -t claude
```

Inside tmux, `Ctrl-a d` detaches without stopping the container.

### Run a one-off command

```bash
docker exec -it -u claude claude-code claude --version
```

### View proxy logs

```bash
docker logs -f claude-squid
```

### Rebuild after config changes

```bash
# Rebuild with custom UID (Linux)
docker compose build --build-arg USER_UID=$(id -u) --build-arg USER_GID=$(id -g)
docker compose up -d

# Rebuild with new Claude Code version
docker compose build --build-arg CLAUDE_CODE_VERSION=1.0.0
docker compose up -d
```
