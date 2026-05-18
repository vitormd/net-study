# Tiny event emitter — fire-and-forget POST to the dashboard's /events endpoint.
# We never want event emission to break the request path, so all errors are swallowed.

require 'net/http'
require 'uri'
require 'json'
require 'time'

module Events
  module_function

  def emit(type, attrs = {})
    url = ENV['DASHBOARD_URL']
    return unless url

    payload = {
      ts:     Time.now.utc.iso8601(3),
      source: ENV.fetch('SERVICE_NAME', 'api'),
      type:   type
    }.merge(attrs)

    Thread.new do
      begin
        uri = URI("#{url}/events")
        http = Net::HTTP.new(uri.host.to_s.delete('[]'), uri.port)
        http.open_timeout = 1
        http.read_timeout = 1
        req = Net::HTTP::Post.new(uri.path, 'Content-Type' => 'application/json')
        req.body = payload.to_json
        http.request(req)
      rescue StandardError
        # ignore — telemetry is best-effort
      end
    end
  end
end
