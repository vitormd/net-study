#!/bin/sh
set -e

STEPCA=https://step-ca:9000
ROOT=/step-data/certs/root_ca.crt
CRT=/run/client.crt
KEY=/run/client.key
PWD_FILE=/run/ca-pwd

mkdir -p /run
echo -n "${CA_PASSWORD:-changeme-lab}" > "$PWD_FILE"

echo "[entrypoint] requesting client cert from step-ca..."
step ca certificate client-01 "$CRT" "$KEY" \
  --not-after 24h \
  --ca-url "$STEPCA" --root "$ROOT" \
  --provisioner admin --password-file "$PWD_FILE" \
  --force

# Concatena o intermediate no cert do cliente (chain completa no handshake).
cat /step-data/certs/intermediate_ca.crt >> "$CRT"

step certificate inspect "$CRT" --short

# Renewer em background.
step ca renew "$CRT" "$KEY" \
  --daemon --expires-in 16h \
  --ca-url "$STEPCA" --root "$ROOT" &

sleep 1
exec bundle exec puma -b tcp://[::]:4000 config.ru
