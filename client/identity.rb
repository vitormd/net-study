# Onboarding mTLS — geração de keypair + CSR e instalação de cert assinado.
#
# A chave privada nasce e morre dentro do container do client. Para o dashboard
# (ou qualquer outra entidade externa) só sai o CSR (chave PÚBLICA + identidade).
#
# /data/ é o FS interno do container — efêmero por design: restart = volta ao
# estado original.
#
# Mantemos um único slot de identidade. Os arquivos sempre se chamam
# /data/identity.{key,crt} — o CN vive dentro do cert. Isso simplifica a
# resolução de "qual identidade está ativa" sem perder a flexibilidade do CN.

require 'openssl'
require 'fileutils'
require_relative 'events'

module Identity
  module_function

  DATA_DIR = '/data'
  KEY_PATH = "#{DATA_DIR}/identity.key"
  CRT_PATH = "#{DATA_DIR}/identity.crt"
  CA_FILE  = '/step-data/certs/root_ca.crt'

  DEFAULT_CN = 'client-02'
  CN_PATTERN = /\A[A-Za-z0-9_.\-]{1,64}\z/

  def generate(cn = DEFAULT_CN)
    cn = cn.to_s.strip
    cn = DEFAULT_CN if cn.empty?
    raise ArgumentError, "invalid CN — use 1-64 chars [A-Za-z0-9._-]" unless cn.match?(CN_PATTERN)

    FileUtils.mkdir_p(DATA_DIR)

    key = OpenSSL::PKey::RSA.new(2048)
    File.write(KEY_PATH, key.to_pem)
    File.delete(CRT_PATH) if File.exist?(CRT_PATH)  # keypair novo invalida o cert anterior

    csr = OpenSSL::X509::Request.new
    csr.version = 0
    csr.subject = OpenSSL::X509::Name.new([
      ['C',  'BR',          OpenSSL::ASN1::PRINTABLESTRING],
      ['O',  'net-study',   OpenSSL::ASN1::UTF8STRING],
      ['CN', cn,            OpenSSL::ASN1::UTF8STRING]
    ])
    csr.public_key = key.public_key
    csr.sign(key, OpenSSL::Digest::SHA256.new)

    Events.emit('identity_csr_generated', cn: cn, key_bits: 2048)
    csr.to_pem
  end

  def install(cert_pem)
    cert = OpenSSL::X509::Certificate.new(cert_pem)

    unless File.exist?(KEY_PATH)
      reason = 'no pending private key — generate a keypair first'
      Events.emit('identity_install_failed', reason: reason)
      return { ok: false, reason: reason }
    end

    key = OpenSSL::PKey::RSA.new(File.read(KEY_PATH))
    unless cert.public_key.to_pem == key.public_key.to_pem
      reason = 'public key mismatch — this cert was not issued for the pending CSR'
      Events.emit('identity_install_failed', reason: reason)
      return { ok: false, reason: reason }
    end

    store = OpenSSL::X509::Store.new
    store.add_file(CA_FILE)
    # Adiciona o intermediate, que vive ao lado do root no volume do step-ca.
    intermediate = '/step-data/certs/intermediate_ca.crt'
    store.add_file(intermediate) if File.exist?(intermediate)
    unless store.verify(cert)
      reason = "chain validation failed: #{store.error_string}"
      Events.emit('identity_install_failed', reason: reason)
      return { ok: false, reason: reason }
    end

    File.write(CRT_PATH, cert.to_pem)
    Events.emit('identity_installed', cn: cn_of(cert), serial: cert.serial.to_s,
                                       not_after: cert.not_after.utc.iso8601)
    { ok: true, cn: cn_of(cert), serial: cert.serial.to_s, not_after: cert.not_after.utc.iso8601 }
  rescue OpenSSL::X509::CertificateError => e
    Events.emit('identity_install_failed', reason: "invalid PEM: #{e.message}")
    { ok: false, reason: "invalid PEM: #{e.message}" }
  end

  def reset!
    File.delete(CRT_PATH) if File.exist?(CRT_PATH)
    File.delete(KEY_PATH) if File.exist?(KEY_PATH)
    Events.emit('identity_reset')
    { ok: true }
  end

  def status
    return { active: 'client-01', has_pending_key: false } unless File.exist?(KEY_PATH)
    return { active: 'client-01', has_pending_key: true,   note: 'keypair generated, cert not installed' } unless File.exist?(CRT_PATH)

    cert = OpenSSL::X509::Certificate.new(File.read(CRT_PATH))
    {
      active: cn_of(cert),
      has_pending_key: true,
      serial: cert.serial.to_s,
      not_after: cert.not_after.utc.iso8601
    }
  end

  def cn_of(cert)
    cert.subject.to_a.find { |k, _, _| k == 'CN' }&.dig(1)
  end
end
