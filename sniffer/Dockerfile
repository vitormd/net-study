FROM ruby:3.2-alpine

# tshark traz o dissector TLS — sabe diferenciar ClientHello, ServerHello,
# Certificate, ApplicationData etc. tcpdump só vê bytes.
RUN apk add --no-cache tshark tini

WORKDIR /app
COPY sniff.rb ./

ENTRYPOINT ["tini", "--"]
CMD ["ruby", "sniff.rb"]
