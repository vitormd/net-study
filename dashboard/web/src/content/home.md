# net-study

**Um laboratório para explorar tópicos de rede visualmente.**

A ideia do net-study é simples: conceitos de rede como **mTLS** e **IPv6** são
quase sempre aprendidos lendo RFCs e diagramas estáticos. Aqui você *vê* —
cada handshake TLS, cada pacote na bridge, cada certificado sendo emitido e
rotacionado acontece ao vivo na tela, com serviços reais conversando numa
rede Docker.

Não é uma simulação: são containers de verdade (`client`, `api-gateway`,
`api`, `step-ca`, `dashboard`, `sniffer`) trocando tráfego real sobre IPv6.

## O que dá pra fazer hoje

### Aba mTLS

- **Onboarding de identidade** — gere um par de chaves no `client`, mande o
  CSR pra CA (step-ca), receba o certificado e instale. O fluxo copy-paste
  torna visível o que trafega (CSR e cert) e o que nunca sai do container
  (a chave privada).
- **Autorização (allowlist)** — edite a lista de CNs aceitos pela api e veja
  a diferença entre *autenticação* (o cert é válido) e *autorização* (o CN
  pode chamar): um cert legítimo fora da lista leva 403 mesmo com o
  handshake completo.
- **Disparar requisições** — com ou sem certificado, escolhendo entre certs
  válidos, expirados ou de uma CA não confiável. O diagrama anima cada etapa
  do handshake e o log lista os eventos TLS.

### Aba IPv6

- **Topologia da rede** — o grafo dos containers com seus endereços ULA
  `fd00:dead:beef::/64`, os caminhos de mTLS, PKI e telemetria.
- **Probe externo** — dispare um `GET` a partir de qualquer nó interno e veja
  IPv4 e IPv6 lado a lado: resolução A/AAAA, qual família conectou, latência.
- **Anatomia de um endereço IPv6** — decomponha qualquer endereço em prefixo,
  sub-rede e ID de interface, com a classificação (global, ULA, link-local,
  multicast…).

### Sniffer (sempre visível à direita)

Um `tshark` rodando na bridge da rede captura o tráfego dos containers e
dissecа os registros TLS — você vê `ClientHello`, `ServerHello`,
`Certificate`, `ChangeCipherSpec` e `ApplicationData` passando em tempo real,
coloridos por tipo.

## Por baixo

Cada peça espelha um padrão de produção real:

- **step-ca** emite certificados de curta duração (24h) com renovação
  automática — como Vault PKI ou cert-manager.
- **api-gateway** (nginx) termina mTLS e repassa a identidade via header
  `X-Forwarded-Client-Cert` — como nginx-ingress, AWS ALB ou Envoy.
- **api** aplica autorização sobre a identidade autenticada.

Use as abas acima para começar a explorar.
