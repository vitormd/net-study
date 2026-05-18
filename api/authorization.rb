# Camada de autorização da api — distingue autenticação de autorização.
#
# Autenticação: o TLS já fez (cert válido assinado pela CA confiada).
# Autorização: aplicação decide se aquele CN autenticado pode chamar este endpoint.
#
# Em produção isso costuma ser uma allowlist por CN/SPIFFE-ID, escopo por endpoint,
# ou política externa (OPA, Cedar). Aqui simplificamos para uma lista global em memória,
# editável em runtime pelo dashboard pra ficar didático.

require 'set'

module Authorization
  @mutex = Mutex.new
  @allowed = Set.new

  module_function

  def init_from_env
    list = ENV.fetch('ALLOWED_CNS', 'client-01,client-02').split(',').map(&:strip).reject(&:empty?)
    @mutex.synchronize { @allowed = Set.new(list) }
  end

  def list
    @mutex.synchronize { @allowed.to_a.sort }
  end

  def allowed?(cn)
    return true if @mutex.synchronize { @allowed.empty? }   # vazio = aceita qualquer (modo aberto)
    @mutex.synchronize { @allowed.include?(cn) }
  end

  def replace(cns)
    @mutex.synchronize { @allowed = Set.new(cns.map(&:to_s).map(&:strip).reject(&:empty?)) }
    list
  end
end

Authorization.init_from_env
