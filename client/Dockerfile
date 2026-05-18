FROM smallstep/step-ca:latest AS step-tools

FROM ruby:3.2-alpine

RUN apk add --no-cache build-base openssl-dev tini curl tcpdump
COPY --from=step-tools /usr/local/bin/step /usr/local/bin/step

WORKDIR /app
COPY Gemfile ./
RUN bundle install --jobs 4

COPY app.rb config.ru events.rb mtls_client.rb identity.rb probe.rb ./
COPY entrypoint.sh ./
RUN chmod +x entrypoint.sh && mkdir -p /data

ENV SERVICE_NAME=client PORT=4000
EXPOSE 4000

ENTRYPOINT ["tini", "--"]
CMD ["/app/entrypoint.sh"]
