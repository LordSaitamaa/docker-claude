#!/usr/bin/env bash
set -euo pipefail

SESSION="claude"
CLAUDE_USER="claude"
CLAUDE_HOME="/home/users/${CLAUDE_USER}"
WORKSPACE="${CLAUDE_HOME}/workspace"

# --- Permission fix (Linux + Windows/Docker Desktop) ---
# No usermod/groupmod needed – preserves read_only: true
fix_permissions() {
    local ws_uid ws_gid claude_uid
    ws_uid="$(stat -c '%u' "${WORKSPACE}")"
    ws_gid="$(stat -c '%g' "${WORKSPACE}")"
    claude_uid="$(id -u "${CLAUDE_USER}")"

    # Windows/Docker Desktop: workspace owned by root (0:0)
    # chown/chmod on NTFS bind-mounts is a no-op – skip gracefully
    if [[ "${ws_uid}" == "0" && "${ws_gid}" == "0" ]]; then
        echo "[INFO] ${WORKSPACE} owned by root (Windows/Docker Desktop detected – skipping chown)."
    fi

    # Linux: UID mismatch (USER_UID build arg not set)
    if [[ "${ws_uid}" != "0" && "${ws_uid}" != "${claude_uid}" ]]; then
        echo "[WARN] ${WORKSPACE} UID (${ws_uid}) != ${CLAUDE_USER} UID (${claude_uid})." >&2
        echo "[WARN] Rebuild: docker compose build --build-arg USER_UID=${ws_uid} --build-arg USER_GID=${ws_gid}" >&2
        chmod -R a+rw "${WORKSPACE}" 2>/dev/null || true
    fi

    chown -R "${CLAUDE_USER}:claude" "${CLAUDE_HOME}" 2>/dev/null || true
    chmod 700 "${WORKSPACE}" 2>/dev/null || true
}

if [[ "$(id -u)" == "0" ]]; then
    fix_permissions
fi

# Run command as claude user (with exec – replaces current process)
run_as_claude() {
    if [[ "$(id -u)" == "0" ]]; then
        exec su-exec "${CLAUDE_USER}" "$@"
    else
        exec "$@"
    fi
}

# Run command as claude user (without exec – returns to caller)
_run() {
    if [[ "$(id -u)" == "0" ]]; then
        su-exec "${CLAUDE_USER}" "$@"
    else
        "$@"
    fi
}

# --- Auth check ---
if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
    if [[ ! -f "${CLAUDE_HOME}/.claude/credentials.json" && ! -f "${CLAUDE_HOME}/.claude/.credentials.json" ]]; then
        echo "[INFO] No API key or login token found." >&2
        echo "[INFO] Run inside the container: claude login" >&2
        echo "[INFO] Open the displayed link in your host browser." >&2
    fi
fi

# --- Wait for proxy (non-fatal) ---
PROXY_HOST="${PROXY_HOST:-squid}"
PROXY_PORT="${PROXY_PORT:-3128}"
MAX_WAIT=60
elapsed=0

# Phase 1: wait for squid TCP port
# -so /dev/null (no -f) → curl returns 0 as long as squid sends ANY HTTP response
echo "[INFO] Waiting for proxy at ${PROXY_HOST}:${PROXY_PORT} …"
until curl -so /dev/null --max-time 2 "http://${PROXY_HOST}:${PROXY_PORT}/" 2>/dev/null; do
    if (( elapsed >= MAX_WAIT )); then
        echo "[WARN] Proxy not reachable after ${MAX_WAIT}s – starting anyway." >&2
        break
    fi
    sleep 1
    (( elapsed++ ))
done

if (( elapsed < MAX_WAIT )); then
    echo "[INFO] Proxy port reachable after ${elapsed}s."

    # Phase 2: verify end-to-end connectivity (non-fatal)
    if curl -so /dev/null --max-time 10 --proxy "http://${PROXY_HOST}:${PROXY_PORT}" \
            "https://api.anthropic.com/" 2>/dev/null; then
        echo "[INFO] Anthropic API reachable through proxy."
    else
        echo "[WARN] Proxy up but Anthropic API not yet reachable – Claude Code will retry automatically." >&2
    fi
fi

# --- YOLO mode (dangerously-skip-permissions) ---
YOLO="${CLAUDE_YOLO:-false}"
CLAUDE_BIN="/home/users/claude/.local/bin/claude"
CLAUDE_CMD="${CLAUDE_BIN}"
if [[ "${YOLO}" == "true" || "${YOLO}" == "1" || "${YOLO}" == "yes" ]]; then
    CLAUDE_CMD="${CLAUDE_BIN} --dangerously-skip-permissions"
    echo "[WARN] ⚠  YOLO mode ENABLED – Claude will auto-approve ALL tool calls!" >&2
fi

# --- Tmux session ---
if ! _run tmux has-session -t "${SESSION}" 2>/dev/null; then
    _run tmux new-session -d -s "${SESSION}" -x 220 -y 50
    _run tmux send-keys -t "${SESSION}" "${CLAUDE_CMD}" Enter
    echo "[INFO] tmux session '${SESSION}' created – running: ${CLAUDE_CMD}"
fi

if [[ "${YOLO}" == "true" || "${YOLO}" == "1" || "${YOLO}" == "yes" ]]; then
cat <<EOF

╔═══════════════════════════════════════════════════════════════════════╗
║        Claude Code – Secure Docker Container  [YOLO MODE]             ║
╠═══════════════════════════════════════════════════════════════════════╣
║  ⚠  --dangerously-skip-permissions is ACTIVE                          ║
║  Bash:    docker exec -it -u claude claude-code bash                  ║
║  Tmux:    docker exec -it -u claude claude-code tmux attach -t ${SESSION}  ║
║  Detach:  Ctrl-a  d  (tmux only)                                      ║
╚═══════════════════════════════════════════════════════════════════════╝

EOF
else
cat <<EOF

╔═══════════════════════════════════════════════════════════════════════╗
║                Claude Code – Secure Docker Container                  ║
╠═══════════════════════════════════════════════════════════════════════╣
║  Bash:    docker exec -it -u claude claude-code bash                  ║
║  Tmux:    docker exec -it -u claude claude-code tmux attach -t ${SESSION}  ║
║  Detach:  Ctrl-a  d  (tmux only)                                      ║
╚═══════════════════════════════════════════════════════════════════════╝

EOF
fi

# Keep container alive as claude user
run_as_claude tail -f /dev/null
