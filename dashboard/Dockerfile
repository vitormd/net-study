# Stage 1 — builda o frontend Vue (Vite) em /web/dist.
FROM node:20-alpine AS web
WORKDIR /web
COPY web/package*.json ./
RUN npm ci
COPY web/ ./
RUN npm run build

# step CLI (usado pelo /ca/sign que proxia pro step-ca).
FROM smallstep/step-ca:latest AS step-tools

# Stage 2 — servidor Ruby; serve o dist do Vite como estático.
FROM ruby:3.2-alpine

RUN apk add --no-cache build-base openssl-dev tini
COPY --from=step-tools /usr/local/bin/step /usr/local/bin/step

WORKDIR /app
COPY Gemfile ./
RUN bundle install --jobs 4

COPY app.rb config.ru probe.rb ./
COPY --from=web /web/dist ./public

ENV SERVICE_NAME=dashboard PORT=80
EXPOSE 80

ENTRYPOINT ["tini", "--"]
# -t 5:48 — cada conexão SSE prende uma thread; folga pra vários navegadores/abas.
CMD ["bundle", "exec", "puma", "-t", "5:48", "-b", "tcp://[::]:80", "config.ru"]
