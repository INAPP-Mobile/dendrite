#!/bin/sh
# Dendrite (element-hq) monolith entrypoint for Railway.
#
# Why this script exists (read before changing it):
# - Dendrite has no official "first run on Railway" path: its config file must
#   be generated (generate-config), its Matrix signing key must exist
#   (generate-keys), and its first account must be created with the
#   create-account tool against a RUNNING server (there is no way to
#   pre-seed an account, and Railway offers no container exec).
# - Registration is intentionally DISABLED in the generated config: Dendrite
#   refuses to start with open registration and no captcha (the
#   open-registration-without-verification flag is code-only, not YAML, so
#   it cannot be set from a config file). The template therefore ships one
#   admin account, created here on first boot from DENDRITE_ADMIN_USER /
#   DENDRITE_ADMIN_PASSWORD. Additional local accounts cannot self-register;
#   the admin invites remote Matrix users via federation instead.
# - server_name is pinned at first boot: Matrix user IDs are
#   @user:server_name, so changing it later would orphan every account.
#   RAILWAY_PUBLIC_DOMAIN is read at first boot only; later boots reuse
#   the pinned value even if the domain changes.
# - The config is regenerated on EVERY boot from the running image's own
#   generate-config, so it always matches the image version; only the
#   pinned values (server_name, signing key, shared secret) are carried over.
# - Dendrite binds Railway's injected PORT via --http-bind-address. Its
#   HTTPS listener is skipped (no certs): Railway terminates TLS at the
#   edge and the plain HTTP listener serves the full API, including
#   federation routes, so a custom domain with a .well-known delegation
#   to this deployment's domain:443 can federate.
# - All state lives under /data (the Railway volume): config, keys,
#   SQLite databases, media, JetStream, search index. Nothing is written
#   to the image layer, so restarts and redeploys keep the server.

set -e

DATA=/data
PORT="${PORT:-8008}"
mkdir -p "$DATA"
cd "$DATA"

# --- 1. Matrix signing key (server identity; generated once) ---
if [ ! -f "$DATA/matrix_key.pem" ]; then
  echo "[dendrite] generating Matrix signing key..."
  /usr/bin/generate-keys --private-key "$DATA/matrix_key.pem"
fi

# --- 2. server_name, pinned at first boot ---
if [ -f "$DATA/server_name" ]; then
  SERVER_NAME=$(cat "$DATA/server_name")
else
  SERVER_NAME="${RAILWAY_PUBLIC_DOMAIN:-localhost}"
  printf '%s' "$SERVER_NAME" > "$DATA/server_name"
  echo "[dendrite] first boot: server_name=$SERVER_NAME"
fi

# --- 3. registration shared secret (persisted; create-account needs it) ---
if [ ! -f "$DATA/registration_shared_secret" ]; then
  head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n' > "$DATA/registration_shared_secret"
fi
REG_SECRET=$(cat "$DATA/registration_shared_secret")

# --- 4. config, regenerated every boot from this image's generate-config ---
/usr/bin/generate-config -server "$SERVER_NAME" -dir "$DATA" > "$DATA/dendrite.yaml.new"
awk -v keypath="$DATA/matrix_key.pem" -v secret="$REG_SECRET" '
  /^[[:space:]]*private_key:/ { sub(/:.*/, ": " keypath); print; next }
  /^[[:space:]]*registration_disabled:/ { sub(/:.*/, ": true"); print; next }
  /^[[:space:]]*registration_shared_secret:/ { sub(/:.*/, ": \"" secret "\""); print; next }
  /^[[:space:]]*type: file/ && !done { sub(/:.*/, ": std"); print; done = 1; next }
  { print }
' "$DATA/dendrite.yaml.new" > "$DATA/dendrite.yaml"
rm -f "$DATA/dendrite.yaml.new"

# --- 5. start the server (background) so first-boot admin creation can run ---
/usr/bin/dendrite --config "$DATA/dendrite.yaml" --http-bind-address ":$PORT" &
SERVER_PID=$!
trap 'kill $SERVER_PID 2>/dev/null; wait $SERVER_PID 2>/dev/null; exit 0' TERM INT

# --- 6. wait for readiness (or a startup crash) ---
READY=0
i=0
while [ "$i" -lt 90 ]; do
  if ! kill -0 $SERVER_PID 2>/dev/null; then
    echo "[dendrite] server exited during startup; aborting."
    exit 1
  fi
  if curl -sf "http://127.0.0.1:$PORT/_matrix/client/versions" >/dev/null 2>&1; then
    READY=1
    break
  fi
  sleep 2
  i=$((i + 1))
done

# --- 7. first-boot admin account (once; marker lives on the volume) ---
# The marker is written only on success, so a failed attempt (e.g. a
# password shorter than Dendrite's 8-character minimum) retries on restart
# after the variable is fixed.
if [ "$READY" = "1" ] && [ ! -f "$DATA/.admin-created" ]; then
  ADMIN_USER="${DENDRITE_ADMIN_USER:-admin}"
  if [ -z "${DENDRITE_ADMIN_PASSWORD:-}" ]; then
    DENDRITE_ADMIN_PASSWORD=$(head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n')
    echo "=================================================================="
    echo "[dendrite] DENDRITE_ADMIN_PASSWORD was empty; generated one (SAVE THIS):"
    echo "[dendrite] $DENDRITE_ADMIN_PASSWORD"
    echo "=================================================================="
  fi
  if printf '%s' "$DENDRITE_ADMIN_PASSWORD" | /usr/bin/create-account \
      --config "$DATA/dendrite.yaml" \
      --username "$ADMIN_USER" --passwordstdin --admin \
      --url "http://127.0.0.1:$PORT"; then
    touch "$DATA/.admin-created"
    echo "[dendrite] admin account @$ADMIN_USER:$SERVER_NAME created"
  else
    echo "[dendrite] WARNING: admin account creation failed; will retry on restart"
  fi
fi

echo "[dendrite] listening on :$PORT as $SERVER_NAME"
wait $SERVER_PID
