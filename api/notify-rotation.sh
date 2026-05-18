#!/bin/sh
# Chamado pelo `step ca renew --daemon --exec` quando o cert é renovado.
# Posta um evento pro dashboard pra aparecer no log + dispara recarga via
# arquivo-marca (a app monitora mtime do cert).
set -e

curl -fs -m 2 -X POST \
  -H 'content-type: application/json' \
  -d "{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%S.000Z)\",\"source\":\"api\",\"type\":\"cert_renewed\",\"path\":\"/run/server.crt\"}" \
  "${DASHBOARD_URL}/events" || true

# Touch the file pra forçar mtime nova caso o renew tenha mantido o mesmo nome.
touch /run/server.crt
