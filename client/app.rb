# Control-plane HTTP server for the client.
# The dashboard calls POST /run/:scenario to trigger an mTLS request against the api.
# This is plain HTTP — the *interesting* connection is the one the client makes
# OUT to the api with mTLS (see mtls_client.rb).

require 'sinatra/base'
require 'json'
require_relative 'mtls_client'
require_relative 'identity'
require_relative 'probe'

class ClientApp < Sinatra::Base
  set :environment, :production
  disable :logging

  API_URL = ENV.fetch('API_URL', 'https://[fd00:dead:beef::20]:8443')

  get '/health' do
    'ok'
  end

  get '/probe' do
    halt 400, '{"error":"missing url"}' unless params['url']
    content_type :json
    Probe.run(params['url']).to_json
  end

  get '/interfaces' do
    content_type :json
    Probe.interfaces.to_json
  end

  get '/certs/available' do
    content_type :json
    MtlsClient.available_client_certs.to_json
  end

  # Body JSON: { "cert_path": "/certs/client.crt" } OR { "no_cert": true }
  post '/run' do
    raw = request.body.read
    opts = raw.empty? ? {} : JSON.parse(raw, symbolize_names: true)
    result = MtlsClient.new(api_url: API_URL).run(opts)
    content_type :json
    result.to_json
  rescue ArgumentError, JSON::ParserError => e
    status 400
    { error: e.message }.to_json
  end

  # --- Onboarding mTLS -----------------------------------------------------
  post '/identity/new' do
    raw = request.body.read
    cn = (JSON.parse(raw)['cn'] rescue nil) if raw && !raw.empty?
    cn ||= params['cn'] || Identity::DEFAULT_CN
    content_type 'application/x-pem-file'
    Identity.generate(cn)
  rescue ArgumentError => e
    status 400
    content_type :json
    { error: e.message }.to_json
  end

  post '/identity/install' do
    content_type :json
    pem = request.body.read
    result = Identity.install(pem)
    status(result[:ok] ? 200 : 400)
    result.to_json
  end

  post '/identity/reset' do
    content_type :json
    Identity.reset!.to_json
  end

  get '/identity/status' do
    content_type :json
    Identity.status.to_json
  end
end
