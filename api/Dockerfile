FROM ruby:3.2-alpine

RUN apk add --no-cache build-base openssl-dev tini curl

WORKDIR /app
COPY Gemfile ./
RUN bundle install --jobs 4

COPY app.rb config.ru puma.rb events.rb probe.rb authorization.rb ./
COPY entrypoint.sh ./
RUN chmod +x entrypoint.sh

ENV SERVICE_NAME=api
EXPOSE 8000 4000

ENTRYPOINT ["tini", "--"]
CMD ["/app/entrypoint.sh"]
