#!/bin/bash
set -euo pipefail

# Initialize squid directories (tmpfs)
mkdir -p /var/log/squid /var/spool/squid /run/squid
chown proxy:proxy /var/log/squid /var/spool/squid /run/squid 2>/dev/null || true

# Generate config from template with extra domains
EXTRA_DOMAINS="${EXTRA_DOMAINS:-}"
EXTRA_ACL_LINES=""

if [[ -n "${EXTRA_DOMAINS}" ]]; then
    IFS=',' read -ra DOMAINS <<< "${EXTRA_DOMAINS}"
    for domain in "${DOMAINS[@]}"; do
        domain="$(echo "${domain}" | xargs)"
        [[ -z "${domain}" ]] && continue
        EXTRA_ACL_LINES+="acl allowed_domains dstdomain ${domain}\n"
    done
fi

export EXTRA_ACL_LINES
envsubst '${EXTRA_ACL_LINES}' \
    < /etc/squid/squid.conf.template \
    > /run/squid.conf

squid -N -f /run/squid.conf -z 2>/dev/null || true

echo "[squid] Active rules:"
grep -E "^acl allowed_domains|^http_access" /run/squid.conf || true
echo "---"

exec squid -NYCd1 -f /run/squid.conf