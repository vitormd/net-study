# net-study

> Laboratório interativo para aprender **mTLS** e **IPv6** mexendo, não lendo.

Três serviços Ruby (`client`, `api`, `dashboard`) conversam numa rede Docker IPv6, com certificados emitidos por uma **CA online (step-ca)** com TTL de 24h e **renovação automática**. Um dashboard web mostra cada handshake TLS acontecendo em tempo real, deixa você executar o **fluxo completo de onboarding mTLS** (CSR → assinatura → instalação) e tem uma aba IPv6 com **grafo da rede**, **probes externos** e um **decodificador de endereços IPv6**.

Sem framework de mesh, sem dependência cloud. Roda local em `docker compose up`.

## Captura rápida

> Capture os PNGs e ponha em `docs/img/`:
> - `docs/img/mtls.png` — aba mTLS com sniffer ao lado depois de um request OK.
> - `docs/img/onboarding.png` — os 3 cards de CSR/assinatura/instalação com CN custom.
> - `docs/img/allowlist.png` — request bloqueado por autorização (403 com handshake OK).
> - `docs/img/ipv6-graph.png` — grafo da rede com step-ca + sniffer.
> - `docs/img/decoder.png` — decodificação de `fd00:dead:beef::20`.

## Para quem é

Quem leu sobre mTLS, leu sobre IPv6, e quer **ver** os dois funcionando antes de aplicar em produção. Útil para:

- Engenheiros backend pegando mTLS pela primeira vez.
- Quem vai integrar uma API B2B via mTLS e quer ensaiar o fluxo de CSR.
- Quem quer entender por que IPv6 não é "só um endereço maior".
- Workshops e estudos em grupo.

## Subir o lab

```bash
git clone <url-do-seu-fork> net-study
cd net-study
docker compose up --build
```

Abra **http://localhost:8080**. Pronto.

Pré-requisitos:

- Docker Desktop com **IPv6 habilitado** (*Settings → Resources → Network → Enable IPv6*).
- **Recursos**: roda confortável em **1 vCPU + 500MB RAM**. O `docker-compose.yml` traz `mem_limit`/`cpus` por serviço somando ~472MB; em regime, o consumo real é ~220MB (o `sniffer`/tshark é o maior). Se algum container for OOM-killed na sua máquina, suba o `mem_limit` dele.

Na primeira subida o **step-ca auto-inicializa** (root + intermediate CA, provisioner JWK `admin` com senha `changeme-lab`), depois um init container gera os fixtures `wrong-client.crt` e `client-expired.crt`. api e client puxam seus próprios certs do step-ca no entrypoint e iniciam threads de renovação (24h TTL).

Limpeza: `docker compose down -v` (o `-v` apaga o volume da PKI; nova subida gera CA nova).

> **Sobre o sniffer**: roda em `network_mode: host` + `privileged`, ou seja, dentro da network namespace da VM do Docker, onde vivem as bridges. Capturando na bridge da rede `lab6` ele vê todo o tráfego entre containers da rede em **um único processo**. No startup descobre os IPs de `api`, `client` e `step-ca` e monta um filtro BPF que inclui esses três nós + portas 8443 (mTLS), 443 (probes externos) e 9000 (PKI). Em rebuild de qualquer componente, basta `docker compose up -d --build` e tudo recupera.

### Desenvolver o frontend

O dashboard é uma SPA Vue 3 (Vite) em `dashboard/web/`. Em produção o build é estático, gerado dentro do Docker (multistage) e servido pelo Sinatra. Para iterar no front com hot reload:

```bash
docker compose up -d            # backend roda em :8080
cd dashboard/web
npm install
npm run dev                     # Vite em :5173, proxy dos endpoints pro :8080
```

Abra **http://localhost:5173** — HMR ativo; os endpoints (`/stream`, `/topology`, `/trigger`, …) são proxiados pro backend em `:8080` (veja `vite.config.js`).

## Arquitetura

```
        Rede Docker IPv6 — fd00:dead:beef::/64
   ┌────────────────────────────────────────────────────────────────┐
   │                ┌──────────────┐                                │
   │   cert/renew   │   step-ca    │  sign CSR                      │
   │ ┌──────────────┤  ::10 :9000  ├──────────┐                     │
   │ │              └────────┬─────┘          │                     │
   │ ▼                       │                ▼                     │
   │ ┌─────────┐ HTTPS mTLS  │       ┌──────────────┐ HTTP+XFCC  ┌──────┐
   │ │ client  │────────────▶│       │ api-gateway  │──────────▶ │ api  │
   │ │  ::21   │             │       │ nginx ::25   │  :8000     │ ::20 │
   │ └────┬────┘             │       │   :8443      │            └──┬───┘
   │      │                  │       └──────┬───────┘               │
   │      │ events  ┌────────▼──────┐ events│                events │
   │      └────────▶│   dashboard   │◀──────┴────────────────────-──┘
   │                │   ::30 :80    │ SSE → navegador
   │                └───────────────┘
   │
   │   ┌─────────┐ tshark na bridge da lab6 (TLS dissector)
   │   │ sniffer │ → /packet → SSE → dock à direita
   │   └─────────┘ (api-gateway, api, client, step-ca; dashboard fora)
   └──────────────────────────────────────────────────────────────┘
                     ▲
                  http://localhost:8080
```

A comunicação **client → api-gateway é mTLS sobre IPv6** — é a "lição". O **api-gateway (nginx) termina mTLS** e repassa HTTP puro pra api com header `X-Forwarded-Client-Cert` (XFCC). É o padrão usado por nginx-ingress, AWS ALB, Envoy.
**Tudo que envolve cert (emissão, renovação, assinatura de CSR) passa pelo step-ca.**
A comunicação **serviços → dashboard é HTTP simples** — é o "plano de controle", separado de propósito.

## Aba mTLS

Tudo o que demonstra autenticação mútua via certificados.

### Onboarding (3 cards no topo)

Replica o ritual que toda integração mTLS B2B faz em produção:

1. **Gerar par no client** — você digita um **CN** (default `client-02`, pode ser `acme-prod`, `staging-bot`, etc.). O container do `client` cria uma chave RSA 2048 e um CSR com esse CN. A chave privada **nunca sai do container**.
2. **Assinar CSR (CA)** — você cola o CSR num textarea. O dashboard atua como **portal**: pede um token JWK ao step-ca usando senha do provisioner, submete o CSR + token, recebe o cert assinado pelo intermediate CA do step-ca (TTL 24h) e devolve.
3. **Instalar no client** — você cola o cert de volta. O client valida (a) chain contra a CA confiada e (b) que a chave pública bate com a privada que ele guardou. Se tudo OK, a partir daí o `client` passa a se autenticar com a nova identidade.

O copy-paste manual é proposital: torna visível o que trafega (CSR e cert, ambos públicos) e o que não trafega (a chave privada).

### Autorização na api (allowlist de CNs)

Logo abaixo do onboarding tem um painel pra editar a **allowlist de CNs** aceitos pela api. mTLS resolve a *autenticação* (cert válido, chain OK); a *autorização* é separada. Tire um CN da lista → request com aquele cert completa o handshake mas leva **403** com `reason: "authenticated by mTLS but CN is not in the allowlist"`. É o que API B2B real faz com OPA, Cedar ou allowlist em código.

Default: `client-01`, `client-02`. Se você gerar uma identidade com CN custom (ex.: `acme-prod`), adicione na allowlist antes de testar.

### Disparar uma requisição

Dois botões:

- **Request sem certificado** — `client` abre a conexão sem apresentar cert. O servidor (`force_peer`) rejeita no handshake.
- **Request c/ certificado** — usa o cert selecionado no dropdown abaixo. O dropdown lista todos os certs com EKU `clientAuth` que o `client` tem disponível: o emitido pelo step-ca no startup (rota automática ↻), os fixtures de teste (wrong-ca, expired) e a identidade do onboarding.

Combinando dropdown + botão você cobre os cenários canônicos:

| Cert escolhido                  | O que acontece                                                                   |
|---------------------------------|----------------------------------------------------------------------------------|
| `client.crt (step-ca, rota ↻)`  | 200 OK, `you_are: client-01`, `via: mTLS terminated at nginx api-gateway`        |
| `<cn>.crt (onboarded)`          | 200 OK com o CN custom — desde que esteja na allowlist                           |
| `client-expired.crt`            | **api-gateway** (nginx) rejeita com 400 "SSL certificate error" — handshake falha |
| `wrong-client.crt`              | api-gateway rejeita: cert assinado por CA não confiada                            |

### Diagrama animado + log + sniffer ao vivo

Cada request emite eventos (`tcp_connecting`, `tls_handshake_starting`, `tls_handshake_completed`, `request_received`, `http_response`, `authorization_denied`...) que viajam via SSE. O diagrama central anima o "pacote" do client ao api a cada etapa. O log abaixo lista cada evento com `ts · source · type · detalhes`; cada linha é expansível pro JSON cru.

À direita, fixo na tela como num IDE, fica o **dock do sniffer** com **dissector TLS via `tshark`**: cada linha mostra `src:port → dst:port` + **rótulo do tipo de record** (ClientHello, ServerHello, Certificate, ChangeCipherSpec, ApplicationData...) + SNI + versão TLS, coloridos por tipo:

- 🔵 ClientHello (azul) — você vê o SNI que o cliente pediu.
- 🟢 ServerHello / Finished (verde) — cipher suite negociada.
- 🟣 Certificate / CertificateVerify (lilás) — chain trafegando.
- 🟡 ChangeCipherSpec (âmbar) — pivô pra criptografia.
- 🟢 ApplicationData — dados criptografados (após o handshake).
- 🟠 SYN / 🔴 RST / cinza ACK / FIN.

## Aba IPv6

Saiu do tema "como o lab usa IPv6" e virou um cantinho dedicado.

### Grafo da rede

SVG com sete nós:

- `step-ca` (PKI, `::10:9000`) — tracejado roxo. Não interage com probe.
- `api-gateway` (nginx, `::25:8443`) — termina mTLS, não tem `/probe`.
- `api` (`::20:8000`), `client` (`::21`), `dashboard` (`::30:80`) — selecionáveis como origem do probe.
- `sniffer` (host netns, bridge) — tracejado amarelo, mostra os 4 nós que ele captura.
- `internet` — destino do probe externo.

Linhas:
- contínuas para fluxo normal (`client → api-gateway` mTLS, `api-gateway → api` HTTP+XFCC, events);
- **roxas tracejadas** para tráfego de PKI (api-gateway/api/client/dashboard → step-ca);
- **amarelas tracejadas** indicando que o sniffer "ouve" aquele nó;
- pontilhada para a saída pra internet.

Clicar em api, client ou dashboard escolhe a origem do probe.

### Probe externo

Faz `GET` num endpoint público — a partir do nó que você selecionou. O backend:

1. Resolve A e AAAA separadamente via `Resolv::DNS`.
2. Para cada um, abre TCP forçando aquela family.
3. Se HTTPS, faz o handshake TLS.
4. Manda um HTTP/1.1 mínimo e lê a resposta.

Você vê **lado a lado** o que aconteceu em IPv4 e em IPv6. Presets:

- `ifconfig.co/json` — Cloudflare, retorna JSON rico (IP, país, ASN).
- `api64.ipify.org` — clássico, leve.
- `v6.ident.me` — **só tem AAAA**. O card IPv4 mostra `no A record` — exatamente a lição de um endpoint IPv6-only.
- Campo livre para outro URL.

### Anatomia de um endereço IPv6

Cola um endereço, decompõe em barra de bits colorida + cards explicativos. Identifica:

- `2000::/3` global unicast → IANA / RIR / ISP / subnet / interface ID
- `fc00::/7` ULA → prefix / global ID 40-bit / subnet / interface
- `fe80::/10` link-local → não atravessa roteador
- `2001:db8::/32` documentação (RFC 3849)
- `ff00::/8` multicast (IPv6 não tem broadcast)
- `::1` loopback

É a feature que transforma `fd00:dead:beef::20` de "string aleatória" em "esse hextet aqui é a subnet, esses 64 bits no fim são o interface ID".

## Layout do código

```
net-study/
├── README.md
├── docker-compose.yml
│
├── api-gateway/                       # nginx reverse proxy — termina mTLS na frente da api
│   ├── entrypoint.sh              #   pega cert do step-ca, sobe nginx, daemon de renew
│   ├── nginx.conf                 #   ssl_verify_client on + headers XFCC pra upstream
│   └── Dockerfile
│
├── api/                           # app server — recebe HTTP puro do api-gateway
│   ├── entrypoint.sh              #   só sobe o puma; sem TLS
│   ├── puma.rb                    #   bind plain HTTP em :8000 e :4000
│   ├── app.rb                     #   /whoami (lê XFCC), /probe + /authorization
│   ├── authorization.rb           #   allowlist de CNs em memória
│   ├── events.rb                  #   POST /events → dashboard
│   └── probe.rb                   #   resolve A/AAAA, tenta v4 e v6 separadamente
│
├── client/                        # quem fala mTLS com o api-gateway
│   ├── entrypoint.sh              #   pega cert do step-ca + daemon de renew
│   ├── app.rb                     #   /run (dispara request), /identity/{new,install,reset}
│   ├── mtls_client.rb             #   conexão TLS manual com hooks por etapa
│   ├── identity.rb                #   gera keypair + CSR, valida e instala cert
│   └── probe.rb
│
├── dashboard/                     # backend Sinatra + SPA Vue
│   ├── app.rb                     #   /events (ingest), /stream (SSE), /ca/sign (proxy step-ca),
│   │                              #   /trigger, /probe-from/:node, /api/authorization, ...
│   ├── probe.rbs
│   ├── Dockerfile                 #   multistage: builda o Vue, depois serve via Sinatra
│   └── web/                       #   SPA em Vue 3 (Composition API, Vite, Reka UI)
│       └── src/
│           ├── App.vue            #     shell: tabs + sniffer dock
│           ├── components/        #     mtls/* e ipv6/* — um componente por painel
│           ├── composables/       #     useSSE, useEventLog, useIdentity, useProbe, ...
│           └── lib/               #     lógica pura (decoder IPv6, classificação de pacote)
│
├── sniffer/                       # tshark na bridge da rede lab6 (TLS dissector)
│   └── sniff.rb                   #   descobre IPs de api/client/api-gateway/step-ca; parsing TLS
│
└── test-certs-init/               # one-shot container, gera fixtures wrong-* e expired
    └── gen-test-certs.sh
```

Vale ler os arquivos nessa ordem:

1. `docker-compose.yml` — entende a topologia inteira (step-ca + api + client + dashboard + sniffer + init).
2. `api/entrypoint.sh` — bootstrap mTLS real: pega cert do step-ca, sobe app, daemoniza renew.
3. `api/puma.rb` — `force_peer` + `ca`. É isso que liga mTLS.
4. `client/mtls_client.rb` — handshake TLS na unha, ótimo para ver as etapas separadas.
5. `dashboard/app.rb#post '/ca/sign'` — como um portal mTLS B2B faz: recebe CSR, pede token JWK ao step-ca, devolve cert.
6. `dashboard/web/src/composables/useSSE.js` — conexão SSE única que alimenta log, diagrama e sniffer.

## O que você efetivamente aprende

| Conceito                                                | Onde você vê                                                                 |
|---------------------------------------------------------|------------------------------------------------------------------------------|
| `force_peer` no servidor é o que vira TLS em mTLS       | `api/puma.rb`                                                                |
| A identidade autenticada é o `subject.CN` do cert       | `api/app.rb#whoami` retorna o CN                                             |
| **Autenticação ≠ autorização**                          | edite a allowlist e veja 200 OK virar 403 mantendo o handshake OK            |
| `verify_hostname=true` no cliente checa SAN             | `client/mtls_client.rb` — wrong-host scenario cairia antes mesmo da api ver  |
| A private key nunca trafega                             | onboarding inteiro: só CSR e cert atravessam                                 |
| Como uma CA emite um cert a partir de um CSR            | `dashboard/app.rb#post '/ca/sign'` (proxy para step-ca via token JWK)        |
| **Rotação automática de cert sem downtime**             | `entrypoint.sh` da api/client roda `step ca renew --daemon`                  |
| **Como o handshake mTLS realmente parece na rede**      | sniffer dock à direita: SYN → ClientHello → Certificate → Finished → dados   |
| IPv6 ULA é o "192.168" do IPv6                          | `fd00:dead:beef::/64` na rede do compose                                     |
| `::` (todas interfaces) ≠ `0.0.0.0`                     | `puma.rb` binda em `[::]:8443`                                               |
| IPv6 tem estrutura hierárquica                          | aba IPv6 → decoder                                                           |
| Docker Desktop tem IPv6 NAT funcional                   | probe IPv6 saindo do container chega na internet                             |

## Paralelos com produção

| Coisa do lab                       | Coisa real                                     |
|-----------------------------------|-------------------------------------------------|
| `step-ca` container                | Vault PKI, AWS Private CA, GCP CAS, cert-manager Issuer |
| Provisioner JWK + senha            | OIDC, X5C, AWS IID, K8s ServiceAccount (SPIRE)  |
| TTL de 24h + renew em background   | mesma coisa em prod (TTLs ainda mais curtos)    |
| `ssl_verify_client on` no nginx (api-gateway) | mesmo padrão em qualquer ingress (nginx-ingress, AWS ALB, Envoy) |
| CN como autorização (allowlist)    | OPA/Cedar policy sobre `subject` ou SPIFFE-ID   |
| Telemetria via dashboard           | Sidecar Envoy + control plane (Istiod, etc.)    |
| Dashboard proxia /ca/sign          | Portal de onboarding / Vault Agent / cert-manager CertificateRequest |

## Limitações conscientes

- Senha do provisioner JWK é estática (`changeme-lab`). Em produção: OIDC, SPIFFE, IAM federation.
- Sem CRL/OCSP — TTL curto resolve. Discutido teoricamente.
- Sem policy na CA além de TTL máximo. Em produção: allowlist por organização, escopos por endpoint.
- Mesh real (Istio, Linkerd, SPIRE) faz **workload attestation** antes de emitir. O lab pula isso.
- O probe IPv6/IPv4 usa HTTP/1.1 manual. Suficiente para o eco, não cobre HTTP/2/3.

## Próximas ideias

- **Botão "force renew"** no painel mTLS, disparando `step ca renew --force` no api-gateway ou no client — a rotação acontece ao vivo no sniffer.
- **ACME provisioner** no step-ca pra demonstrar o fluxo Let's Encrypt-style (challenge → key authorization → cert) ao lado do JWK que já existe.
- **SPIFFE-ID em SAN URI** (`spiffe://net-study.local/api`) no lugar de CN — mostra a identidade "moderna" usada por SPIRE/Istio.
- **Múltiplas identidades simultâneas** no onboarding (deixar `acme-prod` E `staging-bot` instalados ao mesmo tempo no client, escolher qual usar por request).
- **Token bound to cert** (cnf claim / DPoP) — api emite JWT amarrado ao fingerprint do cert; chamadas subsequentes exigem token + cert e a api checa que batem. Padrão OAuth 2 mTLS.
- **Decoder de IPv6 expandido**: mapear `2xxx::/12` para o RIR correspondente (LACNIC, ARIN, RIPE, APNIC, AfriNIC) sem precisar de API externa.
- **Happy Eyeballs racing** no probe — disparar v4 e v6 simultaneamente, mostrar quem chega primeiro e o RTT.
- **Audit log da CA** — pegar o log do step-ca e expor no dashboard como timeline.
- **Túnel 6in4 educacional** — container intermediário que encapsula IPv6 em IPv4, ensinando como a transição funcionou na vida real.

## Licença

MIT, faça o que quiser. Se achou útil, manda um ⭐.
