#!/bin/sh
# Gera os fixtures de teste do dropdown da aba mTLS:
#
#   /certs/wrong-ca.crt      -> CA paralela (não confiada pelo step-ca)
#   /certs/wrong-client.crt  -> cert de cliente assinado pela CA paralela
#   /certs/client-expired.crt-> cert assinado pelo intermediate do step-ca,
#                              com notAfter já vencido (gerado via Ruby + OpenSSL
#                              porque step-ca/CLI não emite certs já expirados).
#
# Roda como init container — uma vez só, depois do step-ca estar saudável.

set -e

CERTS=/certs
STEP=/step-data
mkdir -p "$CERTS"

if [ -f "$CERTS/wrong-ca.crt" ] && [ -f "$CERTS/client-expired.crt" ]; then
  echo "[gen-test-certs] fixtures já existem em $CERTS, nada a fazer"
  exit 0
fi

echo "[gen-test-certs] gerando wrong-ca + wrong-client (assinados por CA paralela)"
openssl req -x509 -new -nodes -newkey rsa:2048 -days 3650 \
  -subj "/C=BR/O=evil-corp/CN=Evil Root CA" \
  -keyout "$CERTS/wrong-ca.key" -out "$CERTS/wrong-ca.crt" 2>/dev/null

openssl genrsa -out "$CERTS/wrong-client.key" 2048 2>/dev/null
cat > /tmp/wc.cnf <<EOF
[req]
distinguished_name = dn
prompt = no
[dn]
C = BR
O = evil-corp
CN = imposter
[v3]
keyUsage = critical, digitalSignature
extendedKeyUsage = clientAuth
EOF
openssl req -new -key "$CERTS/wrong-client.key" -out /tmp/wc.csr -config /tmp/wc.cnf 2>/dev/null
openssl x509 -req -in /tmp/wc.csr -CA "$CERTS/wrong-ca.crt" -CAkey "$CERTS/wrong-ca.key" \
  -CAcreateserial -out "$CERTS/wrong-client.crt" -days 825 -sha256 \
  -extfile /tmp/wc.cnf -extensions v3 2>/dev/null

echo "[gen-test-certs] gerando client-expired (assinado pelo intermediate do step-ca)"
ruby - <<'RUBY'
require 'openssl'
require 'time'

intermediate = OpenSSL::X509::Certificate.new(File.read('/step-data/certs/intermediate_ca.crt'))
inter_key_pem = File.read('/step-data/secrets/intermediate_ca_key')
inter_key = OpenSSL::PKey.read(inter_key_pem, ENV.fetch('CA_PASSWORD', 'changeme-lab'))

# Gera keypair RSA pro cert (mais simples pro Puma/Ruby do que EC).
key = OpenSSL::PKey::RSA.new(2048)

cert = OpenSSL::X509::Certificate.new
cert.version    = 2
cert.serial     = OpenSSL::BN.rand(64)
cert.subject    = OpenSSL::X509::Name.parse('/O=net-study/CN=client-expired')
cert.issuer     = intermediate.subject
cert.public_key = key.public_key
cert.not_before = Time.now - (30 * 24 * 3600)
cert.not_after  = Time.now -       (24 * 3600)   # já vencido

ef = OpenSSL::X509::ExtensionFactory.new
ef.subject_certificate = cert
ef.issuer_certificate  = intermediate
cert.add_extension(ef.create_extension('keyUsage', 'digitalSignature', true))
cert.add_extension(ef.create_extension('extendedKeyUsage', 'clientAuth', false))

cert.sign(inter_key, OpenSSL::Digest::SHA256.new)

# Bundle = leaf + intermediate (chain completa pro handshake).
File.write('/certs/client-expired.crt', cert.to_pem + intermediate.to_pem)
File.write('/certs/client-expired.key', key.to_pem)
puts "  ok — notAfter=#{cert.not_after.utc.iso8601}"
RUBY

rm -f /tmp/wc.cnf /tmp/wc.csr "$CERTS"/*.srl
echo "[gen-test-certs] done"
ls -1 "$CERTS"
