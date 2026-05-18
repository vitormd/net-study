#!/bin/sh
# Bootstrap PKI do api-gateway (nginx que termina mTLS na frente da api):
#   1. Lê root + intermediate CA do volume compartilhado do step-ca.
#   2. Pede um cert de servidor (24h) com SAN do api-gateway.
#   3. Concatena leaf + intermediate (chain completa pro client validar).
#   4. Builda o trust bundle pra exigir cert de cliente.
#   5. Sobe o nginx em foreground; renewer fica daemonizando em background.

set -e

STEPCA=https://step-ca:9000
ROOT=/step-data/certs/root_ca.crt
INTER=/step-data/certs/intermediate_ca.crt
TRUST=/run/trust.crt
CRT=/run/server.crt
KEY=/run/server.key
PWD_FILE=/run/ca-pwd

mkdir -p /run
echo -n "${CA_PASSWORD:-changeme-lab}" > "$PWD_FILE"

# Trust bundle pra ssl_client_certificate (CA bundle do nginx — root + intermediate).
cat "$ROOT" "$INTER" > "$TRUST"

echo "[api-gateway] requesting cert from step-ca..."
step ca certificate api-gateway "$CRT" "$KEY" \
  --san api-gateway \
  --san gateway \
  --san api \
  --san fd00:dead:beef::25 \
  --san ::1 \
  --san localhost \
  --not-after 24h \
  --ca-url "$STEPCA" --root "$ROOT" \
  --provisioner admin --password-file "$PWD_FILE" \
  --force

# Chain completa pro nginx mandar leaf + intermediate no handshake.
cat "$INTER" >> "$CRT"

step certificate inspect "$CRT" --short

# Renewer daemon — reescreve o cert no FS quando renovar e dá HUP no nginx.
step ca renew "$CRT" "$KEY" \
  --daemon --expires-in 16h \
  --ca-url "$STEPCA" --root "$ROOT" \
  --exec "nginx -s reload" &

exec nginx -g 'daemon off;'
