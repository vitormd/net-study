# api/app.rb — Sinatra app that runs behind Puma with mTLS over IPv6.
#
# Puma is configured (in puma.rb) to bind IPv6 with SSL + force_peer, so by the
# time a request reaches Sinatra the client cert has ALREADY been validated.
# Our job here is to expose the verified identity to the user and emit events.

require 'sinatra/base'
require 'openssl'
require 'json'
require_relative 'events'
require_relative 'probe'
require_relative 'authorization'

class Api < Sinatra::Base
  set :environment, :production
  disable :logging   # we emit our own events

  # Agora a api recebe HTTP puro do gateway nginx. A identidade vem em headers:
  #   X-Client-Verify    SUCCESS | FAILED:... | NONE
  #   X-Client-Subject   DN completo (ex.: "CN=client-01,O=net-study")
  #   X-Client-Issuer    DN da CA emissora
  #   X-Client-Serial    serial em hex
  #   X-Forwarded-Client-Cert  padrão XFCC (Envoy / ALB)
  #
  # Como a api só escuta em rede interna (sem porta exposta pro host), confiar
  # nesses headers é seguro — só o gateway consegue setar.
  helpers do
    def peer_identity(env)
      verify = env['HTTP_X_CLIENT_VERIFY']
      return nil unless verify == 'SUCCESS'
      subject = env['HTTP_X_CLIENT_SUBJECT']
      return nil unless subject

      cn = subject[/CN=([^,\/]+)/, 1]
      {
        cn:      cn,
        subject: subject,
        issuer:  env['HTTP_X_CLIENT_ISSUER'],
        serial:  env['HTTP_X_CLIENT_SERIAL'],
        xfcc:    env['HTTP_X_FORWARDED_CLIENT_CERT']
      }
    end
  end

  # Every request: emit a "request_received" event with the verified peer identity.
  before do
    id = peer_identity(request.env)
    Events.emit('request_received',
      direction:   'client->gateway->api',
      path:        request.path,
      method:      request.request_method,
      peer_cn:     id&.dig(:cn),
      peer_issuer: id&.dig(:issuer),
      peer_serial: id&.dig(:serial),
      via:         'nginx (XFCC header)',
      remote_ip:   request.env['REMOTE_ADDR'])
  end

  after do
    Events.emit('request_completed',
      direction: 'api->client',
      path:      request.path,
      status:    response.status)
  end

  # mTLS termina no gateway (nginx). A api confia no header XFCC pra identidade
  # e aplica autorização (allowlist de CNs).
  get '/whoami' do
    id = peer_identity(request.env)
    halt 401, "no client identity in headers — gateway rejeitou ou bypass detectado" unless id

    cn = id[:cn]
    unless Authorization.allowed?(cn)
      Events.emit('authorization_denied',
        cn: cn, reason: 'CN not in allowlist',
        allowlist: Authorization.list)
      halt 403, { error: 'forbidden', cn: cn,
                  reason: 'authenticated by mTLS (api-gateway) but CN is not in the allowlist',
                  allowlist: Authorization.list }.to_json
    end

    content_type :json
    {
      you_are:     cn,
      issued_by:   id[:issuer],
      serial:      id[:serial],
      via:         'mTLS terminated at nginx api-gateway',
      xfcc_header: id[:xfcc],
      message:     "Hello #{cn}, mTLS verified by api-gateway and your CN is on the allowlist."
    }.to_json
  end

  get '/health' do
    'ok'
  end

  # Plano de controle (exposto na porta 4000, plain HTTP). Não requer mTLS.
  get '/probe' do
    halt 400, '{"error":"missing url"}' unless params['url']
    content_type :json
    Probe.run(params['url']).to_json
  end

  get '/interfaces' do
    content_type :json
    Probe.interfaces.to_json
  end

  # Allowlist (exposta na porta de controle, port 4000 — sem mTLS).
  get '/authorization' do
    content_type :json
    { allowed_cns: Authorization.list }.to_json
  end

  put '/authorization' do
    body = JSON.parse(request.body.read) rescue {}
    cns  = body['allowed_cns'].is_a?(Array) ? body['allowed_cns'] : []
    new_list = Authorization.replace(cns)
    Events.emit('authorization_updated', allowlist: new_list)
    content_type :json
    { allowed_cns: new_list }.to_json
  end
end
