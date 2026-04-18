#!/usr/bin/env bash
# Start the nullbore tunnel with the server's install UUID as the slug.
# Run this AFTER `docker compose up server` so the UUID exists.
set -euo pipefail

cd "$(dirname "$0")/../server"

# Load relay env
set -a
. ../relay/.env
set +a

if [ -z "${NULLBORE_API_KEY:-}" ]; then
  echo "error: NULLBORE_API_KEY not set in engineering/relay/.env" >&2
  exit 1
fi

# Wait for the server and read its install UUID
for i in $(seq 1 30); do
  if info=$(curl -fsS http://localhost:7654/api/server-info 2>/dev/null); then
    break
  fi
  sleep 1
done
if [ -z "${info:-}" ]; then
  echo "error: abookify server not responding on :7654 — start it first" >&2
  exit 1
fi

SERVER_ID=$(echo "$info" | sed -n 's/.*"server_id":"\([^"]*\)".*/\1/p')
if [ -z "$SERVER_ID" ]; then
  echo "error: could not read server_id from /api/server-info" >&2
  exit 1
fi

echo "relay: tunneling https://${SERVER_ID}.${NULLBORE_BASE_DOMAIN:-abookify.nullbore.com} → local :7654"

export NULLBORE_TUNNELS="server:7654:${SERVER_ID}"
exec docker compose --profile relay up -d --build nullbore
